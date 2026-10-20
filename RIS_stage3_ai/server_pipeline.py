"""One-worker resumable server pipeline with subprocess logs and live heartbeat."""
import argparse
import os
from pathlib import Path
import platform
import shutil
import signal
import subprocess
import sys
import time
import traceback

from .protocol import load_protocol, require_execution_host
from .storage import atomic_json, digest, directory_lock, file_hash, now, read_json

ROOT = Path(__file__).resolve().parent.parent
STAGES = ('data', 'training', 'comparison', 'metrics', 'budget', 'budget_metrics')


def process_identity(pid):
    """Linux boot + kernel process start time prevents PID-reuse false positives."""
    try:
        stat = Path(f'/proc/{pid}/stat').read_text()
        tail = stat[stat.rfind(')')+2:].split()
        return dict(pid=pid, start_ticks=tail[19],
                    boot=Path('/proc/sys/kernel/random/boot_id').read_text().strip())
    except (OSError, IndexError):
        return None


def resources(device):
    info = dict(host=platform.node(), available_memory_gib=None,
                free_disk_gib=shutil.disk_usage(ROOT).free/2**30, gpu=[])
    if sys.platform == 'linux':
        values = dict(line.split(':', 1) for line in Path('/proc/meminfo').read_text().splitlines())
        info['available_memory_gib'] = int(values['MemAvailable'].split()[0])/2**20
    if device.startswith('cuda'):
        output = subprocess.check_output(['nvidia-smi', '--query-gpu=index,memory.free,utilization.gpu',
                                          '--format=csv,noheader,nounits'], text=True)
        info['gpu'] = [dict(zip(('index','free_mib','utilization_percent'), map(int, line.split(','))))
                       for line in output.strip().splitlines()]
    return info


def resource_guard(device, *, smoke=False):
    info = resources(device)
    if not smoke:
        if info['free_disk_gib'] < 50 or (info['available_memory_gib'] or 0) < 12:
            raise RuntimeError(f'Insufficient disk/memory: {info}')
        if not device.startswith('cuda:') or os.environ.get('CUDA_VISIBLE_DEVICES'):
            raise ValueError('Formal runner requires explicit physical cuda:N without CUDA_VISIBLE_DEVICES remapping')
        index = int(device.split(':')[1])
        gpu = next((g for g in info['gpu'] if g['index'] == index), None)
        if gpu is None or gpu['free_mib'] < 6000 or gpu['utilization_percent'] > 20:
            raise RuntimeError(f'Selected GPU is not available: {info}')
    return info


def commands(run, device, smoke):
    flag = ['--smoke'] if smoke else []
    prefix = [sys.executable, '-X', 'utf8', '-u', '-m']
    def cmd(module, *args):
        return prefix+['RIS_stage3_ai.'+module]+list(map(str, args))
    return dict(
        data=cmd('generate_dataset', '--output', run/'data', *flag),
        training=cmd('train', '--dataset', run/'data', '--output', run/'training', '--device', device, *flag),
        comparison=cmd('run_comparison', '--dataset', run/'data', '--training', run/'training',
                       '--output', run/'comparison', '--device', device, *flag),
        metrics=cmd('aggregate', '--source', run/'comparison', '--output', run/'metrics'),
        budget=cmd('run_budget', '--source', run/'comparison', '--training', run/'training',
                   '--output', run/'budget', '--device', device, *flag),
        budget_metrics=cmd('aggregate_budget', '--source', run/'budget', '--output', run/'budget_metrics'))


def verify_stage(run, stage):
    """Verify persisted stage counts; successful child exit alone is insufficient."""
    if stage == 'data':
        from .generate_dataset import validate_manifest, progress
        result = progress(run/'data', validate_manifest(read_json(run/'data/manifest.json'), current_sources=True))
    elif stage == 'training':
        from .train import training_status
        result = training_status(run/'training')
    elif stage == 'comparison':
        from .run_comparison import validate_comparison, scan_results, result_progress
        m = validate_comparison(read_json(run/'comparison/manifest.json'), current_sources=True)
        result = result_progress(m, scan_results(run/'comparison', m))
    elif stage == 'budget':
        from .run_budget import scan, progress
        m = read_json(run/'budget/manifest.json')
        if m['id'] != digest(m['identity']):
            raise ValueError('Budget manifest mismatch')
        result = progress(m, scan(run/'budget', m))
    else:
        result = read_json(run/stage/'report.json')['progress']
    if not result.get('complete'):
        raise RuntimeError(f'Stage {stage} exited without complete audited outputs: {result}')
    return result


def run_pipeline(output, *, device='cuda:0', smoke=False, through='budget_metrics'):
    output = Path(output).resolve()
    require_execution_host(load_protocol(smoke=smoke))
    if through not in STAGES:
        raise ValueError('Unknown terminal stage')
    # One resource lock across all runs under the experiment parent directory.
    with directory_lock(output.parent/'.ai_server_resource_lock'), directory_lock(output) as owner:
        hashes = {str(p.relative_to(ROOT)).replace('\\','/'): file_hash(p)
                  for folder in ('RIS_stage3_ai','RIS_stage3')
                  for p in sorted((ROOT/folder).iterdir()) if p.suffix in ('.py','.json','.sh')}
        identity = dict(schema=1, profile='smoke' if smoke else 'full', device=device,
                        python=sys.executable, sources=hashes, workers=1, blas_threads=4)
        manifest = dict(id=digest(identity), identity=identity)
        if (output/'pipeline_manifest.json').exists():
            if read_json(output/'pipeline_manifest.json') != manifest:
                raise ValueError('Immutable pipeline identity changed; use a new run directory')
        else:
            atomic_json(output/'pipeline_manifest.json', manifest)
        state = dict(state='RUNNING', owner=owner, process=process_identity(os.getpid()),
                     stage=None, through=through, completed_stages=[], started=now(), updated=now())
        child = None
        def interrupted(signum, frame):
            raise KeyboardInterrupt(f'signal {signum}')
        previous = {}
        for sig in (signal.SIGINT, signal.SIGTERM):
            previous[sig] = signal.signal(sig, interrupted)
        try:
            state['resources_at_start'] = resource_guard(device, smoke=smoke)
            atomic_json(output/'pipeline_state.json', state)
            env = dict(os.environ, OMP_NUM_THREADS='4', OPENBLAS_NUM_THREADS='4', MKL_NUM_THREADS='4',
                       NUMEXPR_NUM_THREADS='4', MPLBACKEND='Agg', PYTHONUNBUFFERED='1')
            for stage, command in commands(output, device, smoke).items():
                # Always re-enter resumable stages to verify immutable identities.
                state.update(stage=stage, command=command, updated=now())
                logdir = output/'logs'
                logdir.mkdir(exist_ok=True)
                logpath = logdir/f'{stage}_{time.time_ns()}.log'
                state['log'] = str(logpath)
                print(f'PIPELINE START {stage} log={logpath}', flush=True)
                with logpath.open('ab', buffering=0) as log:
                    child = subprocess.Popen(command, cwd=ROOT, env=env, stdout=log, stderr=subprocess.STDOUT)
                    state['child'] = process_identity(child.pid) or dict(pid=child.pid)
                    while child.poll() is None:
                        state.update(updated=now())
                        atomic_json(output/'pipeline_state.json', state)
                        time.sleep(5)
                    code = child.returncode
                    child = None
                state['child'] = None
                if code != 0:
                    raise RuntimeError(f'{stage} failed with exit={code}; see {logpath}')
                state['last_audit'] = verify_stage(output, stage)
                state['completed_stages'].append(stage)
                atomic_json(output/'pipeline_state.json', state)
                print(f'PIPELINE VERIFIED {stage}', flush=True)
                if stage == through:
                    break
            state.update(state='COMPLETE' if through == STAGES[-1] else 'PAUSED_AFTER_STAGE', updated=now())
        except BaseException as exc:
            if child is not None and child.poll() is None:
                child.terminate()
                try:
                    child.wait(timeout=15)
                except subprocess.TimeoutExpired:
                    child.kill()
                    child.wait(timeout=15)
            state.update(state='INTERRUPTED' if isinstance(exc, KeyboardInterrupt) else 'FAILED',
                         error=str(exc), traceback=traceback.format_exc(), updated=now(), child=None)
            atomic_json(output/'failures'/f'pipeline_{time.time_ns()}.json', state)
            raise
        finally:
            atomic_json(output/'pipeline_state.json', state)
            for sig, handler in previous.items():
                signal.signal(sig, handler)
    return state


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--device', default='cuda:0')
    parser.add_argument('--smoke', action='store_true')
    parser.add_argument('--through', choices=STAGES, default=STAGES[-1])
    args = parser.parse_args()
    print(run_pipeline(**vars(args)), flush=True)


if __name__ == '__main__':
    main()
