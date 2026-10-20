"""Audit completed SMOKE pipeline, deadline failure statistics and no-recompute resume."""
import argparse
from pathlib import Path
import shutil
import tempfile
from unittest.mock import patch
import numpy as np
from .aggregate import sample_squared_errors
from .aggregate_budget import aggregate
from .generate_dataset import sealed
from .run_budget import run, scan, progress
from .storage import atomic_json, read_json, file_hash, now


def audit(run_dir, output, device='cpu'):
    run_dir = Path(run_dir).resolve()
    source = run_dir/'budget'
    manifest = read_json(source/'manifest.json')
    if manifest['identity']['protocol']['profile'] != 'smoke':
        raise ValueError('This diagnostic is only for smoke outputs')
    records = scan(source, manifest)
    before = {str(p): file_hash(p) for p in (source/'samples').glob('*/*.json')}
    with patch('RIS_stage3_ai.run_budget.timed_design', side_effect=AssertionError('Completed sample recomputed')):
        state = run(run_dir/'comparison', run_dir/'training', source, smoke=True, device=device)
    if not state['complete'] or any(file_hash(p) != h for p,h in before.items()):
        raise AssertionError('Resume changed sample data')
    with tempfile.TemporaryDirectory() as temp:
        temp = Path(temp)
        report = aggregate(source, temp/'metrics', plots=False)
        for row in report['rows']:
            group = [r for r in records.values() if r['case']['split'] == row['split']
                and r['case']['snr_db'] == row['snr_db'] and r['method'] == row['method']
                and r['budget_seconds'] == row['budget_seconds'] and r['status'] == 'SUCCESS']
            if group:
                k = ('angle_deg','range_m','velocity_mps').index(row['metric'])
                expected = np.sqrt(np.mean([sample_squared_errors(r['errors'])[k] for r in group]))
                np.testing.assert_allclose(row['conditional_success_rmse'], expected)
            if row['independent_units'] == 1:
                assert row['ci95_low'] is None
        copied = temp/'injected_failure'
        shutil.copytree(source, copied)
        path = next((copied/'samples').glob('*/*.json'))
        record = read_json(path)
        record.pop('sha256')
        record.update(status='DEADLINE_MISS', error='injected deadline failure')
        atomic_json(path, sealed(record))
        failed = aggregate(copied, temp/'failure_metrics', plots=False)
        affected = [r for r in failed['rows'] if r['split'] == record['case']['split']
            and r['method'] == record['method'] and r['budget_seconds'] == record['budget_seconds']]
        assert len(affected) == 3 and all(r['deadline_misses'] == 1 and r['rmse'] is None for r in affected)
        record['noise_variance'] *= 2
        atomic_json(path, sealed(record))
        try:
            scan(copied, manifest)
        except ValueError as exc:
            assert 'pairing' in str(exc)
        else:
            raise AssertionError('Corrupt pairing accepted')
    evidence = dict(scope='SMOKE_NOT_FORMAL_RESULTS', date=now(), passed=True,
        pipeline_manifest=read_json(run_dir/'pipeline_manifest.json'),
        pipeline_state=read_json(run_dir/'pipeline_state.json'), budget_progress=progress(manifest, records),
        checks=['completed sample resume does not recompute or overwrite',
                'RMSE matches independent squared-error average', 'single unit has no CI',
                'deadline failure suppresses headline RMSE', 'corrupt noise pairing rejected'],
        sample_hashes=before)
    atomic_json(output, evidence)
    return dict(passed=True, budget_progress=state)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--run-dir', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--device', default='cpu')
    print(audit(**vars(parser.parse_args())))


if __name__ == '__main__':
    main()
