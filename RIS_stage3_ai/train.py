"""Audited full-frequency training, validation-only selection and sample resume."""
import argparse
from copy import deepcopy
from datetime import datetime, timezone
import hashlib
import math
import os
from pathlib import Path
import platform
import random
import time
import traceback
import uuid

import numpy as np
import scipy
import torch
from threadpoolctl import threadpool_limits

from .generate_dataset import (DATA_SOURCES, ROOT, validate_manifest, progress as data_progress,
                               read_sample, load_context)
from .physics_numpy import geometric_initialization
from .physics_torch import TorchPhysics
from .protocol import require_execution_host
from .repair import DesignBudget, InfeasibleDesign, repair_design, traditional_design
from .storage import atomic_json, digest, file_hash, read_json, directory_lock, now
from .unfolded_design import UnfoldedConfig, UnfoldedDesigner, network_candidate

SETTINGS_PATH = Path(__file__).with_name('training_v1.json')
TRAIN_SOURCES = tuple(sorted(set(DATA_SOURCES) | {
    'RIS_stage3_ai/train.py', 'RIS_stage3_ai/physics_numpy.py', 'RIS_stage3_ai/physics_torch.py',
    'RIS_stage3_ai/unfolded_design.py', 'RIS_stage3_ai/repair.py'}))
INFERENCE_SOURCES = ('RIS_stage3/stage3_model.py', 'RIS_stage3_ai/context.py',
    'RIS_stage3_ai/physics_numpy.py', 'RIS_stage3_ai/physics_torch.py',
    'RIS_stage3_ai/unfolded_design.py', 'RIS_stage3_ai/repair.py')


def settings_for(p, path=SETTINGS_PATH):
    cfg = read_json(path)
    if cfg['schema'] != 1 or cfg['optimizer'] != 'Adam' or cfg['batch_size'] != 1:
        raise ValueError('Unsupported training schema/optimizer/batch size')
    for key in ('epochs', 'continuous_epochs'):
        if type(cfg[key]) is not int or cfg[key] < 1:
            raise ValueError(f'Invalid {key}')
    if cfg['continuous_epochs'] >= cfg['epochs']:
        raise ValueError('Need both continuous and quantization-aware epochs')
    for key in ('learning_rate', 'gradient_clip_norm'):
        if not math.isfinite(cfg[key]) or cfg[key] <= 0:
            raise ValueError(f'Invalid {key}')
    for key in ('validation_every_epoch', 'include_initial_model_in_selection', 'checkpoint_every_sample'):
        if cfg[key] is not True:
            raise ValueError(f'{key} must be enabled')
    if cfg['selection'] != 'fewest_failures_then_mean_repaired_min_illumination':
        raise ValueError('Unsupported model selection')
    UnfoldedConfig(**cfg['network'])
    if cfg['network']['layers'] != p['learning']['layers']:
        raise ValueError('Network depth differs from data protocol')
    if cfg['repair'] != dict(ao=1, sca=1, phase_sweeps=1) or cfg['fallback'] != dict(ao=3, sca=3, phase_sweeps=2):
        raise ValueError('Repair/fallback must match the declared comparison budget')
    if p['profile'] == 'smoke':
        cfg.update(epochs=2, continuous_epochs=1, status='SMOKE_ONLY_NOT_FORMAL_TRAINING')
    return cfg


def weight_hash(weights):
    h = hashlib.sha256()
    for name, value in sorted(weights.items()):
        h.update(name.encode())
        array = value.detach().cpu().contiguous().numpy()
        h.update(str(array.dtype).encode())
        h.update(str(array.shape).encode())
        h.update(array.tobytes())
    return h.hexdigest()


def cpu_weights(network):
    return {key: value.detach().cpu().clone() for key, value in network.state_dict().items()}


def capture_rng():
    ns = np.random.get_state()
    return dict(python=random.getstate(), numpy=[ns[0], ns[1].tolist(), ns[2], ns[3], ns[4]],
                torch=torch.get_rng_state(), cuda=torch.cuda.get_rng_state_all() if torch.cuda.is_available() else [])


def restore_rng(rng):
    random.setstate(rng['python'])
    ns = rng['numpy']
    np.random.set_state((ns[0], np.array(ns[1], dtype=np.uint32), ns[2], ns[3], ns[4]))
    torch.set_rng_state(rng['torch'])
    if rng['cuda']:
        torch.cuda.set_rng_state_all(rng['cuda'])


def setup_runtime(p, device):
    os.environ.setdefault('CUBLAS_WORKSPACE_CONFIG', ':4096:8')
    device = torch.device(device)
    if device.type not in ('cpu', 'cuda'):
        raise ValueError('Only CPU/CUDA supported')
    if device.type == 'cuda' and not torch.cuda.is_available():
        raise RuntimeError('CUDA requested but unavailable; no silent CPU fallback')
    if device.type == 'cuda':
        device = torch.device('cuda', torch.cuda.current_device() if device.index is None else device.index)
    torch.use_deterministic_algorithms(True)
    torch.backends.cuda.matmul.allow_tf32 = False
    torch.backends.cudnn.allow_tf32 = False
    torch.set_num_threads(p['execution']['blas_threads_per_worker'])
    seed = p['learning']['model_seed']
    random.seed(seed)
    np.random.seed(seed)
    torch.manual_seed(seed)
    if torch.cuda.is_available():
        torch.cuda.manual_seed_all(seed)
    return device


def make_manifest(dataset, data_manifest, cfg, device):
    hashes = {}
    for case in data_manifest['identity']['cases']:
        record, _ = read_sample(dataset, data_manifest, case)
        hashes[case['sample_id']] = record['input_file_sha256']
    identity = dict(schema=1, kind='ris_model_driven_training', dataset_id=data_manifest['id'],
        profile=data_manifest['identity']['protocol']['profile'], settings=cfg, inputs=hashes,
        split_counts={split: sum(c['split'] == split for c in data_manifest['identity']['cases'])
                      for split in ('train', 'validation')},
        sources={name: file_hash(ROOT/name) for name in TRAIN_SOURCES},
        environment=dict(python=platform.python_version(), numpy=np.__version__, scipy=scipy.__version__, torch=str(torch.__version__),
                         device=str(device), cuda=torch.version.cuda,
                         device_name=torch.cuda.get_device_name(device) if device.type == 'cuda' else platform.machine(),
                         blas_threads=data_manifest['identity']['protocol']['execution']['blas_threads_per_worker'],
                         deterministic=True, cublas_workspace=os.environ['CUBLAS_WORKSPACE_CONFIG']),
        selection_uses='validation coarse estimates only, repaired illumination; not target truth or test RMSE')
    return dict(id=digest(identity), identity=identity)


def save_checkpoint(output, manifest, state, network, optimizer, event):
    """Immutable blob first, latest pointer last: interruption keeps the prior commit."""
    output = Path(output)
    state = deepcopy(state)
    parent = read_json(output/'latest.json') if (output/'latest.json').exists() else None
    if (parent is None and state['revision'] != -1) or (parent is not None and
            (parent['revision'] != state['revision'] or parent['manifest_id'] != manifest['id'])):
        raise ValueError('Checkpoint parent does not match the last committed revision')
    state['revision'] += 1
    state.update(weights=cpu_weights(network), optimizer=deepcopy(optimizer.state_dict()), rng=capture_rng(),
                 event=event, saved_at=now(), manifest_id=manifest['id'], parent_checkpoint=parent)
    stem = f'{state["revision"]:06d}_{uuid.uuid4().hex}'
    relative = f'checkpoints/{stem}.pt'
    path = output/relative
    path.parent.mkdir(exist_ok=True)
    temp = path.with_suffix('.tmp')
    try:
        with temp.open('wb') as stream:
            torch.save(state, stream)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temp, path)
        pointer = dict(manifest_id=manifest['id'], checkpoint=relative, sha256=file_hash(path),
                       revision=state['revision'], saved_at=state['saved_at'])
        # Orphans may share revision numbers; only the latest's parent chain is committed.
        atomic_json(output/'events'/f'{stem}.json', dict(pointer=pointer, event=event))
        atomic_json(output/'latest.json', pointer)
    finally:
        temp.unlink(missing_ok=True)
    return state


def read_checkpoint(output, manifest):
    output = Path(output)
    pointer = read_json(output/'latest.json')
    return read_checkpoint_pointer(output, manifest, pointer), pointer


def read_checkpoint_pointer(output, manifest, pointer):
    output = Path(output)
    path = (output/pointer['checkpoint']).resolve()
    if path.parent != (output/'checkpoints').resolve() or path.suffix != '.pt':
        raise ValueError('Invalid checkpoint path')
    if pointer['manifest_id'] != manifest['id'] or file_hash(path) != pointer['sha256']:
        raise ValueError('Checkpoint identity/checksum mismatch')
    state = torch.load(path, map_location='cpu', weights_only=True)
    if state['manifest_id'] != manifest['id'] or state['revision'] != pointer['revision']:
        raise ValueError('Checkpoint state identity mismatch')
    return state


def committed_events(output):
    """Yield audited events newest first, ignoring blobs from interrupted commits."""
    output = Path(output)
    manifest = read_json(output/'manifest.json')
    if manifest['id'] != digest(manifest['identity']):
        raise ValueError('Invalid training manifest')
    pointer = read_json(output/'latest.json')
    expected = pointer['revision']
    while pointer is not None:
        if pointer['revision'] != expected:
            raise ValueError('Broken checkpoint parent chain')
        state = read_checkpoint_pointer(output, manifest, pointer)
        yield state['event']
        pointer = state['parent_checkpoint']
        expected -= 1
    if expected != -1:
        raise ValueError('Missing checkpoint ancestor')


def epoch_order(cases, seed, epoch):
    indices = np.random.default_rng(np.random.SeedSequence([seed, epoch])).permutation(len(cases))
    return [cases[int(i)] for i in indices]


def training_step(ctx, network, optimizer, cfg, straight_through):
    device = network.raw_w_steps.device
    physics = TorchPhysics.from_context(ctx, device)
    w0, phase0 = geometric_initialization(ctx)
    w0 = torch.tensor(w0, dtype=torch.complex128, device=device)
    angles = torch.angle(torch.tensor(phase0, dtype=torch.complex128, device=device))
    network.train()
    optimizer.zero_grad(set_to_none=True)
    w, phase = network(physics, w0, angles, straight_through=straight_through, create_graph=True)
    loss = physics.loss(w, phase, network.config.temperature, network.config.qos_weight)
    if not torch.isfinite(loss):
        raise FloatingPointError('Non-finite training loss')
    loss.backward()
    params = list(network.parameters())
    if any(p.grad is None or not torch.isfinite(p.grad).all() for p in params):
        raise FloatingPointError('Missing/non-finite parameter gradient')
    norm = torch.nn.utils.clip_grad_norm_(params, cfg['gradient_clip_norm'], error_if_nonfinite=True)
    optimizer.step()
    if any(not torch.isfinite(p).all() for p in params):
        raise FloatingPointError('Non-finite parameter after optimizer step')
    return dict(loss=float(loss.detach().cpu()), unclipped_gradient_norm=float(norm.detach().cpu()),
                straight_through=straight_through)


def validation_sample(ctx, network, cfg):
    network.eval()
    candidate_failure = None
    try:
        try:
            w, phase, candidate = network_candidate(ctx, network, straight_through=True)
        except FloatingPointError as exc:
            candidate_failure = str(exc)
            w, phase, fallback = traditional_design(ctx, DesignBudget(**cfg['fallback']))
            return dict(feasible=True, score=fallback['final']['min_illumination'], fallback_used=True,
                        candidate_failure=candidate_failure, candidate=None, repair=dict(fallback=fallback))
        _, _, repaired = repair_design(ctx, w, phase, DesignBudget(**cfg['repair']), DesignBudget(**cfg['fallback']))
        return dict(feasible=True, score=repaired['final']['min_illumination'],
                    fallback_used=repaired['fallback_used'], candidate_failure=candidate_failure,
                    candidate=candidate, repair=repaired)
    except InfeasibleDesign as exc:
        # Failed algorithm samples remain in the denominator and selection failure count.
        return dict(feasible=False, score=0., fallback_used=False, candidate_failure=candidate_failure,
                    error=f'{type(exc).__name__}: {exc}')


def choose_best(best, summary, weights):
    key = (-summary['failures'], summary['mean_repaired_min_illumination'])
    previous = None if best is None else (-best['summary']['failures'], best['summary']['mean_repaired_min_illumination'])
    if previous is None or key > previous:
        return dict(summary=deepcopy(summary), weights=deepcopy(weights), weight_sha256=weight_hash(weights))
    return best


def summarize(state, manifest, ntrain, nval):
    cfg = manifest['identity']['settings']
    best = state['best']
    if state['phase'] == 'complete' and (state['updates'] != cfg['epochs']*ntrain or
            state['validation_done'] != (cfg['epochs']+1)*nval or len(state['validation_history']) != cfg['epochs']+1):
        raise ValueError('Complete state has incorrect training/validation counts')
    return dict(manifest_id=manifest['id'], profile=manifest['identity']['profile'], phase=state['phase'],
        epoch=state['epoch'], position=state['position'], complete=state['phase'] == 'complete',
        training_updates=state['updates'], expected_training_updates=cfg['epochs']*ntrain,
        validation_samples=state['validation_done'], expected_validation_samples=(cfg['epochs']+1)*nval,
        current_weights_changed=weight_hash(state['weights']) != state['initial_weight_sha256'],
        best_epoch=None if best is None else best['summary']['epoch'],
        selected_weights_changed=None if best is None else best['weight_sha256'] != state['initial_weight_sha256'],
        best_validation=None if best is None else best['summary'], revision=state['revision'], updated=now())


def train(dataset, output, *, smoke=False, device='cpu', settings_path=SETTINGS_PATH, limit=None):
    dataset, output = Path(dataset).resolve(), Path(output).resolve()
    if dataset == output or dataset in output.parents or output in dataset.parents:
        raise ValueError('Dataset and training output must be separate directories')
    if limit is not None and (type(limit) is not int or limit < 1):
        raise ValueError('limit must count a positive number of new sample operations')
    data_manifest = validate_manifest(read_json(dataset/'manifest.json'), current_sources=True)
    p = data_manifest['identity']['protocol']
    if smoke != (p['profile'] == 'smoke'):
        raise ValueError('Explicit --smoke must match dataset profile')
    require_execution_host(p)
    cfg = settings_for(p, settings_path)
    device = setup_runtime(p, device)
    with directory_lock(dataset), directory_lock(output) as owner:
        if not data_progress(dataset, data_manifest)['complete']:
            raise ValueError('Training requires a complete, audited train/validation dataset')
        manifest = make_manifest(dataset, data_manifest, cfg, device)
        if (output/'manifest.json').exists():
            if read_json(output/'manifest.json') != manifest:
                raise ValueError('Training identity changed: use original settings/code/device or a new output')
        else:
            if (output/'latest.json').exists() or (output/'checkpoints').exists():
                raise ValueError('Refusing checkpoint files without a manifest')
            atomic_json(output/'manifest.json', manifest)
        cases = data_manifest['identity']['cases']
        training = [c for c in cases if c['split'] == 'train']
        validation = [c for c in cases if c['split'] == 'validation']
        if not training or not validation or len(training)+len(validation) != len(cases):
            raise ValueError('Only nonempty training/validation splits are allowed')
        network = UnfoldedDesigner(UnfoldedConfig(**cfg['network'])).to(device)
        optimizer = torch.optim.Adam(network.parameters(), lr=cfg['learning_rate'])
        if (output/'latest.json').exists():
            state, _ = read_checkpoint(output, manifest)
            network.load_state_dict(state['weights'])
            optimizer.load_state_dict(state['optimizer'])
            restore_rng(state['rng'])
        else:
            state = dict(revision=-1, phase='validation', epoch=0, position=0, updates=0,
                validation_done=0, validation_rows=[], validation_history=[], best=None,
                initial_weight_sha256=weight_hash(network.state_dict()))
            state = save_checkpoint(output, manifest, state, network, optimizer, dict(kind='INITIALIZED'))
        operations = 0
        status = dict(owner=owner, manifest_id=manifest['id'], state='RUNNING', updated=now())
        atomic_json(output/'state.json', status)
        current = None
        try:
            with threadpool_limits(limits=p['execution']['blas_threads_per_worker']):
                while state['phase'] != 'complete':
                    if limit is not None and operations >= limit:
                        break
                    phase = state['phase']
                    current_cases = (epoch_order(training, p['learning']['model_seed'], state['epoch'])
                                     if phase == 'train' else validation)
                    current = current_cases[state['position']]
                    status.update(current_sample=current['sample_id'], phase=phase, epoch=state['epoch'], updated=now())
                    atomic_json(output/'state.json', status)
                    start = time.perf_counter()
                    # Freeze feature contents as well as identities throughout training.
                    if file_hash(dataset/'inputs'/f'{current["sample_id"]}.json') != manifest['identity']['inputs'][current['sample_id']]:
                        raise ValueError('Dataset input changed during training')
                    ctx = load_context(dataset, data_manifest, current)
                    if device.type == 'cuda':
                        torch.cuda.reset_peak_memory_stats(device)
                    if phase == 'train':
                        result = training_step(ctx, network, optimizer, cfg, state['epoch'] > cfg['continuous_epochs'])
                        state['updates'] += 1
                    else:
                        result = validation_sample(ctx, network, cfg)
                        state['validation_rows'].append(dict(sample_id=current['sample_id'], **result))
                        state['validation_done'] += 1
                    if device.type == 'cuda':
                        torch.cuda.synchronize(device)
                    event = dict(kind=phase, epoch=state['epoch'], sample_id=current['sample_id'], result=result,
                        seconds=time.perf_counter()-start,
                        cuda_peak_allocated_bytes=torch.cuda.max_memory_allocated(device) if device.type == 'cuda' else None)
                    state['position'] += 1
                    if state['position'] == len(current_cases):
                        state['position'] = 0
                        if phase == 'train':
                            state['phase'] = 'validation'
                            state['validation_rows'] = []
                        else:
                            rows = state['validation_rows']
                            summary = dict(epoch=state['epoch'], samples=len(rows),
                                failures=sum(not r['feasible'] for r in rows),
                                fallbacks=sum(r['fallback_used'] for r in rows),
                                mean_repaired_min_illumination=float(np.mean([r['score'] for r in rows])))
                            state['best'] = choose_best(state['best'], summary, cpu_weights(network))
                            state['validation_history'].append(summary)
                            state['validation_rows'] = []
                            if state['epoch'] == cfg['epochs']:
                                state['phase'] = 'complete'
                            else:
                                state['epoch'] += 1
                                state['phase'] = 'train'
                    # Do not commit work produced while source files were edited.
                    if manifest['identity']['sources'] != {name: file_hash(ROOT/name) for name in TRAIN_SOURCES}:
                        raise ValueError('Training source changed during run')
                    state = save_checkpoint(output, manifest, state, network, optimizer, event)
                    operations += 1
                    report = summarize(state, manifest, len(training), len(validation))
                    atomic_json(output/'progress.json', report)
                    print(f'SAVED {phase} epoch={event["epoch"]} {current["sample_id"]} '
                          f'updates={report["training_updates"]}/{report["expected_training_updates"]} '
                          f'validation={report["validation_samples"]}/{report["expected_validation_samples"]}', flush=True)
            report = summarize(state, manifest, len(training), len(validation))
            atomic_json(output/'progress.json', report)
            status.update(state='COMPLETE' if report['complete'] else 'PAUSED_LIMIT', current_sample=None, updated=now())
            atomic_json(output/'state.json', status)
            return report
        except BaseException as exc:
            stamp = datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S%f')
            atomic_json(output/'failures'/f'{stamp}_{os.getpid()}.json', dict(
                manifest_id=manifest['id'], sample=current, exception=type(exc).__name__, message=str(exc),
                traceback=traceback.format_exc(), failed_at=now(), owner=owner))
            status.update(state='INTERRUPTED' if isinstance(exc, KeyboardInterrupt) else 'FAILED', updated=now())
            atomic_json(output/'state.json', status)
            raise


def load_selected(output, *, device='cpu', allow_smoke=False):
    """Frozen inference artifact for the future comparison runner; never load partial runs."""
    output = Path(output)
    manifest = read_json(output/'manifest.json')
    if manifest['id'] != digest(manifest['identity']) or manifest['identity']['kind'] != 'ris_model_driven_training':
        raise ValueError('Invalid training manifest')
    if manifest['identity']['profile'] == 'smoke' and not allow_smoke:
        raise ValueError('Smoke model cannot be used for formal comparison')
    if any(file_hash(ROOT/name) != manifest['identity']['sources'][name] for name in INFERENCE_SOURCES):
        raise ValueError('Inference physics/source differs from selected checkpoint')
    state, pointer = read_checkpoint(output, manifest)
    counts = manifest['identity']['split_counts']
    summarize(state, manifest, counts['train'], counts['validation'])
    if state['phase'] != 'complete' or state['best'] is None:
        raise ValueError('Training/validation is incomplete')
    best = state['best']
    if weight_hash(best['weights']) != best['weight_sha256']:
        raise ValueError('Selected weight hash mismatch')
    network = UnfoldedDesigner(UnfoldedConfig(**manifest['identity']['settings']['network'])).to(device)
    network.load_state_dict(best['weights'])
    network.eval()
    return network, dict(training_id=manifest['id'], dataset_id=manifest['identity']['dataset_id'],
        profile=manifest['identity']['profile'], checkpoint=pointer, selected=best['summary'],
        weight_sha256=best['weight_sha256'], weights_changed=best['weight_sha256'] != state['initial_weight_sha256'],
        validation_history=state['validation_history'])


def training_status(output):
    output = Path(output)
    manifest = read_json(output/'manifest.json')
    if manifest['id'] != digest(manifest['identity']) or manifest['identity']['kind'] != 'ris_model_driven_training':
        raise ValueError('Invalid training manifest')
    state, _ = read_checkpoint(output, manifest)
    counts = manifest['identity']['split_counts']
    report = summarize(state, manifest, counts['train'], counts['validation'])
    report['failure_attempts'] = len(list((output/'failures').glob('*.json')))
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--dataset', type=Path)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--settings', type=Path, default=SETTINGS_PATH)
    parser.add_argument('--smoke', action='store_true')
    parser.add_argument('--device', default='cpu', help='cpu or cuda:0; no automatic fallback')
    parser.add_argument('--limit', type=int, help='Number of new train/validation sample operations for a pilot')
    parser.add_argument('--status', action='store_true', help='Audit committed checkpoint and report real progress')
    args = parser.parse_args()
    if args.status:
        print(training_status(args.output), flush=True)
        return
    if args.dataset is None:
        parser.error('--dataset is required for training')
    print(train(args.dataset, args.output, smoke=args.smoke, device=args.device,
                settings_path=args.settings, limit=args.limit), flush=True)


if __name__ == '__main__':
    main()
