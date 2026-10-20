"""Full-size DD observations -> coarse estimates; small JSON, resumable samples.

Only train/validation data are produced here. Test geometries are registered for
split auditing but their observations are reserved for the frozen-model runner.
"""
import argparse
from datetime import datetime, timezone
import os
from pathlib import Path
import platform
import tempfile
import time
import traceback

import numpy as np
import scipy
from threadpoolctl import threadpool_limits

from RIS_stage3.stage3_model import Model
from RIS_stage3.streaming import simulate_block, reference_power, coarse_from_records
from .context import context_from_model
from .protocol import DEFAULT_PROTOCOL, load_protocol, model_config, require_execution_host, validate_protocol
from .scenes import build_scenes, build_cases
from .storage import atomic_json, digest, file_hash, read_json, directory_lock, now

ROOT = Path(__file__).resolve().parent.parent
DATA_SOURCES = ('RIS_stage3/stage3_model.py', 'RIS_stage3/streaming.py',
                'RIS_stage3_ai/storage.py', 'RIS_stage3_ai/protocol.py',
                'RIS_stage3_ai/scenes.py', 'RIS_stage3_ai/generate_dataset.py',
                'RIS_stage3_ai/context.py')


def source_hashes():
    return {name: file_hash(ROOT/name) for name in DATA_SOURCES}


def build_manifest(p):
    validate_protocol(p)
    scenes = build_scenes(p)
    identity = dict(schema=1, kind='coarse_training_dataset', protocol=p,
        sources=source_hashes(), scenes=scenes, cases=build_cases(p, scenes),
        environment=dict(python=platform.python_version(), numpy=np.__version__, scipy=scipy.__version__),
        simulator='exact existing DD block, complex128, every configured tone/antenna/symbol',
        input_contract='coarse estimates and user angles only; no target truth',
        noise_reference='per-scene full-CPI DD-ZF mean echo power',
        batch=p['execution']['batch_subcarriers'])
    return dict(id=digest(identity), identity=identity)


def validate_manifest(manifest, *, current_sources=False):
    identity = manifest['identity']
    if manifest['id'] != digest(identity) or identity['kind'] != 'coarse_training_dataset':
        raise ValueError('Invalid dataset manifest digest/kind')
    p = validate_protocol(identity['protocol'])
    scenes = build_scenes(p)
    if identity['scenes'] != scenes or identity['cases'] != build_cases(p, scenes):
        raise ValueError('Scene/case registry differs from protocol')
    if current_sources and identity['sources'] != source_hashes():
        raise ValueError('Dataset source changed; use an isolated original checkout or a new output')
    return manifest


def prepare(directory, p):
    directory = Path(directory)
    directory.mkdir(parents=True, exist_ok=True)
    manifest = build_manifest(p)
    path = directory/'manifest.json'
    if path.exists():
        saved = validate_manifest(read_json(path), current_sources=True)
        if saved != manifest:
            raise ValueError('Different protocol/code/environment in output; use a new dataset directory')
    else:
        if any((directory/name).exists() for name in ('samples', 'inputs')):
            raise ValueError('Sample files exist without a manifest; refusing to adopt them')
        atomic_json(path, manifest)
    for name in ('samples', 'inputs', 'failures', 'work'):
        (directory/name).mkdir(exist_ok=True)
    return manifest


def sealed(value):
    return dict(value, sha256=digest(value))


def verify_seal(value):
    payload = {k: v for k, v in value.items() if k != 'sha256'}
    if value.get('sha256') != digest(payload):
        raise ValueError('Checkpoint checksum mismatch')
    return value


def read_sample(directory, manifest, case):
    directory = Path(directory)
    path = directory/'samples'/f'{case["sample_id"]}.json'
    record = verify_seal(read_json(path))
    if record['manifest_id'] != manifest['id'] or record['case'] != case or record['status'] != 'COMPLETE':
        raise ValueError('Sample belongs to another experiment/case or is incomplete')
    feature_path = directory/'inputs'/f'{case["sample_id"]}.json'
    if record['input_file_sha256'] != file_hash(feature_path):
        raise ValueError('Input file checksum mismatch')
    feature = read_json(feature_path)
    if set(feature) != {'manifest_id', 'sample_id', 'coarse', 'user_angles'}:
        raise ValueError('Unexpected feature fields, potential truth leakage')
    if feature['manifest_id'] != manifest['id'] or feature['sample_id'] != case['sample_id']:
        raise ValueError('Feature identity mismatch')
    coarse = np.asarray(feature['coarse'], dtype=float)
    user = np.asarray(feature['user_angles'], dtype=float)
    if coarse.shape != (2, 4) or user.shape != (2,) or not np.isfinite(coarse).all() or not np.isfinite(user).all():
        raise ValueError('Non-finite/malformed features')
    if np.any(coarse[:, 0] <= 0):
        raise ValueError('Nonpositive coarse range')
    scene = next(s for s in manifest['identity']['scenes'] if s['scene_id'] == case['scene_id'])
    if feature['user_angles'] != scene['user_angles']:
        raise ValueError('Known user channel does not match registered scene')
    return record, feature


def load_context(directory, manifest, case):
    # Training gets only this returned DesignContext. cfg has NaN target truth.
    _, feature = read_sample(directory, manifest, case)
    cfg = model_config(manifest['identity']['protocol'], user_angles=feature['user_angles'])
    return context_from_model(Model(cfg), feature['coarse'])


def progress(directory, manifest):
    directory = Path(directory)
    cases = manifest['identity']['cases']
    expected_names = {case['sample_id']+'.json' for case in cases}
    unknown = {path.name for path in (directory/'samples').glob('*.json')} - expected_names
    if unknown:
        raise ValueError(f'Unregistered samples in dataset: {sorted(unknown)}')
    counts = dict(train=0, validation=0)
    for case in cases:
        if (directory/'samples'/f'{case["sample_id"]}.json').exists():
            read_sample(directory, manifest, case)
            counts[case['split']] += 1
    total = sum(counts.values())
    return dict(manifest_id=manifest['id'], profile=manifest['identity']['protocol']['profile'],
                completed=total, expected=len(cases), complete=total == len(cases),
                counts=counts, failure_attempts=len(list((directory/'failures').glob('*.json'))),
                updated=now())


def generate_one(directory, manifest, case, scene, reference=None):
    p = manifest['identity']['protocol']
    require_execution_host(p)
    cfg = model_config(p, truth=scene['truth'], user_angles=scene['user_angles'])
    estimator_cfg = model_config(p, user_angles=scene['user_angles'])
    model = Model(estimator_cfg)
    batch = manifest['identity']['batch']
    started = time.perf_counter()
    # Reference is always full configured CPI, even though this file stores only coarse inputs.
    ref_started = time.perf_counter()
    ref = reference_power(cfg, batch) if reference is None else reference
    ref_seconds = time.perf_counter()-ref_started
    variance = float(ref/10**(case['snr_db']/10))
    if not np.isfinite(ref) or ref <= 0 or not np.isfinite(variance) or variance <= 0:
        raise ValueError('Invalid DD reference power/noise variance')
    times = np.arange(cfg.lc)*cfg.symbol_time
    with tempfile.TemporaryDirectory(prefix=case['sample_id']+'_', dir=Path(directory)/'work') as work:
        sim_started = time.perf_counter()
        y = simulate_block(cfg, model.wzf, None, times, variance, case['coarse_seed'],
                           Path(work)/'coarse.npy', batch)
        try:
            sim_seconds = time.perf_counter()-sim_started
            estimate_started = time.perf_counter()
            coarse = coarse_from_records(estimator_cfg, [dict(y=y, w=model.wzf, phase=None, times=times)])
            estimate_seconds = time.perf_counter()-estimate_started
            # Validate the features against actual design input contract before checkpointing.
            context_from_model(model, coarse)
        finally:
            # Explicit close is required before deleting mapped files on Windows.
            y._mmap.close()
            del y
    feature = dict(manifest_id=manifest['id'], sample_id=case['sample_id'],
                   coarse=coarse.tolist(), user_angles=scene['user_angles'])
    record = dict(manifest_id=manifest['id'], case=case, status='COMPLETE', saved_at=now(),
                  noise_reference_power=ref, noise_variance=variance,
                  observation_shape=[cfg.ns, cfg.rx_nx*cfg.rx_ny, cfg.lc],
                  estimator_truth='unavailable_NaN', reference_reused=reference is not None,
                  timings=dict(reference_seconds=ref_seconds, simulation_seconds=sim_seconds,
                               coarse_seconds=estimate_seconds, total_seconds=time.perf_counter()-started))
    return feature, record


def generate(directory, p, *, limit=None, prepare_only=False):
    if limit is not None and (type(limit) is not int or limit < 1):
        raise ValueError('limit must be a positive number of NEW samples')
    if not prepare_only:
        require_execution_host(p)
    directory = Path(directory)
    with directory_lock(directory) as owner:
        manifest = prepare(directory, p)
        state = progress(directory, manifest)
        if prepare_only:
            atomic_json(directory/'progress.json', state)
            return state
        status = dict(owner=owner, manifest_id=manifest['id'], state='RUNNING', updated=now())
        atomic_json(directory/'state.json', status)
        scenes = {s['scene_id']: s for s in manifest['identity']['scenes']}
        references = {}
        produced = 0
        case = None
        try:
            with threadpool_limits(limits=p['execution']['blas_threads_per_worker']):
                for case in manifest['identity']['cases']:
                    dest = directory/'samples'/f'{case["sample_id"]}.json'
                    if dest.exists():
                        record, _ = read_sample(directory, manifest, case)
                        references[case['scene_id']] = record['noise_reference_power']
                        continue
                    if limit is not None and produced >= limit:
                        break
                    status.update(current_sample=case['sample_id'], updated=now())
                    atomic_json(directory/'state.json', status)
                    print(f'START {case["sample_id"]} profile={p["profile"]}', flush=True)
                    feature, record = generate_one(directory, manifest, case, scenes[case['scene_id']],
                                                   references.get(case['scene_id']))
                    validate_manifest(manifest, current_sources=True)
                    feature_path = directory/'inputs'/f'{case["sample_id"]}.json'
                    atomic_json(feature_path, feature)
                    record['input_file_sha256'] = file_hash(feature_path)
                    # This final atomic record is the commit marker. An orphan input is not completion.
                    atomic_json(dest, sealed(record))
                    references[case['scene_id']] = record['noise_reference_power']
                    produced += 1
                    state = progress(directory, manifest)
                    atomic_json(directory/'progress.json', state)
                    print(f'SAVED {case["sample_id"]} {state["completed"]}/{state["expected"]} '
                          f'seconds={record["timings"]["total_seconds"]:.2f}', flush=True)
            state = progress(directory, manifest)
            atomic_json(directory/'progress.json', state)
            status.update(state='COMPLETE' if state['complete'] else 'PAUSED_LIMIT',
                          current_sample=None, updated=now(), completed=state['completed'], expected=state['expected'])
            atomic_json(directory/'state.json', status)
            return state
        except BaseException as exc:
            stamp = datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S%f')
            atomic_json(directory/'failures'/f'{stamp}_{os.getpid()}.json', dict(
                manifest_id=manifest['id'], case=case, error_type=type(exc).__name__,
                message=str(exc), traceback=traceback.format_exc(), owner=owner, failed_at=now()))
            status.update(state='INTERRUPTED' if isinstance(exc, KeyboardInterrupt) else 'FAILED', updated=now())
            atomic_json(directory/'state.json', status)
            raise


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--protocol', type=Path, default=DEFAULT_PROTOCOL)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--smoke', action='store_true')
    parser.add_argument('--limit', type=int, help='New samples for a pilot; does not change total expected')
    parser.add_argument('--prepare-only', action='store_true', help='Register protocol/scenes without computation')
    parser.add_argument('--status', action='store_true', help='Verify saved records and print actual counts')
    args = parser.parse_args()
    if args.status:
        manifest = validate_manifest(read_json(args.output/'manifest.json'))
        state = progress(args.output, manifest)
    else:
        state = generate(args.output, load_protocol(args.protocol, smoke=args.smoke),
                         limit=args.limit, prepare_only=args.prepare_only)
    print(state, flush=True)


if __name__ == '__main__':
    main()
