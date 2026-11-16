"""Audit fetched UAV diagnosis CSV/JSON and frozen Git sources; no dependencies."""
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
manifest = json.loads((root / 'manifest.json').read_text())
summary = json.loads((root / 'summary.json').read_text())
verification = json.loads((root / 'verification.json').read_text())
completion = json.loads((root / 'completion_status.json').read_text())
assert manifest['total_cases'] == summary['complete_cases'] == verification['cases'] == 900
assert verification['passed'] and completion['state'] == 'COMPLETE' and completion['checkpoints'] == 900
assert len(completion['workers']) == 8 and all(w['state'] == 'COMPLETE' for w in completion['workers'])
assert manifest['id'] == summary['manifest_id'] == verification['manifest_id']
prefix = 'stage3-RIS与毫米波通感一体化联合优化算法方案/code/'
for source in manifest['source']:
    raw = subprocess.check_output(['git', 'show', root.name + ':' + prefix + source['file']])
    assert hashlib.sha256(raw).hexdigest() == source['sha256'], source['file']

def close(a, b):
    assert math.isclose(a, b, rel_tol=1e-8, abs_tol=1e-7), (a, b)

def flag(s):
    assert s.lower() in ('0', '1', 'true', 'false')
    return s.lower() in ('1', 'true')

with (root / 'case_metrics.csv').open(newline='', encoding='utf-8-sig') as stream:
    rows = list(csv.DictReader(stream))
assert len(rows) == 13500
methods = summary['methods']
assert len(methods) == 15
index = {}
for row in rows:
    t, rcs, method = int(row['trial']), float(row['rcs_m2']), row['method']
    key = t, rcs, method
    assert key not in index and 0 <= t < 300 and rcs in [1, 10, 100] and method in methods
    index[key] = row
    assert int(row['seed']) == 20261116 + 10000 * t
    errors = [float(row['target1_error_m']), float(row['target2_error_m'])]
    assert all(math.isfinite(e) and e >= 0 for e in errors)
    row['mse'] = sum(e * e for e in errors) / 2
    close(math.sqrt(row['mse']), float(row['position_rmse_m']))
    for field in ['locked', 'feasible', 'failure', 'diagnostic_only']:
        row[field] = flag(row[field])
    assert row['failure'] == (not row['locked'] or not row['feasible'] or max(errors) > 5)
    assert row['diagnostic_only'] == (6 <= methods.index(method) <= 10)

groups = []
max_delta = 0
for ri, rcs in enumerate([1, 10, 100]):
    for mi, method in enumerate(methods):
        group = [index[t, rcs, method] for t in range(300)]
        rmse = math.sqrt(statistics.mean(r['mse'] for r in group))
        close(rmse, summary['position_rmse_m'][ri][mi])
        max_delta = max(max_delta, abs(rmse - summary['position_rmse_m'][ri][mi]))
        counts = {}
        for field, name in [('locked', 'capture'), ('feasible', 'feasible'), ('failure', 'failure')]:
            counts[name + '_count'] = sum(r[field] for r in group)
            close(counts[name + '_count'] / 300, summary[name + '_rate'][ri][mi])
        groups.append(dict(rcs_m2=rcs, method=method, position_rmse_m=rmse,
                           median_case_rmse_m=statistics.median(float(r['position_rmse_m']) for r in group),
                           **counts))

parent_release = pathlib.PurePosixPath(manifest['parent']).parts
parent_release = parent_release[parent_release.index('releases') + 1]
parent_csv = root.parents[1] / 'uav-foundation' / parent_release / 'case_metrics.csv'
with parent_csv.open(newline='', encoding='utf-8-sig') as stream:
    for old in csv.DictReader(stream):
        if old['method'] not in ['Selected_NoRIS', 'Selected_RIS']:
            continue
        method = methods[0 if old['method'] == 'Selected_NoRIS' else 1]
        replay = index[int(old['trial']), float(old['rcs_m2']), method]
        for field in ['target1_error_m', 'target2_error_m']:
            close(float(old[field]), float(replay[field]))
        for field in ['locked', 'feasible', 'failure']:
            assert flag(old[field]) == replay[field]

pairs = dict(position_control=(1, 2), normalization=(2, 3), DD_fit=(2, 4), BIC_fit=(2, 5),
             frozenW_full=(0, 6), frozenW_DD=(0, 7), RIS_remove_noise=(2, 9),
             NoRIS_remove_noise=(0, 8), noiseless_DD=(9, 10), receive_beam=(0, 11),
             RIS_after_receive_beam=(11, 12), BIC_after_receive_beam=(12, 14),
             net_RIS_BIC=(11, 14), net_RIS_DD=(11, 13))
for comp in summary['comparisons']:
    ai, bi = pairs[comp['name']]
    a = [index[t, comp['rcs_m2'], methods[ai]] for t in range(300)]
    b = [index[t, comp['rcs_m2'], methods[bi]] for t in range(300)]
    close(100 * (1 - math.sqrt(statistics.mean(r['mse'] for r in b)
                               / statistics.mean(r['mse'] for r in a))), comp['rmse_reduction_percent'])
    close(100 * statistics.mean(int(x['failure']) - int(y['failure']) for x, y in zip(a, b)),
          comp['failure_reduction_pp'])
primary = {c['name']: c for c in summary['primary']}
for name, metric, rcs, comparison in [('receive_beam_failure_RCS10', 'failure_reduction_pp', 10, 'receive_beam'),
                                    ('BIC_RMSE_RCS100', 'rmse_reduction_percent', 100, 'BIC_fit')]:
    point = next(c for c in summary['comparisons'] if c['name'] == comparison and c['rcs_m2'] == rcs)
    close(primary[name]['estimate'], point[metric])

rng = random.Random(manifest['bootstrap_seed'])
receive_delta = [int(index[t, 10, methods[0]]['failure']) - int(index[t, 10, methods[11]]['failure'])
                 for t in range(300)]
full_mse = [index[t, 100, methods[2]]['mse'] for t in range(300)]
bic_mse = [index[t, 100, methods[5]]['mse'] for t in range(300)]
boot_receive, boot_bic = [], []
for _ in range(4000):
    sample = rng.choices(range(300), k=300)
    boot_receive.append(100 * sum(receive_delta[t] for t in sample) / 300)
    boot_bic.append(100 * (1 - math.sqrt(sum(bic_mse[t] for t in sample) / sum(full_mse[t] for t in sample))))
for name, boot in [('receive_beam_failure_RCS10', boot_receive), ('BIC_RMSE_RCS100', boot_bic)]:
    boot.sort()
    primary[name]['independent_python_ci975'] = [boot[49], boot[3949]]

audit = dict(passed=True, source_release=root.name, manifest_id=manifest['id'], rows=len(rows),
             source_files_checked=len(manifest['source']), maximum_rmse_difference_m=max_delta,
             groups=groups, primary=summary['primary'], all_failures_retained=True,
             evidence_sha256={p.name: hashlib.sha256(p.read_bytes()).hexdigest()
                              for p in root.iterdir() if p.is_file() and p.name != 'independent_audit.json'})
(root / 'independent_audit.json').write_bytes((json.dumps(audit, indent=2) + '\n').encode('utf-8'))
print(json.dumps(audit, indent=2))
