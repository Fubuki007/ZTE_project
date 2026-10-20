"""Full-dimension server timing pilot, never a trained model or scientific result."""
import argparse
from pathlib import Path
import time
import traceback

import numpy as np
import torch
from threadpoolctl import threadpool_limits

from RIS_stage3.stage3_model import Model
from .context import context_from_model
from .generate_dataset import ROOT, build_manifest, generate_one, sealed, verify_seal
from .protocol import load_protocol, require_execution_host, model_config
from .storage import atomic_json, read_json, directory_lock, digest, file_hash, now
from .train import TRAIN_SOURCES, settings_for, setup_runtime, training_step, validation_sample
from .unfolded_design import UnfoldedDesigner, UnfoldedConfig


def profile(output, *, smoke=False, device='cuda:0', repeats=3):
    if type(repeats) is not int or repeats < 1:
        raise ValueError('repeats must be positive')
    p = load_protocol(smoke=smoke)
    require_execution_host(p)
    device = setup_runtime(p, device)
    cfg = settings_for(p)
    data_manifest = build_manifest(p)
    cases = [next(c for c in data_manifest['identity']['cases'] if c['split'] == split) for split in ('train', 'validation')]
    source_names = sorted(set(TRAIN_SOURCES) | {'RIS_stage3_ai/profile_runtime.py'})
    identity = dict(kind='runtime_pilot_only', protocol=p, settings=cfg, data_manifest_id=data_manifest['id'],
        cases=cases, repeats=repeats, device=str(device), torch=str(torch.__version__),
        device_name=torch.cuda.get_device_name(device) if device.type == 'cuda' else 'CPU',
        sources={name: file_hash(ROOT/name) for name in source_names},
        scope='small sample count with all configured physical dimensions; no formal training or test RMSE')
    manifest = dict(id=digest(identity), identity=identity)
    output = Path(output)
    with directory_lock(output) as owner, threadpool_limits(limits=p['execution']['blas_threads_per_worker']):
        if (output/'manifest.json').exists() and read_json(output/'manifest.json') != manifest:
            raise ValueError('Pilot identity changed; use a new output')
        atomic_json(output/'manifest.json', manifest)
        (output/'work').mkdir(exist_ok=True)
        atomic_json(output/'state.json', dict(state='RUNNING', owner=owner, manifest_id=manifest['id'], updated=now()))
        try:
            features, generated = {}, []
            for case in cases:
                path = output/f'{case["split"]}_input.json'
                if path.exists():
                    saved = verify_seal(read_json(path))
                    if saved['manifest_id'] != manifest['id']:
                        raise ValueError('Pilot input identity mismatch')
                    feature, record = saved['feature'], saved['record']
                else:
                    scene = next(s for s in data_manifest['identity']['scenes'] if s['scene_id'] == case['scene_id'])
                    print(f'GENERATE {case["sample_id"]} Ns={p["physical"]["ns"]}', flush=True)
                    feature, record = generate_one(output, data_manifest, case, scene)
                    atomic_json(path, sealed(dict(manifest_id=manifest['id'], feature=feature, record=record)))
                features[case['split']] = feature
                generated.append(record)
            measurements = []
            for mode in ('continuous_train', 'quantized_train', 'validation'):
                for replicate in range(repeats):
                    path = output/'measurements'/f'{mode}_{replicate:02d}.json'
                    if path.exists():
                        row = verify_seal(read_json(path))
                        if row['manifest_id'] != manifest['id']:
                            raise ValueError('Pilot timing identity mismatch')
                        measurements.append(row)
                        continue
                    if device.type == 'cuda':
                        torch.cuda.synchronize(device)
                        torch.cuda.reset_peak_memory_stats(device)
                    start = time.perf_counter()
                    feature = features['validation' if mode == 'validation' else 'train']
                    ctx = context_from_model(Model(model_config(p, user_angles=feature['user_angles'])), feature['coarse'])
                    network = UnfoldedDesigner(UnfoldedConfig(**cfg['network'])).to(device)
                    if mode == 'validation':
                        result = validation_sample(ctx, network, cfg)
                    else:
                        optimizer = torch.optim.Adam(network.parameters(), lr=cfg['learning_rate'])
                        result = training_step(ctx, network, optimizer, cfg, mode == 'quantized_train')
                    if device.type == 'cuda':
                        torch.cuda.synchronize(device)
                    elapsed = time.perf_counter()-start
                    row = sealed(dict(manifest_id=manifest['id'], mode=mode, replicate=replicate,
                        seconds=elapsed, result=result,
                        cuda_peak_allocated_bytes=torch.cuda.max_memory_allocated(device) if device.type == 'cuda' else None,
                        includes='context, fresh tiny network/Adam creation, computation; excludes checkpoint I/O', saved_at=now()))
                    atomic_json(path, row)
                    measurements.append(row)
                    print(f'MEASURE {mode} {replicate+1}/{repeats} seconds={elapsed:.3f}', flush=True)
                    del ctx, network
                    if mode != 'validation':
                        del optimizer
            rates = {}
            for mode in ('continuous_train', 'quantized_train', 'validation'):
                values = [r['seconds'] for r in measurements if r['mode'] == mode]
                rates[mode] = dict(median=float(np.median(values)), minimum=min(values), maximum=max(values), samples=len(values))
            ntrain = p['learning']['train_scenes']*len(p['learning']['snr_db'])*p['learning']['noise_replicates_per_scene_snr']
            nval = p['learning']['validation_scenes']*len(p['learning']['snr_db'])*p['learning']['noise_replicates_per_scene_snr']
            budgets = dict(continuous_train=ntrain*cfg['continuous_epochs'],
                quantized_train=ntrain*(cfg['epochs']-cfg['continuous_epochs']), validation=nval*(cfg['epochs']+1))
            times = {stat: sum(budgets[mode]*rates[mode][stat] for mode in rates)/3600 for stat in ('median', 'minimum', 'maximum')}
            validation_failures = sum(not r['result']['feasible'] for r in measurements if r['mode'] == 'validation')
            if validation_failures:
                times = {key: None for key in times}
            ng = p['learning']['train_scenes']+p['learning']['validation_scenes']
            reference = np.median([r['timings']['reference_seconds'] for r in generated])
            other = np.median([r['timings']['total_seconds']-r['timings']['reference_seconds'] for r in generated])
            report = dict(manifest_id=manifest['id'], complete=True, profile=p['profile'], scope=identity['scope'],
                rates_seconds=rates, operation_counts=budgets, validation_failures=validation_failures,
                projected_training_and_validation_hours=times,
                projected_data_generation_hours=float((reference*ng+other*(ntrain+nval))/3600),
                limitation='Two geometries at the first SNR only. Min/max are scenario projections, NOT confidence intervals. '
                           'Excludes checkpoint/log I/O, CPU/GPU contention, full six-method evaluation; fresh optimizer adds startup overhead.',
                measurements=measurements, data_generation=generated, updated=now())
            if any(file_hash(ROOT/name) != sha for name, sha in identity['sources'].items()):
                raise ValueError('Pilot source changed during measurement')
            atomic_json(output/'report.json', report)
            atomic_json(output/'state.json', dict(state='COMPLETE', owner=owner, updated=now()))
            return report
        except BaseException:
            atomic_json(output/'failure.json', dict(manifest_id=manifest['id'], traceback=traceback.format_exc(), updated=now()))
            atomic_json(output/'state.json', dict(state='FAILED', owner=owner, updated=now()))
            raise


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--smoke', action='store_true')
    parser.add_argument('--device', default='cuda:0')
    parser.add_argument('--repeats', type=int, default=3)
    args = parser.parse_args()
    report = profile(args.output, smoke=args.smoke, device=args.device, repeats=args.repeats)
    print(report['projected_training_and_validation_hours'], flush=True)


if __name__ == '__main__':
    main()
