"""Six-method end-to-end smoke and independent metric/bootstrap/failure checks."""
from pathlib import Path
import shutil
import tempfile
import unittest
from unittest.mock import patch

import numpy as np

from RIS_stage3.collect_rmse import match_errors
from RIS_stage3.streaming import coarse_from_records
from .aggregate import aggregate, bootstrap_squared, sample_squared_errors
from .generate_dataset import generate, sealed
from .protocol import load_protocol, EXPECTED_METHODS
from .run_comparison import compare, scan_results, result_path, validate_comparison
from .storage import read_json, atomic_json, file_hash
from .train import train


class ComparisonTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.work = tempfile.TemporaryDirectory()
        cls.root = Path(cls.work.name)
        cls.data, cls.training, cls.output = [cls.root/name for name in ('data', 'training', 'comparison')]
        generate(cls.data, load_protocol(smoke=True))
        train(cls.data, cls.training, smoke=True)
        def guarded_coarse(cfg, records):
            if not np.isnan(cfg.truth).all():
                raise AssertionError('Truth leaked into coarse estimator')
            return coarse_from_records(cfg, records)
        with patch('RIS_stage3_ai.run_comparison.coarse_from_records', side_effect=guarded_coarse):
            cls.partial = compare(cls.data, cls.training, cls.output, smoke=True, limit=2)
            saved = {str(path): file_hash(path) for path in (cls.output/'samples').glob('*/*.json')}
            try:
                aggregate(cls.output, cls.root/'invalid_metrics', plots=False)
            except ValueError:
                pass
            else:
                raise AssertionError('Incomplete comparison was accepted')
            cls.done = compare(cls.data, cls.training, cls.output, smoke=True)
        if any(file_hash(path) != sha for path, sha in saved.items()):
            raise AssertionError('Resume rewrote completed method samples')
        cls.manifest = validate_comparison(read_json(cls.output/'manifest.json'))
        cls.records = scan_results(cls.output, cls.manifest)

    @classmethod
    def tearDownClass(cls):
        cls.work.cleanup()

    def test_six_method_pipeline_pairing_and_resume(self):
        self.assertFalse(self.partial['complete'])
        self.assertEqual(self.partial['terminal_methods'], 2)
        self.assertTrue(self.done['complete'])
        self.assertTrue(self.done['all_methods_successful'])
        self.assertEqual(len(self.records), 12)
        self.assertFalse(list((self.output/'work').iterdir()))
        for case in self.manifest['identity']['cases']:
            rows = [self.records[(case['sample_id'], m)] for m in EXPECTED_METHODS]
            self.assertEqual(len({r['noise_variance'] for r in rows}), 1)
            self.assertEqual(len({r['coarse_sha256'] for r in rows}), 1)
            self.assertEqual(len({r['case']['fine_seed'] for r in rows}), 1)
            self.assertTrue(all(r['estimator_truth'] == 'unavailable_NaN' for r in rows))
            self.assertTrue(all(r['design']['final']['feasible'] for r in rows))
        with patch('RIS_stage3_ai.run_comparison.run_method', side_effect=AssertionError('No rerun')):
            self.assertTrue(compare(self.data, self.training, self.output, smoke=True)['complete'])

    def test_metrics_match_direct_errors_and_single_scene_has_no_ci(self):
        report = aggregate(self.output, self.root/'metrics', plots=False)
        self.assertEqual(len(report['rows']), 36)
        for row in report['rows']:
            case = next(c for c in self.manifest['identity']['cases'] if c['split'] == row['split'])
            r = self.records[(case['sample_id'], row['method'])]
            errors = np.array(r['errors'])
            direct = {'angle_deg': np.sqrt(np.mean(errors[:, 2:]**2)),
                      'range_m': np.sqrt(np.mean(errors[:, 0]**2)),
                      'velocity_mps': np.sqrt(np.mean(errors[:, 1]**2))}
            self.assertAlmostEqual(row['rmse'], direct[row['metric']], places=12)
            self.assertIsNone(row['ci95_low'])
            self.assertIsNone(row['paired_difference_ci95_high'])

    def test_common_assignment_and_wrapped_azimuth(self):
        truth = np.array([[100., 1., 30., 179.], [200., 2., 70., 30.]])
        estimate = np.array([[203., -2., 71., 31.], [102., 4., 32., -179.]])
        error, order = match_errors(estimate, truth)
        np.testing.assert_array_equal(order, [1, 0])
        np.testing.assert_allclose(error, [[2, 3, 2, 2], [3, -4, 1, 1]])
        np.testing.assert_allclose(sample_squared_errors(error), [2.5, 6.5, 12.5])

    def test_cluster_bootstrap_keeps_scenes_and_methods_paired(self):
        a = np.array([1., 9., 25., 49.])
        squared = np.stack([a, 4*a], axis=1)[:, :, None]
        actual, count = bootstrap_squared(squared, ['a', 'a', 'b', 'b'], 2000, np.random.default_rng(77))
        choices = np.random.default_rng(77).integers(0, 2, size=(2000, 2))
        expected = np.sqrt(np.array([5., 37.])[choices].mean(axis=1))
        self.assertEqual(count, 2)
        np.testing.assert_array_equal(actual[:, 0, 0], expected)
        np.testing.assert_allclose(actual[:, 1, 0], 2*actual[:, 0, 0])
        with self.assertRaises(ValueError):
            bootstrap_squared(squared, ['a', 'a', 'a', 'b'], 20, np.random.default_rng(1))

    def test_failed_algorithm_is_retained_and_not_given_finite_headline_rmse(self):
        copy = self.root/'with_failure'
        shutil.copytree(self.output, copy)
        case = self.manifest['identity']['cases'][0]
        path = result_path(copy, case, 'learned_physics')
        record = read_json(path)
        record.pop('sha256')
        record.update(status='ALGORITHM_FAILURE', error='injected physical failure')
        atomic_json(path, sealed(record))
        report = aggregate(copy, self.root/'failure_metrics', plots=False)
        rows = [r for r in report['rows'] if r['split'] == case['split'] and r['method'] == 'learned_physics']
        self.assertTrue(report['progress']['complete'])
        self.assertFalse(report['progress']['all_methods_successful'])
        self.assertTrue(all(r['algorithm_failures'] == 1 and r['rmse'] is None for r in rows))

    def test_corrupt_noise_pairing_rejected(self):
        copy = self.root/'bad_pairing'
        shutil.copytree(self.output, copy)
        case = self.manifest['identity']['cases'][0]
        path = result_path(copy, case, 'learned_physics')
        record = read_json(path)
        record.pop('sha256')
        record['noise_variance'] *= 2
        atomic_json(path, sealed(record))
        with self.assertRaisesRegex(ValueError, 'pairing checkpoint'):
            scan_results(copy, self.manifest)


if __name__ == '__main__':
    unittest.main()
