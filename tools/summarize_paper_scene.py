"""Summarize only a complete, audited server run; never reinterpret PEB as RMSE."""
import argparse
import csv
import json
from pathlib import Path

import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
import numpy as np


def read_csv(path):
    with path.open(encoding='utf-8-sig', newline='') as stream:
        return list(csv.DictReader(stream))


def interval(values, rng):
    values = np.asarray(values, dtype=float)
    finite = np.isfinite(values)
    valid = values[finite]
    if not len(valid):
        return dict(median=None, ci95=None, finite=0, undefined=len(values))
    # Retain undefined cases in the count; conditional statistics are labeled.
    boot = np.median(valid[rng.integers(len(valid), size=(4000, len(valid)))], axis=1)
    return dict(median=float(np.median(valid)), ci95=np.quantile(boot, [.025, .975]).tolist(),
                finite=int(finite.sum()), undefined=int((~finite).sum()))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('directory', type=Path)
    args = parser.parse_args()
    root = args.directory
    manifest = json.loads((root / 'manifest.json').read_text(encoding='utf-8'))
    verification = json.loads((root / 'verification.json').read_text(encoding='utf-8'))
    assert manifest['profile'] == 'full' and manifest['mc'] == 300
    assert verification['complete'] and verification['count'] == 900
    assert manifest['id'] == verification['manifest_id']
    assert verification['per_channel'] == [300, 300, 300]
    rows = read_csv(root / 'case_metrics.csv')
    assert len(rows) == 900 * 8
    cases = {}
    for row in rows:
        key = (int(row['rice_index']), int(row['trial']))
        methods = cases.setdefault(key, {})
        assert row['method'] not in methods
        assert float(row['sinr']) >= 10 * (1 - 1e-8)
        methods[row['method']] = row
    assert len(cases) == 900 and all(len(m) == 8 for m in cases.values())
    rng = np.random.default_rng(40917)
    result = dict(manifest_id=manifest['id'], cases=900, actual_RMSE=False,
                  scope='Oracle gain-normalized paper-inspired DD/RR experiment', channels={})
    methods = ['Fixed_uniform_RIS', 'Fixed_edge_RIS', 'Fixed_best_RIS_refined',
               'FAS_RIS_guard0', 'FAS_RIS_guard4', 'Fixed_uniform_noRIS']
    labels = ['Uniform', 'Nonuniform', 'Refined fixed', 'FAS, guard 0', 'FAS, guard 4', 'Fixed, no RIS']
    for ri, channel in enumerate(manifest['rice_labels'], 1):
        samples = [cases[ri, trial] for trial in range(300)]
        fixed = np.array([float(c['Fixed_best_RIS_refined']['peb_m']) for c in samples])
        nonuniform = np.array([float(c['Fixed_edge_RIS']['peb_m']) for c in samples])
        fas = np.array([float(c['FAS_RIS_guard4']['peb_m']) for c in samples])
        fixed_best = np.array([min(float(c[m]['peb_m']) for m in methods[:3]) for c in samples])
        snr = np.array([float(c['FAS_RIS_guard4']['net_energy_snr_db']) -
                        float(c['Fixed_best_RIS_refined']['net_energy_snr_db']) for c in samples])
        with np.errstate(invalid='ignore', divide='ignore'):
            change = 100 * (1 - fas / fixed)
            edge_change = 100 * (1 - fas / nonuniform)
            sensitivity = 100 * (1 - fas / fixed_best)
        absolute = {}
        for m in methods:
            absolute[m] = interval([float(c[m]['peb_m']) for c in samples], rng)
        result['channels'][channel] = dict(
            net_energy_gain_db=interval(snr, rng),
            peb_reduction_pct=interval(change, rng),
            nonuniform_fixed_peb_reduction_pct=interval(edge_change, rng),
            wins_peb=int(np.sum(fas < fixed)),
            wins_peb_vs_nonuniform=int(np.sum(fas < nonuniform)),
            sensitivity_best_fixed_peb_reduction_pct=interval(sensitivity, rng),
            absolute_peb_m=absolute)
    (root / 'summary.json').write_text(json.dumps(result, ensure_ascii=False, indent=2, allow_nan=False) + '\n', encoding='utf-8', newline='\n')
    fig, axes = plt.subplots(1, 3, figsize=(13, 4.2), constrained_layout=True)
    channels = list(result['channels'])
    colors = ['#386cb0', '#f28e2b', '#59a14f']
    for i, channel in enumerate(channels):
        stats = result['channels'][channel]
        for ax, key, offset, marker in [
            (axes[0], 'net_energy_gain_db', 0, 'o'),
            (axes[1], 'peb_reduction_pct', -.08, 'o'),
            (axes[1], 'nonuniform_fixed_peb_reduction_pct', .08, 's'),
        ]:
            v = stats[key]
            if v['median'] is None:
                continue
            low, high = v['ci95']
            ax.errorbar(i + offset, v['median'], yerr=[[v['median'] - low], [high - v['median']]],
                        fmt=marker, color=colors[i], capsize=4, markersize=7)
        medians = [stats['absolute_peb_m'][m]['median'] for m in methods]
        axes[2].plot(range(len(methods)), medians, 'o-', color=colors[i], label=channel)
    for ax in axes[:2]:
        ax.axhline(0, color='.6', linewidth=.8)
        ax.set_xticks(range(3), channels)
        ax.grid(axis='y', alpha=.25)
    axes[0].set_ylabel('Net sensing-energy gain (dB)')
    axes[0].set_title('FAS guard 4 vs refined fixed')
    axes[1].set_ylabel('Position-bound reduction (%)')
    axes[1].set_title('Position bound: baseline sensitivity')
    axes[1].plot([], [], 'ko', label='vs refined fixed')
    axes[1].plot([], [], 'ks', label='vs nonuniform fixed')
    axes[1].legend(fontsize=8)
    axes[2].set_yscale('log')
    axes[2].set_ylabel('Median position bound (m)')
    axes[2].set_xticks(range(len(methods)), labels, rotation=25, ha='right')
    axes[2].grid(axis='y', alpha=.25)
    axes[2].legend(fontsize=8)
    fig.suptitle('Oracle normalized diagnostic; position bound, not measured localization RMSE', fontsize=11)
    fig.savefig(root / 'comparison.png', dpi=180)
    plt.close(fig)
    print(json.dumps({k: {n: v for n, v in x.items() if n != 'absolute_peb_m'}
                      for k, x in result['channels'].items()}, indent=2))


if __name__ == '__main__':
    main()
