"""Audited angle/range/velocity RMSE, paired cluster CIs and measured timings."""
import argparse
import csv
from pathlib import Path

import numpy as np

from .protocol import EXPECTED_METHODS
from .run_comparison import validate_comparison, scan_results, result_progress
from .storage import atomic_json, digest, file_hash, read_json

METRICS = ('angle_deg', 'range_m', 'velocity_mps')
LABELS = dict(dd_joint='DD joint', stage3_original='Original RIS (3/3/2)',
    stage3_short='Short RIS (1/1/1)', untrained_physics='Untrained physics + repair',
    learned_physics='Learned physics + repair', stage3_extended='Extended RIS (8/5/3)')


def sample_squared_errors(errors):
    errors = np.asarray(errors, float)
    if errors.shape != (2, 4) or not np.isfinite(errors).all():
        raise ValueError('Expected finite two-target errors')
    return np.array([np.mean(errors[:, 2:]**2), np.mean(errors[:, 0]**2), np.mean(errors[:, 1]**2)])


def bootstrap_squared(squared, cluster_ids, draws, rng):
    """Keep all methods/metrics paired. Average equal-size scene clusters first."""
    squared = np.asarray(squared, float)
    ids = np.asarray(cluster_ids)
    groups = sorted(set(cluster_ids))
    if squared.shape[0] != len(ids) or not groups:
        raise ValueError('Empty/mismatched bootstrap data')
    sizes = [int(np.sum(ids == group)) for group in groups]
    if len(set(sizes)) != 1:
        raise ValueError('Unequal cluster sizes require an explicit weighted protocol')
    means = np.stack([squared[ids == group].mean(axis=0) for group in groups])
    indices = rng.integers(0, len(groups), size=(draws, len(groups)))
    return np.sqrt(means[indices].mean(axis=1)), len(groups)


def write_csv(path, rows):
    with Path(path).open('w', encoding='utf-8', newline='') as stream:
        writer = csv.DictWriter(stream, fieldnames=list(rows[0]), lineterminator='\n')
        writer.writeheader()
        writer.writerows(rows)


def optional_float(value):
    return float(value) if np.isfinite(value) else None


def summarize_group(cases, records, p, rng):
    n = len(cases)
    sq = np.full((n, 6, 3), np.nan)
    successful = np.zeros((n, 6), bool)
    failed = np.zeros((n, 6), bool)
    audits = []
    for ci, case in enumerate(cases):
        for mi, method in enumerate(EXPECTED_METHODS):
            record = records.get((case['sample_id'], method))
            if record is None:
                continue
            if record['status'] == 'ALGORITHM_FAILURE':
                failed[ci, mi] = True
                audits.append(dict(sample_id=case['sample_id'], scene_id=case['scene_id'], method=method,
                    snr_db=case['snr_db'], split=case['split'], status=record['status'],
                    assignment='', errors='', error=record['error']))
                continue
            successful[ci, mi] = True
            sq[ci, mi] = sample_squared_errors(record['errors'])
            audits.append(dict(sample_id=case['sample_id'], scene_id=case['scene_id'], method=method,
                snr_db=case['snr_db'], split=case['split'], status=record['status'],
                assignment=record['assignment'], errors=record['errors'], error=''))
    split, snr = cases[0]['split'], cases[0]['snr_db']
    clusters = [c['scene_id'] if split == 'heldout' else c['sample_id'] for c in cases]
    boot, nclusters = bootstrap_squared(sq, clusters, p['evaluation']['bootstrap_replicates'], rng)
    ci_available = nclusters > 1
    rows = []
    duration = (p['physical']['lc']+p['physical']['lf'])*(1/p['physical']['df']+p['physical']['cp_time'])
    thresholds = [5., 3e8/(2*p['physical']['ns']*p['physical']['df']), 3e8/(2*p['physical']['fc']*duration)]
    for mi, method in enumerate(EXPECTED_METHODS):
        selected = [records[(c['sample_id'], method)] for k, c in enumerate(cases) if successful[k, mi]]
        ns, nf = int(successful[:, mi].sum()), int(failed[:, mi].sum())
        all_success = ns == n
        baseline_success = successful[:, 1].all()
        design_times = [r['timings']['design_seconds'] for r in selected]
        processing_times = [r['timings']['processing_seconds'] for r in selected]
        raw = [r['design']['repair']['raw']['feasible'] for r in selected if 'repair' in r['design']]
        fallbacks = sum(r['design']['fallback_used'] for r in selected)
        for ki, metric in enumerate(METRICS):
            successful_rmse = float(np.sqrt(sq[successful[:, mi], mi, ki].mean())) if ns else None
            interval = np.quantile(boot[:, mi, ki], [.025, .975]) if all_success and ci_available else [np.nan]*2
            paired = boot[:, mi, ki]-boot[:, 1, ki]
            paired_interval = np.quantile(paired, [.025, .975]) if all_success and baseline_success and ci_available else [np.nan]*2
            if selected:
                es = np.array([r['errors'] for r in selected])
                values = es[:, :, 2:] if ki == 0 else es[:, :, (0 if ki == 1 else 1)]
                outliers = float(np.any(np.abs(values).reshape(ns, -1) > thresholds[ki], axis=1).mean())
            else:
                outliers = None
            rows.append(dict(split=split, snr_db=snr, method=method, metric=metric,
                expected_cases=n, successful_cases=ns, algorithm_failures=nf, missing_cases=n-ns-nf,
                rmse=successful_rmse if all_success else None,
                ci95_low=optional_float(interval[0]), ci95_high=optional_float(interval[1]),
                conditional_success_rmse=successful_rmse,
                paired_rmse_difference_vs_original=(float(np.sqrt(sq[:, mi, ki].mean())-np.sqrt(sq[:, 1, ki].mean()))
                                                    if all_success and baseline_success else None),
                paired_difference_ci95_low=optional_float(paired_interval[0]),
                paired_difference_ci95_high=optional_float(paired_interval[1]),
                resampling_units=nclusters, resampling_unit='scene' if split == 'heldout' else 'MC trial',
                outlier_threshold=thresholds[ki], conditional_success_outlier_rate=outliers,
                design_audit_samples=ns, raw_feasibility_samples=len(raw),
                raw_feasible_rate=float(np.mean(raw)) if raw else None,
                final_feasible_rate=float(np.mean([r['design']['final']['feasible'] for r in selected])) if ns else None,
                fallback_count=fallbacks,
                conditional_fallback_rate=fallbacks/ns if ns else None,
                median_design_seconds=float(np.median(design_times)) if ns else None,
                p95_design_seconds=float(np.quantile(design_times, .95)) if ns else None,
                median_processing_seconds=float(np.median(processing_times)) if ns else None))
    return rows, audits


def plot_rows(directory, rows, profile, complete, selected):
    import matplotlib
    matplotlib.use('Agg')
    import matplotlib.pyplot as plt
    colors = ['#68707a', '#2574aa', '#b08a30', '#8b67ad', '#cb4266', '#269b79']
    ylabels = ['Angle RMSE (degree)', 'Range RMSE (m)', 'Radial velocity RMSE (m/s)']
    status = 'FULL SCALE' if profile == 'full' else 'LOCAL SMOKE - NOT SCIENTIFIC RESULTS'
    if not complete:
        status += ' - INCOMPLETE'
    if not selected['weights_changed']:
        status += ' | selected model = initialization'
    for split in ('heldout', 'legacy'):
        for metric, ylabel in zip(METRICS, ylabels):
            fig, ax = plt.subplots(figsize=(9.5, 6), constrained_layout=True)
            for method, color, marker in zip(EXPECTED_METHODS, colors, ['s', '^', 'v', 'D', 'o', 'P']):
                points = sorted([r for r in rows if r['split'] == split and r['method'] == method and r['metric'] == metric], key=lambda r: r['snr_db'])
                x = [r['snr_db'] for r in points]
                y = [np.nan if r['rmse'] is None else r['rmse'] for r in points]
                ax.plot(x, y, marker=marker, color=color, label=LABELS[method], lw=1.7)
                lower = [np.nan if r['ci95_low'] is None else r['ci95_low'] for r in points]
                upper = [np.nan if r['ci95_high'] is None else r['ci95_high'] for r in points]
                ax.fill_between(x, lower, upper, color=color, alpha=.1)
            valid = [r['rmse'] for r in rows if r['split'] == split and r['metric'] == metric and r['rmse'] is not None]
            if valid and min(valid) > 0:
                ax.set_yscale('log')
            ax.set(xlabel='SNR (dB)', ylabel=ylabel, title=f'{status}\n{split}; missing/failed methods have no headline RMSE')
            ax.set_xticks(sorted({r['snr_db'] for r in rows if r['split'] == split}))
            ax.grid(True, which='both', alpha=.25)
            ax.legend(fontsize=9)
            for extension in ('png', 'svg'):
                fig.savefig(directory/f'{split}_{metric}_vs_snr.{extension}', dpi=180)
            plt.close(fig)


def aggregate(source, output, *, partial=False, plots=True):
    source, output = Path(source).resolve(), Path(output).resolve()
    if output == source or output in source.parents:
        raise ValueError('Use a separate metrics output or a child metrics directory')
    manifest = validate_comparison(read_json(source/'manifest.json'))
    records = scan_results(source, manifest)
    state = result_progress(manifest, records)
    if not state['complete'] and not partial:
        raise ValueError('Incomplete comparison; explicit --partial required')
    p = manifest['identity']['protocol']
    rng = np.random.default_rng(p['evaluation']['bootstrap_seed'])
    rows, audits = [], []
    for split, key in [('heldout', 'heldout_test'), ('legacy', 'legacy_test')]:
        for snr in p[key]['snr_db']:
            cases = [c for c in manifest['identity']['cases'] if c['split'] == split and c['snr_db'] == snr]
            group_rows, group_audit = summarize_group(cases, records, p, rng)
            rows.extend(group_rows)
            audits.extend(group_audit)
    input_hash = digest({f'{key[0]}/{key[1]}': record['sha256'] for key, record in sorted(records.items())})
    identity = dict(comparison_id=manifest['id'], sample_digest=input_hash,
                    aggregate_source_sha256=file_hash(Path(__file__)), partial=partial,
                    bootstrap_replicates=p['evaluation']['bootstrap_replicates'], bootstrap_seed=p['evaluation']['bootstrap_seed'])
    output.mkdir(parents=True, exist_ok=True)
    report = dict(identity=identity, progress=state, profile=p['profile'],
        selection=manifest['identity']['selected'],
        metric_order=list(METRICS), assignment=manifest['identity']['assignment'],
        failure_policy='No fabricated finite error for failure. Headline RMSE/CI absent unless every expected case succeeds; conditional-success RMSE labeled separately.',
        confidence_intervals='paired scene-cluster bootstrap for heldout, paired MC bootstrap for legacy; unavailable with one independent unit',
        clipped_errors=False, discarded_outliers=0,
        timing='Fixed-iteration methods at measured latency; this is NOT a matched-time-budget sweep.', rows=rows)
    write_csv(output/'rmse_and_timing.csv', rows)
    if audits:
        write_csv(output/'per_sample_errors.csv', audits)
    atomic_json(output/'report.json', report)
    if plots:
        plot_rows(output, rows, p['profile'], state['complete'], manifest['identity']['selected'])
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--partial', action='store_true')
    args = parser.parse_args()
    report = aggregate(args.source, args.output, partial=args.partial)
    print(report['progress'], flush=True)


if __name__ == '__main__':
    main()
