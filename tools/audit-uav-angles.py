"""Independently recompute the full angular replay metrics without MATLAB."""
import csv
import hashlib
import json
import math
from pathlib import Path
import random
import statistics
import subprocess
import sys

root = Path(sys.argv[1]).resolve()
manifest = json.loads((root / 'manifest.json').read_text(encoding='utf-8-sig'))
summary = json.loads((root / 'summary.json').read_text(encoding='utf-8-sig'))
verification = json.loads((root / 'verification.json').read_text(encoding='utf-8-sig'))
assert manifest['profile'] == 'full' and manifest['total_cases'] == verification['cases'] == 900
assert verification['passed'] and summary['manifest_id'] == verification['manifest_id'] == manifest['id']
methods = ['legacy', 'signed_null', 'no_null', 'matched_array']
assert manifest['methods'] == summary['methods'] == methods
code = 'stage3-RIS与毫米波通感一体化联合优化算法方案/code/'
for source in manifest['source']:
    blob = subprocess.check_output(['git', 'show', root.name + ':' + code + source['file']])
    assert hashlib.sha256(blob).hexdigest() == source['sha256'], source['file']
with (root / 'case_metrics.csv').open(newline='', encoding='utf-8-sig') as stream:
    rows = list(csv.DictReader(stream))
assert len(rows) == 3600
index = {(int(r['trial']), int(r['rcs_m2']), r['method']): r for r in rows}
assert len(index) == len(rows)


def flag(value):
    assert value in ['0', '1']
    return value == '1'


def close(a, b):
    assert math.isclose(a, b, rel_tol=1e-9, abs_tol=1e-8), (a, b)


for row in rows:
    assert int(row['seed']) == 20261116 + 10000 * int(row['trial'])
    errors = [float(row['target1_error_m']), float(row['target2_error_m'])]
    assert all(math.isfinite(e) and e >= 0 for e in errors)
    row['mse'] = statistics.mean(e * e for e in errors)
    close(math.sqrt(row['mse']), float(row['position_rmse_m']))
    for key in ['locked', 'feasible', 'failure', 'outside_local_box', 'polar_boundary']:
        row[key] = flag(row[key])
    assert row['failure'] == (not row['locked'] or not row['feasible'] or max(errors) > 5)
    assert float(row['legacy_coarse_replay_delta']) < 1e-7
    assert float(row['legacy_fine_replay_delta_m']) < 1e-5

groups = []
for ri, rcs in enumerate([1, 10, 100]):
    for mi, method in enumerate(methods):
        group = [index[t, rcs, method] for t in range(300)]
        rmse = math.sqrt(statistics.mean(r['mse'] for r in group))
        close(rmse, summary['position_rmse_m'][ri][mi])
        for key, name in [('failure', 'failure_rate'), ('locked', 'capture_rate'),
                          ('feasible', 'feasible_rate'), ('outside_local_box', 'outside_local_box_rate'),
                          ('polar_boundary', 'polar_boundary_rate')]:
            close(statistics.mean(r[key] for r in group), summary[name][ri][mi])
        for pi, field in enumerate(['coarse_range_rmse_m', 'coarse_velocity_rmse_mps',
                                    'coarse_polar_rmse_deg', 'coarse_azimuth_rmse_deg']):
            close(math.sqrt(statistics.mean(float(r[field]) ** 2 for r in group)),
                  summary['coarse_parameter_RMSE'][ri][mi][pi])
        groups.append(dict(rcs_m2=rcs, method=method, position_rmse_m=rmse,
                           failure_count=sum(r['failure'] for r in group)))
    for t in range(300):
        group = [index[t, rcs, method] for method in methods]
        for field in ['locked', 'input_snr_db', 'coarse_range_rmse_m', 'coarse_velocity_rmse_mps']:
            assert len({r[field] for r in group}) == 1, (t, rcs, field)

parent_parts = Path(manifest['parent']).parts
parent_sha = parent_parts[parent_parts.index('releases') + 1]
assert len(parent_sha) == 40
parent_csv = root.parents[1] / 'uav-diagnosis' / parent_sha / 'case_metrics.csv'
with parent_csv.open(newline='', encoding='utf-8-sig') as stream:
    for old in csv.DictReader(stream):
        if old['method'] != 'RxBeam_NoRIS':
            continue
        replay = index[int(old['trial']), int(old['rcs_m2']), 'legacy']
        for field in ['target1_error_m', 'target2_error_m']:
            assert abs(float(old[field]) - float(replay[field])) < 1e-5
        for field in ['locked', 'feasible', 'failure']:
            assert flag(old[field]) == replay[field]

for comp in summary['comparisons']:
    a = [index[t, comp['rcs_m2'], 'legacy'] for t in range(300)]
    b = [index[t, comp['rcs_m2'], comp['method']] for t in range(300)]
    close(100 * (1 - math.sqrt(statistics.mean(r['mse'] for r in b) /
                               statistics.mean(r['mse'] for r in a))), comp['rmse_reduction_percent'])
    close(100 * statistics.mean(int(x['failure']) - int(y['failure']) for x, y in zip(a, b)),
          comp['failure_reduction_pp'])
rng = random.Random(manifest['bootstrap_seed'])
delta = [int(index[t, 10, 'legacy']['failure']) - int(index[t, 10, 'matched_array']['failure'])
         for t in range(300)]
bootstrap = sorted(100 * statistics.mean(delta[t] for t in rng.choices(range(300), k=300))
                   for _ in range(manifest['bootstrap_repeats']))
primary = dict(summary['primary'], independent_python_ci95_pp=[bootstrap[99], bootstrap[3899]])
audit = dict(passed=True, source_release=root.name, manifest_id=manifest['id'], rows=len(rows),
             source_files_checked=len(manifest['source']), groups=groups, primary=primary,
             all_failures_retained=True, evidence_sha256={p.name: hashlib.sha256(p.read_bytes()).hexdigest()
             for p in root.iterdir() if p.is_file() and p.name != 'independent_audit.json'})
(root / 'independent_audit.json').write_bytes((json.dumps(audit, indent=2) + '\n').encode('utf-8'))
print(json.dumps(audit, indent=2))
