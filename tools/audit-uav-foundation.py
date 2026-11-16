"""Independently audit fetched full-run results, using only Python's standard library.

Run from the repository root: python tools/audit-uav-foundation.py <results-directory>
"""

import csv
import hashlib
import json
import math
import pathlib
import random
import statistics
import subprocess
import sys

root = pathlib.Path(sys.argv[1])
release = root.name
manifest = json.loads((root / 'manifest.json').read_text())
summary = json.loads((root / 'summary.json').read_text())
verification = json.loads((root / 'verification.json').read_text())
completion = json.loads((root / 'completion_status.json').read_text())
cfg = manifest['config']
methods = cfg['methods']
rcs_values = cfg['rcs_m2']
assert verification['passed'] and verification['cases'] == 900
assert completion['state'] == 'COMPLETE' and completion['checkpoints'] == 900
assert len(completion['workers']) == 8
assert all(w['state'] == 'COMPLETE' and w['completed'] == w['assigned']
           for w in completion['workers'])
assert summary['complete_cases'] == manifest['total_cases'] == 900
assert summary['manifest_id'] == verification['manifest_id'] == manifest['id']
assert cfg['mc'] == 300 and cfg['profile'] == 'full'
prefix = 'stage3-RIS与毫米波通感一体化联合优化算法方案/code/'
for item in manifest['source']:
    blob = subprocess.check_output(['git', 'show', release + ':' + prefix + item['file']])
    assert hashlib.sha256(blob).hexdigest() == item['sha256'], item['file']

def flag(value):
    assert value.lower() in ('0', '1', 'false', 'true')
    return value.lower() in ('1', 'true')

def close(a, b):
    assert math.isclose(a, b, rel_tol=1e-8, abs_tol=1e-7), (a, b)

with (root / 'case_metrics.csv').open(newline='', encoding='utf-8-sig') as stream:
    rows = list(csv.DictReader(stream))
assert len(rows) == 3600
index = {}
for row in rows:
    trial = int(row['trial'])
    rcs = float(row['rcs_m2'])
    method = row['method']
    key = trial, rcs, method
    assert key not in index and 0 <= trial < 300 and rcs in rcs_values and method in methods
    index[key] = row
    assert int(row['seed']) == cfg['seed'] + 10000 * trial
    e1, e2 = float(row['target1_error_m']), float(row['target2_error_m'])
    assert all(math.isfinite(e) and e >= 0 for e in (e1, e2))
    row['mse'] = (e1 * e1 + e2 * e2) / 2
    close(float(row['position_rmse_m']), math.sqrt(row['mse']))
    row['locked_flag'], row['feasible_flag'], row['failure_flag'] = (
        flag(row[k]) for k in ('locked', 'feasible', 'failure'))
    assert row['failure_flag'] == (not row['locked_flag'] or not row['feasible_flag']
                                 or max(e1, e2) > cfg['failure_position_m'])
    xyz = [float(row['hover_' + axis]) for axis in 'xyz']
    assert xyz in (cfg['candidates'] if method.startswith('Selected') else [cfg['hover']])
    if row['feasible_flag']:
        assert float(row['min_sinr_db']) >= 10 - 1e-7
        assert float(row['tx_power_fraction']) <= 1 + 1e-6

groups = []
max_delta = 0
for ri, rcs in enumerate(rcs_values):
    for mi, method in enumerate(methods):
        group = [index[trial, rcs, method] for trial in range(300)]
        rmse = math.sqrt(statistics.mean(r['mse'] for r in group))
        max_delta = max(max_delta, abs(rmse - summary['position_rmse_m'][ri][mi]))
        close(rmse, summary['position_rmse_m'][ri][mi])
        rates = {}
        for key, field in [('capture', 'locked_flag'), ('fine_feasible', 'feasible_flag'),
                           ('failure', 'failure_flag')]:
            count = sum(r[field] for r in group)
            close(count / 300, summary[key + '_rate'][ri][mi])
            rates[key + '_count'] = count
        for key, field in [('coarse_position_rmse_m', 'coarse_rmse_m'),
                           ('velocity_rmse_mps', 'velocity_rmse_mps')]:
            close(math.sqrt(statistics.mean(float(r[field]) ** 2 for r in group)),
                  summary[key][ri][mi])
        captured = [r for r in group if r['locked_flag'] and r['feasible_flag']]
        ordered = sorted(float(r['position_rmse_m']) for r in group)
        groups.append(dict(rcs_m2=rcs, method=method, position_rmse_m=rmse,
                           median_case_rmse_m=statistics.median(ordered),
                           p90_case_rmse_m=ordered[269], maximum_case_rmse_m=ordered[-1],
                           captured_position_rmse_m=math.sqrt(statistics.mean(r['mse'] for r in captured))
                           if captured else None, **rates))
    for trial in range(300):
        a, b = (index[trial, rcs, method] for method in methods[:2])
        close(float(a['coarse_rmse_m']), float(b['coarse_rmse_m']))
        assert a['locked_flag'] == b['locked_flag']

pair_ids = [(0, 2), (1, 3), (0, 1), (2, 3)]
comparisons = []
for original in summary['comparisons']:
    names = ['position_without_RIS', 'position_with_RIS', 'RIS_at_fixed_position',
             'RIS_after_position_selection']
    ai, bi = pair_ids[names.index(original['name'])]
    rcs = original['rcs_m2']
    a = [index[t, rcs, methods[ai]] for t in range(300)]
    b = [index[t, rcs, methods[bi]] for t in range(300)]
    gain = 100 * (1 - math.sqrt(statistics.mean(r['mse'] for r in b)
                               / statistics.mean(r['mse'] for r in a)))
    close(gain, original['gain_percent'])
    common = [(x, y) for x, y in zip(a, b)
              if x['locked_flag'] and x['feasible_flag'] and y['locked_flag'] and y['feasible_flag']]
    detail = dict(name=original['name'], rcs_m2=rcs, gain_percent=gain,
                  common_capture_feasible_cases=len(common),
                  common_capture_rmse_m=[math.sqrt(statistics.mean(pair[k]['mse'] for pair in common))
                                         for k in (0, 1)] if common else None,
                  improvement_cases=sum(y['mse'] < x['mse'] for x, y in zip(a, b)))
    if original['primary']:
        rng = random.Random(cfg['bootstrap_seed'])
        boot = []
        for _ in range(4000):
            ids = rng.choices(range(300), k=300)
            boot.append(100 * (1 - math.sqrt(sum(b[i]['mse'] for i in ids)
                                             / sum(a[i]['mse'] for i in ids))))
        boot.sort()
        detail['independent_ci95_percent'] = [boot[99], boot[3899]]
        detail['bootstrap_rng'] = 'Python random.Random; paired geometry resampling'
    comparisons.append(detail)

same_hover = []
for rcs in rcs_values:
    common = [(index[t, rcs, methods[2]], index[t, rcs, methods[3]]) for t in range(300)]
    common = [(a, b) for a, b in common if all(a['hover_' + axis] == b['hover_' + axis]
                                             for axis in 'xyz')]
    same_hover.append(dict(rcs_m2=rcs, cases=len(common),
                           position_rmse_m=[math.sqrt(statistics.mean(pair[k]['mse'] for pair in common))
                                            for k in (0, 1)] if common else None))

audit = dict(passed=True, source_release=release, manifest_id=manifest['id'], rows=3600,
             source_files_checked=len(manifest['source']), maximum_rmse_difference_m=max_delta,
             all_failures_retained=True, groups=groups, comparisons=comparisons,
             posthoc_same_hover_selected_methods=same_hover,
             evidence_sha256={p.name: hashlib.sha256(p.read_bytes()).hexdigest()
                              for p in root.iterdir() if p.is_file() and p.name != 'independent_audit.json'})
(root / 'independent_audit.json').write_bytes((json.dumps(audit, indent=2) + '\n').encode('utf-8'))
print(json.dumps(audit, indent=2))
