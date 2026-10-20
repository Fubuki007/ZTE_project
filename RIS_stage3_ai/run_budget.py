"""Full-test-set paired RMSE at preregistered wall-clock design budgets."""
import argparse
from pathlib import Path
import tempfile
import time
import traceback
import platform
import numpy as np
import scipy
import torch
from threadpoolctl import threadpool_limits

from RIS_stage3.stage3_model import Model
from RIS_stage3.streaming import simulate_block, coarse_from_records
from RIS_stage3.collect_rmse import match_errors
from .budget_design import METHODS, BUDGETS, timed_design, NoTimelyDesign
from .context import context_from_model
from .generate_dataset import ROOT, sealed, verify_seal
from .protocol import model_config, require_execution_host
from .repair import InfeasibleDesign
from .run_comparison import (validate_comparison, scan_results, result_progress,
                             run_method, sources as comparison_sources)
from .storage import atomic_json, read_json, digest, file_hash, directory_lock, now
from .train import load_selected, setup_runtime
from .unfolded_design import UnfoldedDesigner


def sources():
    return dict(comparison_sources(), **{n: file_hash(ROOT/n) for n in (
        'RIS_stage3_ai/budget_design.py', 'RIS_stage3_ai/run_budget.py')})


def keys():
    return [(m, b, f'{m}_{b:g}s') for m in METHODS for b in BUDGETS]


def scan(output, manifest):
    records = {}
    scenes = {s['scene_id']: s for s in manifest['identity']['scenes']}
    for case in manifest['identity']['cases']:
        for method, budget, key in keys():
            path = Path(output)/'samples'/case['sample_id']/f'{key}.json'
            if not path.exists():
                continue
            r = verify_seal(read_json(path))
            if (r['manifest_id'] != manifest['id'] or r['case'] != case or
                    r['key'] != key or r['budget_seconds'] != budget or r['method'] != method):
                raise ValueError('Budget result identity mismatch')
            pairing = manifest['identity']['coarse_pairing'][case['sample_id']]
            if r['coarse_sha256'] != pairing['sha256'] or r['noise_variance'] != pairing['noise_variance']:
                raise ValueError('Budget noise/coarse pairing mismatch')
            if r['status'] not in ('SUCCESS', 'DEADLINE_MISS', 'ALGORITHM_FAILURE'):
                raise ValueError('Invalid terminal budget status')
            if r['status'] == 'SUCCESS':
                t = r['design']['budget_timing']
                if not r['design']['final']['feasible'] or t['candidate_ready_seconds'] > budget:
                    raise ValueError('Late or infeasible design was scored')
                errors, order = match_errors(np.array(r['estimate']), scenes[case['scene_id']]['truth'])
                if not np.allclose(errors, r['errors'], rtol=0, atol=1e-10) or order.tolist() != r['assignment']:
                    raise ValueError('Budget metric audit failed')
            records[(case['sample_id'], key)] = r
    if len(list((Path(output)/'samples').glob('*/*.json'))) != len(records):
        raise ValueError('Unexpected budget result file')
    return records


def progress(manifest, records):
    expected = len(manifest['identity']['cases'])*len(keys())
    return dict(terminal=len(records), expected=expected, complete=len(records) == expected,
                successful=sum(r['status'] == 'SUCCESS' for r in records.values()),
                deadline_misses=sum(r['status'] == 'DEADLINE_MISS' for r in records.values()),
                algorithm_failures=sum(r['status'] == 'ALGORITHM_FAILURE' for r in records.values()), updated=now())


def run(source, training, output, *, device='cpu', smoke=False, limit=None):
    source, training, output = map(lambda p: Path(p).resolve(), (source, training, output))
    if any(output == p or output in p.parents or p in output.parents for p in (source, training)):
        raise ValueError('Use separate input/output directories')
    if limit is not None and (type(limit) is not int or limit < 1):
        raise ValueError('limit must count positive new evaluations')
    parent = validate_comparison(read_json(source/'manifest.json'), current_sources=True)
    if not result_progress(parent, scan_results(source, parent))['complete']:
        raise ValueError('Complete six-method comparison required')
    p = parent['identity']['protocol']
    if smoke != (p['profile'] == 'smoke'):
        raise ValueError('Explicit smoke flag must match protocol')
    require_execution_host(p)
    device = setup_runtime(p, device)
    environment = dict(python=platform.python_version(), numpy=np.__version__, scipy=scipy.__version__,
                       torch=str(torch.__version__), device=str(device),
                       device_name=torch.cuda.get_device_name(device) if device.type == 'cuda' else platform.machine())
    if environment != parent['identity']['environment']:
        raise ValueError('Budget and fixed-iteration evaluation require identical runtime/device')
    trained, selected = load_selected(training, device=device, allow_smoke=smoke)
    if selected != parent['identity']['selected']:
        raise ValueError('Budget and fixed-budget comparison must use identical frozen model')
    untrained = UnfoldedDesigner(trained.config).to(device).eval()
    identity = dict(kind='wallclock_checkpoint_budget_rmse', schema=1,
        comparison_id=parent['id'], protocol=p, selected=selected,
        cases=parent['identity']['cases'], scenes=parent['identity']['scenes'],
        environment=environment, sources=sources(),
        coarse_pairing={c['sample_id']: dict(sha256=file_hash(source/'coarse'/f'{c["sample_id"]}.json'),
            noise_variance=verify_seal(read_json(source/'coarse'/f'{c["sample_id"]}.json'))['noise_variance'])
            for c in parent['identity']['cases']},
        budgets_seconds=list(BUDGETS), methods=list(METHODS),
        timing='Context, initialization, network transfer, quantization, projection, updates and final audit charged. '
               'Best feasible checkpoint ready before deadline; atomic overrun separately recorded. No hard realtime guarantee.',
        initialization='All methods start with common feasible geometric solution; AI then attempts network + projection. '
                       'All continue 1/1/1 AO blocks. Best physical illumination retained; no truth-based selection.',
        pairing='Original test registry, coarse block, fine seeds, noise variance and full CPI unchanged.')
    manifest = dict(id=digest(identity), identity=identity)
    with directory_lock(output) as owner:
        if (output/'manifest.json').exists():
            if read_json(output/'manifest.json') != manifest:
                raise ValueError('Budget manifest changed; use new output')
        else:
            if (output/'samples').exists():
                raise ValueError('Orphan samples without manifest')
            atomic_json(output/'manifest.json', manifest)
        records = scan(output, manifest)
        status = dict(state='RUNNING', owner=owner, updated=now())
        atomic_json(output/'state.json', status)
        scenes = {s['scene_id']: s for s in identity['scenes']}
        (output/'work').mkdir(exist_ok=True)
        produced = 0
        try:
            with threadpool_limits(limits=p['execution']['blas_threads_per_worker']):
                for case in identity['cases']:
                    todo = [x for x in keys() if (case['sample_id'], x[2]) not in records]
                    if not todo or (limit is not None and produced >= limit):
                        continue
                    scene = scenes[case['scene_id']]
                    cfg = model_config(p, truth=scene['truth'], user_angles=scene['user_angles'])
                    est = model_config(p, user_angles=scene['user_angles'])
                    model = Model(est)
                    coarse_path = source/'coarse'/f'{case["sample_id"]}.json'
                    saved = verify_seal(read_json(coarse_path))
                    if saved['case'] != case or saved['manifest_id'] != parent['id']:
                        raise ValueError('Coarse identity mismatch')
                    coarse = np.array(saved['coarse'])
                    times = np.arange(cfg.lc)*cfg.symbol_time
                    with tempfile.TemporaryDirectory(dir=output/'work') as temp:
                        work = Path(temp)
                        yc = simulate_block(cfg, model.wzf, None, times, saved['noise_variance'],
                                            case['coarse_seed'], work/'coarse.npy', p['execution']['batch_subcarriers'])
                        try:
                            rc = dict(y=yc, w=model.wzf, phase=None, times=times)
                            if not np.allclose(coarse_from_records(est, [rc]), coarse, atol=1e-10, rtol=0):
                                raise ValueError('Coarse replay mismatch')
                            order = np.random.default_rng(case['fine_seed']).permutation(len(keys())).tolist()
                            for index in order:
                                method, seconds, key = keys()[index]
                                if (case['sample_id'], key) in records:
                                    continue
                                if limit is not None and produced >= limit:
                                    break
                                status.update(current_case=case['sample_id'], current_method=key, updated=now())
                                atomic_json(output/'state.json', status)
                                print(f'START BUDGET {case["sample_id"]} {key}', flush=True)
                                start = time.perf_counter()
                                design = None
                                try:
                                    network = trained if method == 'learned_anytime' else untrained
                                    ctx, w, phase, design = timed_design(lambda: context_from_model(model, coarse),
                                                                        method, network, seconds)
                                    result = run_method(method, case, cfg, est, model, ctx, coarse, rc,
                                        saved['noise_variance'], trained, untrained, p, work, 0.,
                                        saved['coarse_seconds'], prepared=(w, phase, design))
                                except NoTimelyDesign as exc:
                                    result = dict(status='DEADLINE_MISS', error=str(exc), budget_timing=exc.timing)
                                except (InfeasibleDesign, FloatingPointError, np.linalg.LinAlgError) as exc:
                                    result = dict(status='ALGORITHM_FAILURE', error=str(exc),
                                        design=design, traceback=traceback.format_exc())
                                if identity['sources'] != sources():
                                    raise ValueError('Sources changed during evaluation')
                                record = sealed(dict(manifest_id=manifest['id'], case=case, key=key,
                                    method=method, budget_seconds=seconds, coarse_sha256=file_hash(coarse_path),
                                    noise_variance=saved['noise_variance'], method_order=order,
                                    total_seconds=time.perf_counter()-start, saved_at=now(), **result))
                                atomic_json(output/'samples'/case['sample_id']/f'{key}.json', record)
                                records[(case['sample_id'], key)] = record
                                produced += 1
                                report = progress(manifest, records)
                                atomic_json(output/'progress.json', report)
                                print(f'SAVED BUDGET {key} {record["status"]} {report["terminal"]}/{report["expected"]}', flush=True)
                        finally:
                            yc._mmap.close()
                            del yc
            report = progress(manifest, records)
            status.update(state='COMPLETE' if report['complete'] else 'PAUSED_LIMIT', updated=now())
            atomic_json(output/'progress.json', report)
            atomic_json(output/'state.json', status)
            return report
        except BaseException as exc:
            status.update(state='FAILED', error=str(exc), traceback=traceback.format_exc(), updated=now())
            atomic_json(output/'failures'/f'{time.time_ns()}.json', status)
            atomic_json(output/'state.json', status)
            raise


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('source', 'training', 'output'):
        parser.add_argument('--'+name, type=Path, required=True)
    parser.add_argument('--device', default='cpu')
    parser.add_argument('--smoke', action='store_true')
    parser.add_argument('--limit', type=int)
    args = parser.parse_args()
    print(run(**vars(args)))


if __name__ == '__main__':
    main()
