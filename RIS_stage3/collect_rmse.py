"""Distance/BS-radial-velocity RMSE from all saved Stage-3 joint estimates.

This is full-data postprocessing, not a new simulation. The same direction-based
assignment used for angle errors is retained for both distance and velocity.
The original simulation files and experiment identity are not modified.
"""
import argparse
import csv
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path

import numpy as np
from scipy.optimize import linear_sum_assignment

METHODS = ['DD FFT', 'DD joint refinement', 'Random RIS + joint refinement',
           'Stage-3 optimized RIS']
COLORS = ['#6b7280', '#3478b5', '#b18a32', '#ca4260']
MARKERS = ['s', '^', 'D', 'o']


def atomic_json(path, data):
    path = Path(path)
    temp = path.with_suffix(path.suffix + f'.{os.getpid()}.tmp')
    temp.write_text(json.dumps(data, ensure_ascii=False, indent=2, allow_nan=False) + '\n',
                    encoding='utf-8', newline='\n')
    os.replace(temp, path)


def direction(angles):
    theta, phi = np.deg2rad(angles).T
    return np.column_stack((np.sin(theta)*np.cos(phi), np.sin(theta)*np.sin(phi),
                            np.cos(theta)))


def match_errors(estimates, truth):
    """One assignment for R, v, theta, phi; do not minimize each metric separately."""
    estimates, truth = np.asarray(estimates, float), np.asarray(truth, float)
    if estimates.shape != truth.shape or truth.ndim != 2 or truth.shape[1] != 4:
        raise ValueError('Estimates and truth must both have shape [targets,4]')
    if not np.all(np.isfinite(estimates)) or not np.all(np.isfinite(truth)):
        raise ValueError('Non-finite estimate or truth')
    cost = np.rad2deg(np.arccos(np.clip(direction(truth[:, 2:]) @
                                       direction(estimates[:, 2:]).T, -1, 1)))
    rows, cols = linear_sum_assignment(cost)
    order = cols[np.argsort(rows)]
    errors = estimates[order] - truth
    errors[:, 3] = (errors[:, 3] + 180) % 360 - 180
    return errors, order


def load_samples(source, manifest, partial=False):
    truth = np.asarray(manifest['config']['truth'], float)
    counts, data, audit = [], [], []
    digest = hashlib.sha256()
    seen = set()
    expected_names = set()
    for si, snr in enumerate(manifest['snr_db']):
        trials = []
        for trial in range(manifest['mc']):
            name = f'snr_{si:02d}_mc_{trial:04d}.json'
            expected_names.add(name)
            path = source/'samples'/name
            if not path.exists():
                continue
            raw = path.read_bytes()
            record = json.loads(raw)
            if (record['manifest_id'] != manifest['id'] or record['trial'] != trial or
                    float(record['snr_db']) != float(snr) or record['methods'] != METHODS):
                raise ValueError(f'Incompatible or mislabeled checkpoint: {path}')
            key = (float(snr), trial)
            if key in seen:
                raise ValueError(f'Duplicate sample: {key}')
            seen.add(key)
            estimates = np.asarray(record['estimates'], float)
            if estimates.shape != (len(METHODS), len(truth), 4):
                raise ValueError(f'Unexpected estimate shape: {path}')
            errors = []
            for method, estimate in enumerate(estimates):
                error, order = match_errors(estimate, truth)
                # Independent consistency check against the existing angle output.
                if not np.allclose(error[:, 2:], record['angular_errors_deg'][method],
                                   rtol=1e-9, atol=1e-8):
                    raise ValueError(f'Target assignment differs from angle experiment: {path}')
                errors.append(error)
                for target, estimate_index in enumerate(order):
                    audit.append(dict(snr_db=snr, trial=trial, seed=record['seed'],
                                      method=METHODS[method], target=target+1,
                                      estimate_index=int(estimate_index),
                                      range_error_m=float(error[target, 0]),
                                      velocity_error_mps=float(error[target, 1])))
            trials.append(np.array(errors))
            digest.update(name.encode('utf-8'))
            digest.update(raw)
        counts.append(len(trials))
        data.append(np.array(trials) if trials else np.empty((0, len(METHODS), len(truth), 4)))
    unexpected = {p.name for p in (source/'samples').glob('snr_*_mc_*.json')} - expected_names
    if unexpected:
        raise ValueError(f'Unexpected checkpoint filenames: {sorted(unexpected)[:3]}')
    complete = all(count == manifest['mc'] for count in counts)
    if not complete and not partial:
        raise ValueError(f'Incomplete experiment: {counts}; need {manifest["mc"]} per SNR')
    if not sum(counts):
        raise ValueError('No usable samples')
    return data, counts, audit, digest.hexdigest(), complete


def summarize(errors, parameter, bootstrap_indices, threshold):
    values = errors[:, :, :, parameter]  # MC, method, target
    squared = np.mean(values**2, axis=2)
    rmse = np.sqrt(np.mean(squared, axis=0))
    boot = np.sqrt(np.mean(squared[bootstrap_indices], axis=1))
    ci = np.quantile(boot, [.025, .975], axis=0).T
    details = []
    for method in range(len(METHODS)):
        e = values[:, method]
        row = dict(rmse=float(rmse[method]), ci95_low=float(ci[method, 0]),
                   ci95_high=float(ci[method, 1]), mean_error=float(np.mean(e)),
                   outlier_rate=float(np.mean(np.any(np.abs(e) > threshold, axis=1))))
        for target in range(e.shape[1]):
            row[f'target_{target+1}_rmse'] = float(np.sqrt(np.mean(e[:, target]**2)))
            row[f'target_{target+1}_bias'] = float(np.mean(e[:, target]))
        details.append(row)
    return rmse, ci, details


def write_csv(path, rows):
    temp = path.with_suffix(path.suffix+f'.{os.getpid()}.tmp')
    with temp.open('w', encoding='utf-8', newline='') as stream:
        writer = csv.DictWriter(stream, fieldnames=list(rows[0]), lineterminator='\n')
        writer.writeheader()
        writer.writerows(rows)
    os.replace(temp, path)


def plot_metric(output, stem, ylabel, snrs, rmse, ci, manifest, counts, complete):
    import matplotlib
    matplotlib.use('Agg')
    import matplotlib.pyplot as plt
    plt.rcParams.update({'font.family': 'DejaVu Sans', 'font.size': 12})
    fig, ax = plt.subplots(figsize=(9.2, 5.8), constrained_layout=True)
    for method, label in enumerate(METHODS):
        curve = np.where(rmse[:, method] > 0, rmse[:, method], np.nan)
        ax.semilogy(snrs, curve, color=COLORS[method], marker=MARKERS[method],
                    label=label, lw=2, ms=6)
        if min(counts) > 1:
            ax.fill_between(snrs, ci[:, method, 0], ci[:, method, 1],
                            color=COLORS[method], alpha=.12)
    ax.set(xlabel='SNR (dB)', ylabel=ylabel)
    if len(snrs) > 1:
        ax.set_xlim(min(snrs), max(snrs))
    ax.set_xticks(snrs)
    ax.grid(True, which='both', alpha=.25)
    ax.legend(fontsize=10)
    cfg = manifest['config']
    profile = 'FULL SCALE' if manifest['profile'] == 'full' else 'LOCAL SMOKE - NOT FINAL RESULTS'
    status = '' if complete else ' - INCOMPLETE'
    subtitle = (f"{cfg['ns']:,} subcarriers | {cfg['rx_nx']*cfg['rx_ny']} Rx | "
                f"{cfg['lc']+cfg['lf']} symbols | MC {min(counts)}-{max(counts)}/{manifest['mc']}")
    ax.set_title(profile+status+'\n'+subtitle, fontsize=11)
    for extension in ('png', 'svg'):
        final = output/f'{stem}.{extension}'
        temp = output/f'{stem}.{os.getpid()}.tmp.{extension}'
        fig.savefig(temp, dpi=220)
        os.replace(temp, final)
    plt.close(fig)


def collect(source, output, partial=False, bootstrap=2000, seed=20261015):
    source, output = Path(source), Path(output)
    manifest = json.loads((source/'manifest.json').read_text(encoding='utf-8'))
    data, counts, audit, sample_hash, complete = load_samples(source, manifest, partial)
    cfg = manifest['config']
    duration = (cfg['lc']+cfg['lf'])*(1/cfg['df']+cfg['cp_time'])
    thresholds = [cfg['c']/(2*cfg['ns']*cfg['df']), cfg['c']/(2*cfg['fc']*duration)]
    rng = np.random.default_rng(seed)
    grids = [np.full((len(data), len(METHODS)), np.nan) for _ in range(2)]
    intervals = [np.full((len(data), len(METHODS), 2), np.nan) for _ in range(2)]
    rows = [[], []]
    for si, (snr, errors) in enumerate(zip(manifest['snr_db'], data)):
        if not len(errors):
            continue
        indices = rng.integers(0, len(errors), size=(bootstrap, len(errors)))
        for parameter in range(2):
            rmse, ci, details = summarize(errors, parameter, indices, thresholds[parameter])
            grids[parameter][si], intervals[parameter][si] = rmse, ci
            for method, detail in zip(METHODS, details):
                rows[parameter].append(dict(snr_db=snr, method=method,
                                            mc_completed=len(errors), **detail,
                                            outlier_threshold=thresholds[parameter]))
    output.mkdir(parents=True, exist_ok=True)
    for parameter, stem, label in ((0, 'range_rmse_vs_snr', 'Range RMSE (m)'),
                                    (1, 'velocity_rmse_vs_snr', 'Radial velocity RMSE (m/s)')):
        write_csv(output/f'{stem}.csv', rows[parameter])
        plot_metric(output, stem, label, manifest['snr_db'], grids[parameter],
                    intervals[parameter], manifest, counts, complete)
    write_csv(output/'per_sample_range_velocity_errors.csv', audit)
    report = dict(complete=complete, source_manifest_id=manifest['id'],
                  source_code_sha256=manifest['code_sha256'],
                  postprocessor_sha256=hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
                  checkpoints_sha256=sample_hash, counts=counts,
                  total_completed=sum(counts), total_expected=manifest['mc']*len(counts),
                  snr_db=manifest['snr_db'], methods=METHODS,
                  source_profile=manifest['profile'], source_config=cfg,
                  processed_at_utc=datetime.now(timezone.utc).isoformat(),
                  range_metric='sqrt(mean over MC and targets of (R_est-R_true)^2), metre',
                  velocity_metric='sqrt(mean over MC and targets of (v_B_est-v_B_true)^2), m/s',
                  assignment='Same 3D-direction Hungarian assignment as original angle metric',
                  bootstrap=dict(unit='MC trial, targets and methods kept paired',
                                 draws=bootstrap, seed=seed, confidence=.95),
                  outlier_definition='Fraction of trials with any target error exceeding one native full-CPI FFT bin',
                  range_outlier_threshold_m=thresholds[0],
                  velocity_outlier_threshold_mps=thresholds[1],
                  new_simulation=False, clipped_errors=False, discarded_samples=0)
    atomic_json(output/'metrics_progress.json', report)
    (output/'state').write_text('COMPLETE\n' if complete else 'PARTIAL\n', encoding='utf-8')
    print(f"METRICS={'COMPLETE' if complete else 'PARTIAL'} SAMPLES={sum(counts)}/{report['total_expected']}", flush=True)
    print('SOURCE='+str(source.resolve()), flush=True)
    print('OUTPUT='+str(output.resolve()), flush=True)
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', type=Path, default=Path(__file__).parent/'results_full_mc100')
    parser.add_argument('--output', type=Path)
    parser.add_argument('--partial', action='store_true')
    parser.add_argument('--bootstrap', type=int, default=2000)
    parser.add_argument('--seed', type=int, default=20261015)
    args = parser.parse_args()
    if args.bootstrap < 100:
        parser.error('Use at least 100 bootstrap draws')
    output = args.output if args.output else args.source/'range_velocity_metrics'
    output.mkdir(parents=True, exist_ok=True)
    (output/'state').write_text('RUNNING\n', encoding='utf-8')
    try:
        collect(args.source, output, args.partial, args.bootstrap, args.seed)
    except Exception:
        (output/'state').write_text('FAILED\n', encoding='utf-8')
        raise


if __name__ == '__main__':
    main()
