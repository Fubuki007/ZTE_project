"""Paired six-method full-size evaluation of a frozen, completed training run."""
import argparse
from datetime import datetime, timezone
import hashlib
import os
from pathlib import Path
import platform
import tempfile
import time
import traceback

import numpy as np
import scipy
import torch
from threadpoolctl import threadpool_limits

from RIS_stage3.stage3_model import Model
from RIS_stage3.streaming import simulate_block, reference_power, coarse_from_records, Observation
from RIS_stage3.collect_rmse import match_errors
from .context import context_from_model
from .generate_dataset import ROOT, validate_manifest, sealed, verify_seal
from .physics_numpy import audit_design
from .protocol import model_config, require_execution_host, EXPECTED_METHODS
from .repair import DesignBudget, InfeasibleDesign, traditional_design, repair_design
from .scenes import build_scenes, build_cases
from .storage import atomic_json, digest, file_hash, read_json, directory_lock, now
from .train import TRAIN_SOURCES, load_selected, setup_runtime, weight_hash
from .unfolded_design import UnfoldedDesigner, network_candidate

SOURCES = tuple(sorted(set(TRAIN_SOURCES) | {'RIS_stage3/collect_rmse.py', 'RIS_stage3_ai/run_comparison.py'}))


def sources():
    return {name: file_hash(ROOT/name) for name in SOURCES}


def array_hash(*arrays):
    h = hashlib.sha256()
    for a in arrays:
        if a is None:
            h.update(b'None')
        else:
            a = np.ascontiguousarray(a)
            h.update(str((a.shape, str(a.dtype))).encode())
            h.update(a.tobytes())
    return h.hexdigest()


def validate_comparison(manifest, current_sources=False):
    i = manifest['identity']
    if manifest['id'] != digest(i) or i['kind'] != 'six_method_paired_comparison':
        raise ValueError('Comparison manifest digest/kind mismatch')
    registry = build_scenes(i['protocol'])
    if i['scenes'] != registry or i['cases'] != build_cases(i['protocol'], registry, ('heldout', 'legacy')):
        raise ValueError('Test registry differs from frozen protocol')
    if i['methods'] != EXPECTED_METHODS:
        raise ValueError('Six methods required')
    if current_sources and i['sources'] != sources():
        raise ValueError('Comparison code changed; use a new output')
    return manifest


def result_path(output, case, method):
    return Path(output)/'samples'/case['sample_id']/f'{method}.json'


def read_result(output, manifest, case, method):
    record = verify_seal(read_json(result_path(output, case, method)))
    if record['manifest_id'] != manifest['id'] or record['case'] != case or record['method'] != method:
        raise ValueError('Result identity mismatch')
    if record['status'] not in ('SUCCESS', 'ALGORITHM_FAILURE'):
        raise ValueError('Nonterminal result')
    coarse_path = Path(output)/'coarse'/f'{case["sample_id"]}.json'
    coarse = verify_seal(read_json(coarse_path))
    if (file_hash(coarse_path) != record['coarse_sha256'] or coarse['manifest_id'] != manifest['id']
            or coarse['case'] != case or coarse['noise_variance'] != record['noise_variance']
            or coarse['reference_power'] != record['reference_power']):
        raise ValueError('Coarse/noise pairing checkpoint mismatch')
    if record['status'] == 'SUCCESS':
        estimate = np.asarray(record['estimate'], float)
        if estimate.shape != (2, 4) or not np.isfinite(estimate).all():
            raise ValueError('Malformed estimate')
        scene = next(s for s in manifest['identity']['scenes'] if s['scene_id'] == case['scene_id'])
        error, order = match_errors(estimate, scene['truth'])
        if not np.allclose(error, record['errors'], rtol=0, atol=1e-10) or list(order) != record['assignment']:
            raise ValueError('Metric/assignment audit failed')
    return record


def scan_results(output, manifest):
    records = {}
    allowed = set()
    for case in manifest['identity']['cases']:
        for method in EXPECTED_METHODS:
            path = result_path(output, case, method)
            allowed.add(path.resolve())
            if path.exists():
                records[(case['sample_id'], method)] = read_result(output, manifest, case, method)
    extra = {p.resolve() for p in (Path(output)/'samples').glob('*/*.json')} - allowed
    if extra:
        raise ValueError('Unregistered comparison result files')
    return records


def result_progress(manifest, records):
    cases = manifest['identity']['cases']
    paired = sum(all((c['sample_id'], m) in records for m in EXPECTED_METHODS) for c in cases)
    failures = sum(r['status'] == 'ALGORITHM_FAILURE' for r in records.values())
    return dict(manifest_id=manifest['id'], profile=manifest['identity']['protocol']['profile'],
        terminal_methods=len(records), expected_methods=len(cases)*6,
        complete_paired_cases=paired, expected_paired_cases=len(cases),
        algorithm_failures=failures, complete=paired == len(cases),
        all_methods_successful=paired == len(cases) and failures == 0, updated=now())


def design_method(method, ctx, model, trained, untrained, p):
    settings = next(m for m in p['methods'] if m['id'] == method)
    if method == 'dd_joint':
        w = model.wzf.copy()
        power = float(np.sum(np.abs(w)**2))
        minimum = float(np.min(model.sinr(w, None)))
        feasible = power <= model.cfg.ns*(1+1e-5) and minimum >= model.cfg.gamma*(1-1e-4)
        if not feasible:
            raise InfeasibleDesign('DD beam failed power/QoS')
        return w, None, dict(final=dict(feasible=True, power=power, min_sinr=minimum), fallback_used=False)
    if method.startswith('stage3_'):
        w, phase, info = traditional_design(ctx, DesignBudget(settings['ao'], settings['sca'], settings['phase_sweeps']))
        return w, phase, dict(optimization=info, final=info['final'], fallback_used=False)
    network = trained if method == 'learned_physics' else untrained
    try:
        w, phase, candidate = network_candidate(ctx, network, straight_through=True)
    except FloatingPointError as exc:
        w, phase, fallback = traditional_design(ctx)
        return w, phase, dict(candidate_failure=str(exc), fallback=fallback,
                             final=fallback['final'], fallback_used=True)
    w, phase, repair = repair_design(ctx, w, phase,
        DesignBudget(settings['repair_ao'], settings['repair_sca'], settings['repair_phase_sweeps']))
    return w, phase, dict(candidate=candidate, repair=repair, final=repair['final'], fallback_used=repair['fallback_used'])


def run_method(method, case, cfg_sim, cfg_est, model, ctx, coarse, rc, variance,
               trained, untrained, p, work, context_seconds, coarse_seconds, *, prepared=None):
    device = trained.raw_w_steps.device
    if device.type == 'cuda':
        torch.cuda.synchronize(device)
    started = time.perf_counter()
    w, phase, design = (design_method(method, ctx, model, trained, untrained, p)
                        if prepared is None else prepared)
    if phase is not None and not audit_design(ctx, w, phase)['feasible']:
        raise InfeasibleDesign('Final independent transmit audit failed')
    if device.type == 'cuda':
        torch.cuda.synchronize(device)
    design_seconds = time.perf_counter()-started + (0. if method == 'dd_joint' else context_seconds)
    if prepared is not None:
        # Actual processing includes an atomic update's overrun. The earlier
        # candidate availability time is reported separately in budget_timing.
        design_seconds = design['budget_timing']['actual_stop_seconds']
    times = np.arange(cfg_sim.lc, cfg_sim.lc+cfg_sim.lf)*cfg_sim.symbol_time
    start = time.perf_counter()
    fine = simulate_block(cfg_sim, w, phase, times, variance, case['fine_seed'],
                          work/'fine.npy', p['execution']['batch_subcarriers'])
    try:
        simulation_seconds = time.perf_counter()-start
        rf = dict(y=fine, w=w, phase=phase, times=times)
        start = time.perf_counter()
        obs = Observation(cfg_est, [rc, rf], p['execution']['batch_subcarriers'])
        # Same DD full-CPI initialization as the legacy baseline; RIS uses common coarse input.
        initial = coarse_from_records(cfg_est, [rc, rf]) if method == 'dd_joint' else coarse
        estimate, diagnostics = obs.refine(initial, paths=phase is not None)
        refinement_seconds = time.perf_counter()-start
        if not np.isfinite(estimate).all():
            raise FloatingPointError('Non-finite estimate')
        errors, order = match_errors(estimate, cfg_sim.truth)
        return dict(status='SUCCESS', estimate=estimate.tolist(), errors=errors.tolist(), assignment=order.tolist(),
            design=design, diagnostics=diagnostics, design_sha256=array_hash(w, phase),
            phase=None if phase is None else np.column_stack([phase.real, phase.imag]).tolist(),
            timings=dict(design_seconds=design_seconds, context_seconds=0. if phase is None else context_seconds,
                         fine_simulation_seconds=simulation_seconds, refinement_seconds=refinement_seconds,
                         processing_seconds=coarse_seconds+design_seconds+refinement_seconds),
            estimator_truth='unavailable_NaN')
    finally:
        fine._mmap.close()
        del fine
        (work/'fine.npy').unlink(missing_ok=True)


def compare(dataset, training, output, *, smoke=False, device='cpu', limit=None):
    if limit is not None and (type(limit) is not int or limit < 1):
        raise ValueError('limit counts positive NEW method evaluations')
    dataset, training, output = map(lambda p: Path(p).resolve(), (dataset, training, output))
    for source in (dataset, training):
        if output == source or output in source.parents or source in output.parents:
            raise ValueError('Comparison output must be separate from inputs')
    data_manifest = validate_manifest(read_json(dataset/'manifest.json'), current_sources=True)
    p = data_manifest['identity']['protocol']
    if smoke != (p['profile'] == 'smoke'):
        raise ValueError('Explicit --smoke must match the data profile')
    require_execution_host(p)
    device = setup_runtime(p, device)
    load_start = time.perf_counter()
    trained, selected = load_selected(training, device=device, allow_smoke=smoke)
    if selected['dataset_id'] != data_manifest['id'] or selected['profile'] != p['profile']:
        raise ValueError('Model/dataset profile or identity mismatch')
    untrained = UnfoldedDesigner(trained.config).to(device).eval()
    load_seconds = time.perf_counter()-load_start
    scenes = build_scenes(p)
    cases = build_cases(p, scenes, ('heldout', 'legacy'))
    identity = dict(kind='six_method_paired_comparison', schema=1, protocol=p, scenes=scenes, cases=cases,
        methods=EXPECTED_METHODS, sources=sources(), selected=selected,
        untrained_weight_sha256=weight_hash(untrained.state_dict()),
        environment=dict(python=platform.python_version(), numpy=np.__version__, scipy=scipy.__version__,
                         torch=str(torch.__version__), device=str(device),
                         device_name=torch.cuda.get_device_name(device) if device.type == 'cuda' else platform.machine()),
        pairing='same coarse block, fine seed, noise variance, chunking and CPI across methods',
        timing='no warmup; model load separate; design includes context, transfer, repair and fallback; '
               'processing=coarse estimation+design+fine refinement; simulation excluded',
        method_order='seeded permutation per paired case, invariant to restarts',
        assignment='3D-direction Hungarian, one assignment for all four parameters',
        failure_policy='terminal algorithm failures retained; infrastructure failures stop and resume')
    manifest = dict(id=digest(identity), identity=identity)
    with directory_lock(output) as owner:
        if (output/'manifest.json').exists():
            if read_json(output/'manifest.json') != manifest:
                raise ValueError('Comparison identity changed; use a new output')
        else:
            if (output/'samples').exists():
                raise ValueError('Refusing samples without comparison manifest')
            atomic_json(output/'manifest.json', manifest)
        (output/'work').mkdir(exist_ok=True)
        records = scan_results(output, manifest)
        status = dict(owner=owner, manifest_id=manifest['id'], state='RUNNING', updated=now(), model_load_seconds=load_seconds)
        atomic_json(output/'state.json', status)
        scene_map = {s['scene_id']: s for s in scenes}
        references, produced = {}, 0
        current_case, current_method = None, None
        try:
            with threadpool_limits(limits=p['execution']['blas_threads_per_worker']):
                for case in cases:
                    if all((case['sample_id'], m) in records for m in EXPECTED_METHODS):
                        continue
                    if limit is not None and produced >= limit:
                        break
                    current_case = case
                    scene = scene_map[case['scene_id']]
                    cfg_sim = model_config(p, truth=scene['truth'], user_angles=scene['user_angles'])
                    cfg_est = model_config(p, user_angles=scene['user_angles'])
                    model = Model(cfg_est)
                    coarse_path = output/'coarse'/f'{case["sample_id"]}.json'
                    saved = verify_seal(read_json(coarse_path)) if coarse_path.exists() else None
                    if saved is not None and (saved['manifest_id'] != manifest['id'] or saved['case'] != case):
                        raise ValueError('Coarse checkpoint identity mismatch')
                    if scene['scene_id'] not in references:
                        references[scene['scene_id']] = saved['reference_power'] if saved else reference_power(cfg_sim, p['execution']['batch_subcarriers'])
                    ref = references[scene['scene_id']]
                    variance = ref/10**(case['snr_db']/10)
                    times = np.arange(cfg_sim.lc)*cfg_sim.symbol_time
                    with tempfile.TemporaryDirectory(prefix=case['sample_id']+'_', dir=output/'work') as temp:
                        work = Path(temp)
                        yc = simulate_block(cfg_sim, model.wzf, None, times, variance, case['coarse_seed'],
                                             work/'coarse.npy', p['execution']['batch_subcarriers'])
                        try:
                            rc = dict(y=yc, w=model.wzf, phase=None, times=times)
                            start = time.perf_counter()
                            coarse = coarse_from_records(cfg_est, [rc])
                            coarse_seconds = time.perf_counter()-start
                            if saved is not None:
                                if not np.allclose(coarse, saved['coarse'], atol=1e-10, rtol=0):
                                    raise ValueError('Replayed coarse estimate differs from checkpoint')
                                coarse_seconds = saved['coarse_seconds']
                            else:
                                atomic_json(coarse_path, sealed(dict(manifest_id=manifest['id'], case=case,
                                    coarse=coarse.tolist(), coarse_seconds=coarse_seconds,
                                    reference_power=ref, noise_variance=variance)))
                            start = time.perf_counter()
                            ctx = context_from_model(model, coarse)
                            context_seconds = time.perf_counter()-start
                            order = np.random.default_rng(case['fine_seed']).permutation(EXPECTED_METHODS).tolist()
                            for method in order:
                                if (case['sample_id'], method) in records:
                                    continue
                                if limit is not None and produced >= limit:
                                    break
                                current_method = method
                                status.update(current_case=case['sample_id'], current_method=method, updated=now())
                                atomic_json(output/'state.json', status)
                                print(f'START {case["sample_id"]} {method}', flush=True)
                                start = time.perf_counter()
                                try:
                                    result = run_method(method, case, cfg_sim, cfg_est, model, ctx, coarse, rc,
                                        variance, trained, untrained, p, work, context_seconds, coarse_seconds)
                                except (InfeasibleDesign, FloatingPointError, np.linalg.LinAlgError) as exc:
                                    result = dict(status='ALGORITHM_FAILURE', error=f'{type(exc).__name__}: {exc}',
                                                  traceback=traceback.format_exc(), seconds_until_failure=time.perf_counter()-start)
                                validate_comparison(manifest, current_sources=True)
                                record = sealed(dict(manifest_id=manifest['id'], case=case, method=method,
                                    noise_variance=variance, reference_power=ref, coarse_sha256=file_hash(coarse_path),
                                    method_order=order, saved_at=now(), **result))
                                atomic_json(result_path(output, case, method), record)
                                records[(case['sample_id'], method)] = record
                                produced += 1
                                report = result_progress(manifest, records)
                                atomic_json(output/'progress.json', report)
                                print(f'SAVED {method} {result["status"]} {report["terminal_methods"]}/{report["expected_methods"]}', flush=True)
                        finally:
                            yc._mmap.close()
                            del yc
                report = result_progress(manifest, records)
                atomic_json(output/'progress.json', report)
                status.update(state='COMPLETE' if report['complete'] else 'PAUSED_LIMIT', updated=now(), current_case=None, current_method=None)
                atomic_json(output/'state.json', status)
                return report
        except BaseException as exc:
            stamp = datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S%f')
            atomic_json(output/'failures'/f'{stamp}_{os.getpid()}.json', dict(manifest_id=manifest['id'],
                case=current_case, method=current_method, error=f'{type(exc).__name__}: {exc}',
                traceback=traceback.format_exc(), failed_at=now(), owner=owner))
            status.update(state='INTERRUPTED' if isinstance(exc, KeyboardInterrupt) else 'FAILED', updated=now())
            atomic_json(output/'state.json', status)
            raise


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--dataset', type=Path)
    parser.add_argument('--training', type=Path)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--smoke', action='store_true')
    parser.add_argument('--device', default='cpu')
    parser.add_argument('--limit', type=int, help='New method evaluations, without changing expected counts')
    parser.add_argument('--status', action='store_true')
    args = parser.parse_args()
    if args.status:
        manifest = validate_comparison(read_json(args.output/'manifest.json'))
        print(result_progress(manifest, scan_results(args.output, manifest)), flush=True)
        return
    if args.dataset is None or args.training is None:
        parser.error('--dataset and --training required')
    print(compare(args.dataset, args.training, args.output, smoke=args.smoke, device=args.device, limit=args.limit), flush=True)


if __name__ == '__main__':
    main()
