"""Local smoke for reproducibility, isolation, checkpoint integrity and real DD chain."""
from copy import deepcopy
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import numpy as np

from RIS_stage3.stage3_model import Model
from RIS_stage3.streaming import simulate_block, coarse_from_records
from .generate_dataset import (generate, load_context, progress, read_sample,
                               validate_manifest, build_manifest)
from .protocol import load_protocol, validate_protocol, require_execution_host, model_config
from .scenes import build_scenes, build_cases, geometry_id, target_geometry_id
from .storage import read_json, atomic_json, file_hash, directory_lock


class DatasetTests(unittest.TestCase):
    def test_full_registry_and_scene_disjointness(self):
        p = load_protocol()
        scenes = build_scenes(p)
        self.assertEqual(scenes, build_scenes(p))
        cases = build_cases(p, scenes, ('train', 'validation', 'heldout', 'legacy'))
        self.assertEqual({s: sum(c['split'] == s for c in cases) for s in
                          ('train', 'validation', 'heldout', 'legacy')},
                         dict(train=384, validation=96, heldout=1056, legacy=1100))
        keys = [target_geometry_id(s['truth']) for s in scenes]
        self.assertEqual(len(set(keys)), len(keys))
        seeds = [c[k] for c in cases for k in ('coarse_seed', 'fine_seed')]
        self.assertEqual(len(set(seeds)), len(seeds))
        reversed_cases = build_cases(p, list(reversed(scenes)), ('train', 'validation', 'heldout', 'legacy'))
        self.assertEqual({c['sample_id']: c for c in cases}, {c['sample_id']: c for c in reversed_cases})
        s = scenes[0]
        self.assertEqual(geometry_id(s['truth'], s['user_angles']),
                         geometry_id(list(reversed(s['truth'])), s['user_angles']))

    def test_full_dimensions_and_host_guard(self):
        p = load_protocol()
        for key in ('ns', 'lc', 'lf', 'bits', 'rx_nx', 'refinement_iterations'):
            bad = deepcopy(p)
            bad['physical'][key] += 1
            with self.assertRaises(ValueError):
                validate_protocol(bad)
        with patch('RIS_stage3_ai.protocol.platform.system', return_value='Linux'), \
             patch('RIS_stage3_ai.protocol.socket.gethostname', return_value='laptop'):
            with self.assertRaises(RuntimeError):
                require_execution_host(p)
        with patch('RIS_stage3_ai.protocol.platform.system', return_value='Linux'), \
             patch('RIS_stage3_ai.protocol.socket.gethostname', return_value='jzm'):
            require_execution_host(p)
        smoke = load_protocol(smoke=True)
        self.assertEqual(smoke['physical']['ns'], 512)
        self.assertEqual(p['physical']['ns'], 12672)
        self.assertIn('SMOKE', smoke['status'])
        self.assertTrue(np.isnan(model_config(smoke).truth).all())

    def test_prepare_only_full_has_no_computation(self):
        with tempfile.TemporaryDirectory() as work, \
             patch('RIS_stage3_ai.generate_dataset.simulate_block', side_effect=AssertionError('No simulation')):
            state = generate(work, load_protocol(), prepare_only=True)
            self.assertEqual((state['completed'], state['expected'], state['complete']), (0, 480, False))

    def test_real_coarse_pipeline_resume_and_truth_free_context(self):
        p = load_protocol(smoke=True)
        with tempfile.TemporaryDirectory() as work:
            directory = Path(work)
            first = generate(directory, p, limit=1)
            self.assertEqual((first['completed'], first['expected'], first['complete']), (1, 3, False))
            self.assertEqual(read_json(directory/'state.json')['state'], 'PAUSED_LIMIT')
            manifest = validate_manifest(read_json(directory/'manifest.json'), current_sources=True)
            case = manifest['identity']['cases'][0]
            record, feature = read_sample(directory, manifest, case)
            saved = file_hash(directory/'samples'/f'{case["sample_id"]}.json')
            ctx = load_context(directory, manifest, case)
            self.assertEqual(ctx.ns, 512)
            self.assertNotIn('truth', feature)
            self.assertNotIn('truth', vars(ctx))
            # Regenerate the exact observed block and estimate with truth poisoned.
            scene = next(s for s in manifest['identity']['scenes'] if s['scene_id'] == case['scene_id'])
            cfg = model_config(p, truth=scene['truth'], user_angles=scene['user_angles'])
            cfg_est = model_config(p, user_angles=scene['user_angles'])
            model = Model(cfg_est)
            times = np.arange(cfg.lc)*cfg.symbol_time
            y = simulate_block(cfg, model.wzf, None, times, record['noise_variance'],
                               case['coarse_seed'], directory/'replay.npy', manifest['identity']['batch'])
            try:
                estimate = coarse_from_records(cfg_est, [dict(y=y, w=model.wzf, phase=None, times=times)])
                np.testing.assert_allclose(estimate, feature['coarse'], atol=1e-10, rtol=0)
            finally:
                y._mmap.close()
                del y
            with patch('RIS_stage3_ai.generate_dataset.simulate_block', wraps=simulate_block) as simulator:
                done = generate(directory, p)
                self.assertEqual(simulator.call_count, 2)
            self.assertTrue(done['complete'])
            self.assertEqual(saved, file_hash(directory/'samples'/f'{case["sample_id"]}.json'))
            with patch('RIS_stage3_ai.generate_dataset.simulate_block', side_effect=AssertionError('Must skip')):
                self.assertTrue(generate(directory, p)['complete'])
            self.assertFalse(list((directory/'work').iterdir()))

    def test_failure_is_saved_and_can_resume(self):
        p = load_protocol(smoke=True)
        with tempfile.TemporaryDirectory() as work:
            with patch('RIS_stage3_ai.generate_dataset.simulate_block', side_effect=OSError('injected disk failure')):
                with self.assertRaisesRegex(OSError, 'injected disk'):
                    generate(work, p, limit=1)
            directory = Path(work)
            self.assertEqual(read_json(directory/'state.json')['state'], 'FAILED')
            manifest = read_json(directory/'manifest.json')
            state = progress(directory, manifest)
            self.assertEqual((state['completed'], state['failure_attempts']), (0, 1))
            state = generate(work, p, limit=1)
            self.assertEqual((state['completed'], state['failure_attempts']), (1, 1))
            failure = read_json(next((directory/'failures').glob('*.json')))
            self.assertEqual(failure['error_type'], 'OSError')

    def test_lock_and_manifest_integrity(self):
        p = load_protocol(smoke=True)
        with tempfile.TemporaryDirectory() as work:
            with directory_lock(work):
                with self.assertRaises(RuntimeError):
                    with directory_lock(work):
                        pass
            generate(work, p, prepare_only=True)
            bad = deepcopy(p)
            bad['learning']['model_seed'] += 100
            with self.assertRaisesRegex(ValueError, 'Different protocol'):
                generate(work, bad, prepare_only=True)
            manifest = build_manifest(p)
            manifest['identity']['protocol']['learning']['train_scenes'] += 1
            with self.assertRaisesRegex(ValueError, 'digest'):
                validate_manifest(manifest)

    def test_orphan_and_corrupt_inputs_not_counted_as_success(self):
        p = load_protocol(smoke=True)
        with tempfile.TemporaryDirectory() as work:
            directory = Path(work)
            generate(work, p, prepare_only=True)
            manifest = read_json(directory/'manifest.json')
            case = manifest['identity']['cases'][0]
            feature_path = directory/'inputs'/f'{case["sample_id"]}.json'
            atomic_json(feature_path, dict(orphan=True))
            self.assertEqual(progress(work, manifest)['completed'], 0)
            generate(work, p, limit=1)
            feature = read_json(feature_path)
            feature['coarse'][0][0] += 1
            atomic_json(feature_path, feature)
            with self.assertRaisesRegex(ValueError, 'checksum'):
                progress(work, manifest)
            with self.assertRaises(ValueError):
                generate(work, p)

    def test_paired_awgn_is_independent_of_beam_and_ris(self):
        p = load_protocol(smoke=True)
        cfg = model_config(p, truth=p['legacy_test']['truth'])
        model = Model(cfg)
        times = np.arange(3)*cfg.symbol_time
        with tempfile.TemporaryDirectory() as work:
            noises = []
            for index, (w, phase) in enumerate([(model.wzf, None),
                    (model.wzf*.8, np.ones(cfg.ris_nx*cfg.ris_ny, complex))]):
                blocks = []
                for variance in (0., .123):
                    y = simulate_block(cfg, w, phase, times, variance, 54321,
                                       Path(work)/f'{index}_{variance}.npy', 128)
                    blocks.append(np.array(y))
                    y._mmap.close()
                    del y
                noises.append(blocks[1]-blocks[0])
            np.testing.assert_allclose(noises[0], noises[1], atol=5e-15, rtol=0)


if __name__ == '__main__':
    unittest.main()
