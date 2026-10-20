"""Real local training smoke, exact resume, failure recovery and selection guards."""
from copy import deepcopy
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import numpy as np
import torch

from .generate_dataset import generate, load_context
from .protocol import load_protocol
from .repair import InfeasibleDesign
from .storage import read_json, atomic_json
from .train import (train, load_selected, read_checkpoint, weight_hash, choose_best,
                    settings_for, validation_sample, training_status, committed_events)
from .unfolded_design import UnfoldedDesigner


def state_at(path):
    return read_checkpoint(path, read_json(Path(path)/'manifest.json'))[0]


class TrainingTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.work = tempfile.TemporaryDirectory()
        cls.root = Path(cls.work.name)
        cls.dataset = cls.root/'data'
        cls.p = load_protocol(smoke=True)
        generate(cls.dataset, cls.p)
        cls.full = cls.root/'uninterrupted'
        cls.report = train(cls.dataset, cls.full, smoke=True)
        cls.state = state_at(cls.full)

    @classmethod
    def tearDownClass(cls):
        cls.work.cleanup()

    def test_actual_training_changes_parameters_and_covers_validation(self):
        self.assertTrue(self.report['complete'])
        self.assertEqual(self.report['training_updates'], 4)
        self.assertEqual(self.report['validation_samples'], 3)
        self.assertTrue(self.report['current_weights_changed'])
        self.assertEqual([v['epoch'] for v in self.state['validation_history']], [0, 1, 2])
        events = list(reversed(list(committed_events(self.full))))
        steps = [e for e in events if e['kind'] == 'train']
        self.assertEqual(len(steps), 4)
        self.assertTrue(all(e['sample_id'].startswith('train_') for e in steps))
        self.assertEqual([e['result']['straight_through'] for e in steps], [False, False, True, True])
        self.assertTrue(any(e['result']['unclipped_gradient_norm'] > 0 for e in steps))
        self.assertTrue(all(e['sample_id'].startswith('validation_') for e in events if e['kind'] == 'validation'))
        network, meta = load_selected(self.full, allow_smoke=True)
        self.assertEqual(weight_hash(network.state_dict()), meta['weight_sha256'])
        self.assertEqual(meta['selected']['samples'], 1)
        self.assertTrue(all(v['failures'] == 0 for v in meta['validation_history']))
        self.assertTrue(training_status(self.full)['complete'])

    def assert_same_result(self, output):
        state = state_at(output)
        self.assertEqual(weight_hash(state['weights']), weight_hash(self.state['weights']))
        self.assertEqual(state['best']['weight_sha256'], self.state['best']['weight_sha256'])
        self.assertEqual(state['validation_history'], self.state['validation_history'])
        self.assertEqual(state['updates'], self.state['updates'])
        self.assertEqual(state['optimizer']['param_groups'], self.state['optimizer']['param_groups'])
        for key, values in self.state['optimizer']['state'].items():
            for name, value in values.items():
                torch.testing.assert_close(state['optimizer']['state'][key][name], value, rtol=0, atol=0)
        torch.testing.assert_close(state['rng']['torch'], self.state['rng']['torch'], rtol=0, atol=0)
        self.assertEqual(state['rng']['python'], self.state['rng']['python'])
        self.assertEqual(state['rng']['numpy'], self.state['rng']['numpy'])

    def test_resume_exactly_matches_uninterrupted_training(self):
        output = self.root/'resumed'
        paused = train(self.dataset, output, smoke=True, limit=2)
        self.assertFalse(paused['complete'])
        self.assertEqual(paused['training_updates'], 1)
        self.assertEqual(read_json(output/'state.json')['state'], 'PAUSED_LIMIT')
        with self.assertRaisesRegex(ValueError, 'incomplete'):
            load_selected(output, allow_smoke=True)
        done = train(self.dataset, output, smoke=True)
        self.assertTrue(done['complete'])
        self.assert_same_result(output)
        with patch('RIS_stage3_ai.train.training_step', side_effect=AssertionError('Must not retrain')):
            self.assertTrue(train(self.dataset, output, smoke=True)['complete'])

    def test_failed_commit_replays_step_without_advancing_saved_optimizer(self):
        output = self.root/'commit_failure'
        def fail_pointer(path, value):
            if Path(path).name == 'latest.json' and value['revision'] == 2:
                raise OSError('injected checkpoint pointer failure')
            return atomic_json(path, value)
        with patch('RIS_stage3_ai.train.atomic_json', side_effect=fail_pointer):
            with self.assertRaisesRegex(OSError, 'injected checkpoint'):
                train(self.dataset, output, smoke=True)
        self.assertEqual(state_at(output)['updates'], 0)
        self.assertEqual(read_json(output/'state.json')['state'], 'FAILED')
        self.assertEqual(len(list((output/'failures').glob('*.json'))), 1)
        self.assertTrue(train(self.dataset, output, smoke=True)['complete'])
        self.assert_same_result(output)
        events = list(committed_events(output))
        self.assertEqual(sum(e['kind'] == 'train' for e in events), 4)
        self.assertEqual(sum(e['kind'] == 'validation' for e in events), 3)
        self.assertGreater(len(list((output/'events').glob('*.json'))), len(events))

    def test_checkpoint_corruption_and_identity_change_are_rejected(self):
        output = self.root/'corruption'
        train(self.dataset, output, smoke=True, limit=1)
        pointer = read_json(output/'latest.json')
        path = output/pointer['checkpoint']
        with path.open('ab') as stream:
            stream.write(b'corrupt')
        with self.assertRaisesRegex(ValueError, 'checksum'):
            state_at(output)
        changed = read_json(Path(__file__).with_name('training_v1.json'))
        changed['learning_rate'] = .02
        changed_path = self.root/'changed_settings.json'
        atomic_json(changed_path, changed)
        with self.assertRaisesRegex(ValueError, 'identity changed'):
            train(self.dataset, self.full, smoke=True, settings_path=changed_path)

    def test_smoke_and_incomplete_data_cannot_be_formal_models(self):
        with self.assertRaisesRegex(ValueError, 'Smoke model'):
            load_selected(self.full)
        with patch('RIS_stage3_ai.train.file_hash', return_value='changed'):
            with self.assertRaisesRegex(ValueError, 'Inference physics/source'):
                load_selected(self.full, allow_smoke=True)
        with self.assertRaisesRegex(ValueError, 'match dataset profile'):
            train(self.dataset, self.root/'wrong_profile')
        partial = self.root/'partial_data'
        generate(partial, self.p, limit=1)
        with self.assertRaisesRegex(ValueError, 'complete, audited'):
            train(partial, self.root/'wrong_data', smoke=True)
        cfg = settings_for(load_protocol())
        self.assertEqual((cfg['epochs'], cfg['continuous_epochs'], cfg['network']['layers']), (20, 5, 6))

    def test_selection_can_keep_initial_model_and_penalizes_failed_samples(self):
        weights = {'x': torch.tensor([1.], dtype=torch.float64)}
        initial = dict(epoch=0, samples=3, failures=0, fallbacks=0, mean_repaired_min_illumination=1.)
        best = choose_best(None, initial, weights)
        for summary in [dict(initial, epoch=1, mean_repaired_min_illumination=.9),
                        dict(initial, epoch=2), dict(initial, epoch=3, failures=1, mean_repaired_min_illumination=10.)]:
            best = choose_best(best, summary, {'x': torch.tensor([2.])})
        self.assertEqual(best['summary']['epoch'], 0)
        better = choose_best(best, dict(initial, epoch=4, mean_repaired_min_illumination=1.1), weights)
        self.assertEqual(better['summary']['epoch'], 4)

    def test_validation_retains_physical_failure_and_propagates_infrastructure_failure(self):
        manifest = read_json(self.dataset/'manifest.json')
        case = next(c for c in manifest['identity']['cases'] if c['split'] == 'validation')
        ctx = load_context(self.dataset, manifest, case)
        network = UnfoldedDesigner()
        cfg = settings_for(self.p)
        with patch('RIS_stage3_ai.train.repair_design', side_effect=InfeasibleDesign('physical failure')):
            result = validation_sample(ctx, network, cfg)
        self.assertFalse(result['feasible'])
        self.assertEqual(result['score'], 0.)
        self.assertIn('physical failure', result['error'])
        with patch('RIS_stage3_ai.train.network_candidate', side_effect=OSError('device access failure')):
            with self.assertRaises(OSError):
                validation_sample(ctx, network, cfg)


if __name__ == '__main__':
    unittest.main()
