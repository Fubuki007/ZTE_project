"""Small regression checks for matching, signed errors and complete-data validation."""
import json
from pathlib import Path
import tempfile
import unittest

import numpy as np

from collect_rmse import METHODS, load_samples, match_errors, summarize


class MetricsTests(unittest.TestCase):
    def setUp(self):
        self.truth = np.array([[200., 15., 60., 28.], [210., -5., 16., 11.]])

    def test_joint_assignment_preserves_identity_when_order_reversed(self):
        estimates = self.truth + np.array([[.2, -.3, .1, .1], [-.4, .5, -.1, -.2]])
        expected = estimates-self.truth
        actual, order = match_errors(estimates[::-1], self.truth)
        np.testing.assert_array_equal(order, [1, 0])
        np.testing.assert_allclose(actual, expected)

    def test_matching_not_reoptimized_for_range_and_speed(self):
        # Swapped ranges/speeds with unchanged angles must count as large errors.
        estimates = self.truth.copy()
        estimates[:, :2] = estimates[::-1, :2]
        errors, order = match_errors(estimates, self.truth)
        np.testing.assert_array_equal(order, [0, 1])
        np.testing.assert_allclose(errors[:, 0], [10, -10])
        np.testing.assert_allclose(errors[:, 1], [-20, 20])

    def test_velocity_keeps_sign_and_angle_wrap(self):
        estimates = self.truth.copy()
        estimates[1, 1] = 5.
        estimates[:, 3] += 360.
        errors, _ = match_errors(estimates, self.truth)
        self.assertEqual(errors[1, 1], 10.)
        np.testing.assert_allclose(errors[:, 3], 0.)

    def test_rmse_averages_squares_not_signed_errors(self):
        errors = np.zeros((2, 4, 2, 4))
        errors[0, :, :, 0] = 1.
        errors[1, :, :, 0] = -1.
        indices = np.array([[0, 0], [0, 1], [1, 1]])
        rmse, ci, details = summarize(errors, 0, indices, .1)
        np.testing.assert_allclose(rmse, 1.)
        np.testing.assert_allclose(ci, 1.)
        self.assertEqual(details[0]['mean_error'], 0.)
        self.assertEqual(details[0]['outlier_rate'], 1.)

    def test_mc_and_targets_averaged_with_equal_weight(self):
        errors = np.zeros((2, 4, 2, 4))
        errors[0, :, :, 1] = [1., 3.]
        errors[1, :, :, 1] = [2., 4.]
        rmse, _, details = summarize(errors, 1, np.array([[0, 1]]), 10.)
        np.testing.assert_allclose(rmse, np.sqrt(7.5))
        self.assertAlmostEqual(details[0]['target_1_rmse'], np.sqrt(2.5))
        self.assertAlmostEqual(details[0]['target_2_rmse'], np.sqrt(12.5))

    def test_reject_nonfinite_estimates(self):
        estimates = self.truth.copy()
        estimates[0, 0] = np.nan
        with self.assertRaises(ValueError):
            match_errors(estimates, self.truth)

    def test_missing_and_incompatible_checkpoints_fail(self):
        manifest = dict(config=dict(truth=self.truth.tolist()), snr_db=[-30.], mc=2, id='test')
        record = dict(manifest_id='test', trial=0, snr_db=-30., methods=METHODS,
                      estimates=np.tile(self.truth, (4, 1, 1)).tolist(),
                      angular_errors_deg=np.zeros((4, 2, 2)).tolist(), seed=99)
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root/'samples').mkdir()
            path = root/'samples'/'snr_00_mc_0000.json'
            path.write_text(json.dumps(record))
            with self.assertRaisesRegex(ValueError, 'Incomplete'):
                load_samples(root, manifest)
            _, counts, audit, _, complete = load_samples(root, manifest, partial=True)
            self.assertEqual(counts, [1])
            self.assertFalse(complete)
            self.assertEqual(len(audit), 8)
            record['manifest_id'] = 'wrong'
            path.write_text(json.dumps(record))
            with self.assertRaisesRegex(ValueError, 'Incompatible'):
                load_samples(root, manifest, partial=True)


if __name__ == '__main__':
    unittest.main()
