"""Paired RMSE versus available-design budget, retaining deadline misses."""
import argparse
from pathlib import Path
import numpy as np
from .aggregate import METRICS, bootstrap_squared, sample_squared_errors, optional_float, write_csv
from .budget_design import METHODS, BUDGETS
from .run_budget import scan, progress
from .storage import read_json, atomic_json, digest, file_hash


def aggregate(source, output, *, partial=False, plots=True):
    source, output = Path(source).resolve(), Path(output).resolve()
    if source == output or output in source.parents:
        raise ValueError('Metrics must not overwrite source')
    manifest = read_json(source/'manifest.json')
    if manifest['id'] != digest(manifest['identity']):
        raise ValueError('Manifest digest mismatch')
    records = scan(source, manifest)
    state = progress(manifest, records)
    if not state['complete'] and not partial:
        raise ValueError('Incomplete budget experiment')
    p = manifest['identity']['protocol']
    rng = np.random.default_rng(p['evaluation']['bootstrap_seed'])
    rows = []
    for split in ('heldout', 'legacy'):
        for snr in sorted({c['snr_db'] for c in manifest['identity']['cases'] if c['split'] == split}):
            cases = [c for c in manifest['identity']['cases'] if c['split'] == split and c['snr_db'] == snr]
            for budget in BUDGETS:
                sq = np.full((len(cases), len(METHODS), 3), np.nan)
                groups = []
                for mi, method in enumerate(METHODS):
                    group = [records.get((c['sample_id'], f'{method}_{budget:g}s')) for c in cases]
                    groups.append(group)
                    for ci, r in enumerate(group):
                        if r is not None and r['status'] == 'SUCCESS':
                            sq[ci, mi] = sample_squared_errors(r['errors'])
                clusters = [c['scene_id'] if split == 'heldout' else c['sample_id'] for c in cases]
                boot, units = bootstrap_squared(sq, clusters, p['evaluation']['bootstrap_replicates'], rng)
                for mi, method in enumerate(METHODS):
                    group = groups[mi]
                    valid = np.isfinite(sq[:, mi, 0])
                    complete = bool(valid.all())
                    timed = [r.get('budget_timing') or (r.get('design') or {}).get('budget_timing') for r in group if r]
                    timed = [t for t in timed if t]
                    for ki, metric in enumerate(METRICS):
                        rmse = float(np.sqrt(sq[valid, mi, ki].mean())) if valid.any() else None
                        ci = np.quantile(boot[:, mi, ki], [.025, .975]) if complete and units > 1 else [np.nan]*2
                        paired = complete and np.isfinite(sq[:, 0, ki]).all()
                        delta = np.quantile(boot[:, mi, ki]-boot[:, 0, ki], [.025, .975]) if paired and units > 1 else [np.nan]*2
                        rows.append(dict(split=split, snr_db=snr, budget_seconds=budget, method=method, metric=metric,
                            expected=len(cases), successful=int(valid.sum()), missing=sum(r is None for r in group),
                            deadline_misses=sum(r is not None and r['status'] == 'DEADLINE_MISS' for r in group),
                            algorithm_failures=sum(r is not None and r['status'] == 'ALGORITHM_FAILURE' for r in group),
                            rmse=rmse if complete else None, conditional_success_rmse=rmse,
                            ci95_low=optional_float(ci[0]), ci95_high=optional_float(ci[1]),
                            paired_rmse_difference=(rmse-float(np.sqrt(sq[:, 0, ki].mean()))) if paired else None,
                            paired_ci95_low=optional_float(delta[0]), paired_ci95_high=optional_float(delta[1]),
                            independent_units=units,
                            median_actual_stop_seconds=float(np.median([t['actual_stop_seconds'] for t in timed])) if timed else None,
                            maximum_atomic_overrun_seconds=max(t['atomic_overrun_seconds'] for t in timed) if timed else None))
    output.mkdir(parents=True, exist_ok=True)
    report = dict(progress=state, profile=p['profile'], manifest_id=manifest['id'],
        samples_digest=digest({f'{a}/{b}': r['sha256'] for (a,b),r in sorted(records.items())}),
        aggregate_source_sha256=file_hash(Path(__file__)),
        timing=manifest['identity']['timing'],
        warning='Checkpoint-availability comparison, not guaranteed hard deadline. Missing/failed cases suppress headline RMSE.', rows=rows)
    atomic_json(output/'report.json', report)
    write_csv(output/'budget_rmse.csv', rows)
    if plots:
        import matplotlib
        matplotlib.use('Agg')
        import matplotlib.pyplot as plt
        for split in ('heldout', 'legacy'):
            snrs = sorted({r['snr_db'] for r in rows if r['split'] == split})
            for metric in METRICS:
                cols = min(3, len(snrs))
                fig, axes = plt.subplots((len(snrs)+cols-1)//cols, cols, squeeze=False,
                    figsize=(max(9, 5*cols), 4*((len(snrs)+cols-1)//cols)), constrained_layout=True)
                for ax, snr in zip(axes.flat, snrs):
                    for method in METHODS:
                        points = [r for r in rows if r['split'] == split and r['metric'] == metric and r['snr_db'] == snr and r['method'] == method]
                        ax.plot([r['budget_seconds'] for r in points],
                                [np.nan if r['rmse'] is None else r['rmse'] for r in points], 'o-', label=method)
                    ax.set(xlabel='Available-checkpoint budget (s)', ylabel=metric+' RMSE', title=f'SNR {snr:g} dB', xscale='log')
                    ax.ticklabel_format(axis='y', style='plain', useOffset=False)
                    ax.grid(alpha=.3)
                for ax in list(axes.flat)[len(snrs):]:
                    ax.set_visible(False)
                axes.flat[0].legend(fontsize=8)
                fig.suptitle(f'{p["profile"].upper()} {split}: {metric}\n' +
                             ('COMPLETE' if state['complete'] else 'INCOMPLETE') +
                             (' | NOT SCIENTIFIC RESULTS' if p['profile'] == 'smoke' else ''))
                for ext in ('png', 'svg'):
                    fig.savefig(output/f'{split}_{metric}_vs_budget.{ext}', dpi=160, bbox_inches='tight')
                plt.close(fig)
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--partial', action='store_true')
    args = parser.parse_args()
    print(aggregate(**vars(args))['progress'])


if __name__ == '__main__':
    main()
