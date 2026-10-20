"""Deadline exclusion, paired full-chain smoke, resume and runner failure checks."""
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch
import numpy as np
from .budget_design import timed_design, NoTimelyDesign
from .test_design import fixture
from .physics_numpy import geometric_initialization
from .storage import read_json, file_hash
from .server_pipeline import run_pipeline, verify_stage


class BudgetTests(unittest.TestCase):
    def test_late_better_solution_never_scores(self):
        _, _, _, ctx = fixture()
        w0, p0 = geometric_initialization(ctx)
        audits = [dict(feasible=True, min_illumination=1.), dict(feasible=True, min_illumination=100.)]
        with patch('RIS_stage3_ai.budget_design.audit_design', side_effect=audits), \
             patch('RIS_stage3_ai.budget_design.optimize', return_value=(w0*2, p0, {})):
            _, _, _, info = timed_design(lambda: ctx, 'traditional_anytime', None, 1.,
                                        clock=iter([0., .1, .2, 1.2, 1.3]).__next__)
        self.assertEqual(info['final']['min_illumination'], 1.)
        self.assertAlmostEqual(info['budget_timing']['atomic_overrun_seconds'], .3)
        self.assertFalse(info['budget_timing']['events'][-1]['timely'])

    def test_initialization_time_is_charged_and_no_timely_design_is_failure(self):
        _, _, _, ctx = fixture()
        with self.assertRaises(NoTimelyDesign) as caught:
            timed_design(lambda: ctx, 'traditional_anytime', None, 1.,
                         clock=iter([0., 2., 2.1, 2.2]).__next__)
        self.assertIsNone(caught.exception.timing['candidate_ready_seconds'])

    def test_pipeline_failure_is_not_completion(self):
        with tempfile.TemporaryDirectory() as temp:
            output = Path(temp)/'run'
            with patch('RIS_stage3_ai.server_pipeline.commands', return_value={
                    'data':[sys.executable,'-c','raise SystemExit(7)']}):
                with self.assertRaisesRegex(RuntimeError, 'exit=7'):
                    run_pipeline(output, smoke=True, device='cpu')
            state = read_json(output/'pipeline_state.json')
            self.assertEqual(state['state'], 'FAILED')
            self.assertEqual(state['completed_stages'], [])
            self.assertTrue(list((output/'failures').glob('*.json')))

    def test_zero_exit_with_incomplete_data_is_rejected(self):
        with tempfile.TemporaryDirectory() as temp:
            output = Path(temp)
            from .generate_dataset import generate
            from .protocol import load_protocol
            generate(output/'data', load_protocol(smoke=True), prepare_only=True)
            with self.assertRaisesRegex(RuntimeError, 'without complete'):
                verify_stage(output, 'data')


if __name__ == '__main__':
    unittest.main()
