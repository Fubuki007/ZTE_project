"""Validate v1, preserve full dimensions and prohibit full execution off server."""
from copy import deepcopy
from dataclasses import asdict
import math
from pathlib import Path
import platform
import socket

from RIS_stage3.stage3_model import Config
from .storage import read_json

DEFAULT_PROTOCOL = Path(__file__).with_name('experiment_v1.json')
EXPECTED_METHODS = ['dd_joint', 'stage3_original', 'stage3_short',
                    'untrained_physics', 'learned_physics', 'stage3_extended']
SMOKE_OVERRIDES = dict(ns=512, lc=32, lf=32, rx_nx=4, rx_ny=4,
                       refinement_iterations=2)


def positive_int(value, name):
    if type(value) is not int or value < 1:
        raise ValueError(f'{name} must be a positive integer')


def validate_snrs(values):
    if not values or not all(isinstance(x, (int, float)) and math.isfinite(x) for x in values):
        raise ValueError('SNR grid must be finite and nonempty')
    if any(a >= b for a, b in zip(values, values[1:])):
        raise ValueError('SNR grid must increase strictly')


def validate_protocol(p):
    if p['schema_version'] != 1 or p['profile'] not in ('full', 'smoke'):
        raise ValueError('Unsupported protocol/profile')
    baseline = asdict(Config())
    expected = {key: baseline[key] for key in p['physical'] if key != 'dtype'}
    if p['profile'] == 'smoke':
        expected.update(SMOKE_OVERRIDES)
    if set(p['physical']) != set(asdict(Config())) - {
        'c', 'truth', 'user_angles', 'seed', 'ao_iterations', 'sca_iterations', 'phase_sweeps'} | {'dtype'}:
        raise ValueError('Missing or unexpected physical settings')
    for key, value in expected.items():
        actual = p['physical'][key]
        if key == 'ris_position':
            actual, value = tuple(actual), tuple(value)
        if actual != value:
            raise ValueError(f'{key} differs from the locked {p["profile"]} model')
    if p['physical']['dtype'] != 'float64/complex128':
        raise ValueError('Only float64/complex128 is supported')
    if p['profile'] == 'full' and p['run_location'] != 'server_only':
        raise ValueError('Full experiments must be server_only')
    learn, held, legacy = p['learning'], p['heldout_test'], p['legacy_test']
    for key in ('train_scenes', 'validation_scenes', 'layers', 'noise_replicates_per_scene_snr'):
        positive_int(learn[key], key)
    for value, name in [(held['scenes'], 'heldout scenes'), (held['mc_per_scene_snr'], 'heldout MC'),
                        (legacy['mc'], 'legacy MC'), (p['execution']['batch_subcarriers'], 'batch'),
                        (p['execution']['blas_threads_per_worker'], 'threads')]:
        positive_int(value, name)
    for group in (learn, held, legacy):
        validate_snrs(group['snr_db'])
    if held['expected_paired_cases'] != held['scenes']*len(held['snr_db'])*held['mc_per_scene_snr']:
        raise ValueError('Wrong heldout sample count')
    if legacy['expected_paired_cases'] != len(legacy['snr_db'])*legacy['mc']:
        raise ValueError('Wrong legacy sample count')
    if learn['input_truth'] or not learn['all_subcarriers_in_objective']:
        raise ValueError('Truth inputs or subcarrier reduction are forbidden')
    if learn['split_unit'] != 'geometry_scene' or learn['checkpoint_selection'] != 'validation_only':
        raise ValueError('Split/selection must prevent test leakage')
    if not p['scene_domain']['exclude_legacy_geometry_from_training']:
        raise ValueError('Legacy geometry must be excluded')
    if [method['id'] for method in p['methods']] != EXPECTED_METHODS:
        raise ValueError('Unexpected comparison methods')
    if any(m.get('layers', learn['layers']) != learn['layers'] for m in p['methods']):
        raise ValueError('Learning and inference layer counts differ')
    for key in ('range_m', 'velocity_mps', 'theta_from_z_deg', 'phi_deg',
                'user_theta_from_z_deg', 'user_phi_deg'):
        bounds = p['scene_domain'][key]
        if len(bounds) != 2 or not all(math.isfinite(x) for x in bounds) or bounds[0] >= bounds[1]:
            raise ValueError(f'Invalid scene domain: {key}')
    for key in ('min_target_range_gap_m', 'min_target_direction_gap_deg'):
        if not math.isfinite(p['scene_domain'][key]) or p['scene_domain'][key] <= 0:
            raise ValueError(f'Invalid separation: {key}')
    seeds = [learn[k] for k in ('scene_seed', 'noise_seed', 'model_seed')]
    seeds += [held['scene_seed'], held['noise_seed'], legacy['seed'], p['evaluation']['bootstrap_seed']]
    for seed in seeds:
        positive_int(seed, 'seed')
    if len(set(seeds)) != len(seeds):
        raise ValueError('Seed namespaces must differ')
    if legacy['truth'] != [list(z) for z in Config().truth] or legacy['user_angles'] != list(Config().user_angles):
        raise ValueError('Legacy geometry differs from baseline')
    return p


def load_protocol(path=DEFAULT_PROTOCOL, *, smoke=False):
    p = deepcopy(read_json(path))
    # Validate the submitted full protocol before applying any smoke overrides.
    validate_protocol(p)
    if smoke:
        p['profile'] = 'smoke'
        p['status'] = 'SMOKE_ONLY_NOT_SCIENTIFIC_RESULTS'
        p['run_location'] = 'local_or_server'
        p['physical'].update(SMOKE_OVERRIDES)
        p['learning'].update(train_scenes=2, validation_scenes=1, snr_db=[20],
                             noise_replicates_per_scene_snr=1)
        p['heldout_test'].update(scenes=1, snr_db=[20], mc_per_scene_snr=1, expected_paired_cases=1)
        p['legacy_test'].update(snr_db=[20], mc=1, expected_paired_cases=1)
    return validate_protocol(p)


def require_execution_host(p):
    validate_protocol(p)
    if p['profile'] == 'full' and (platform.system() != 'Linux' or socket.gethostname().split('.')[0].lower() != 'jzm'):
        raise RuntimeError('Full computation is restricted to server jzm. Use --smoke locally.')


def model_config(p, *, truth=None, user_angles=None):
    cfg = Config(**{key: value for key, value in p['physical'].items() if key != 'dtype'})
    # Unavailable truth is poisoned, not silently replaced with the legacy scene.
    cfg.truth = tuple(tuple(row) for row in truth) if truth is not None else ((float('nan'),)*4,)*2
    if user_angles is not None:
        cfg.user_angles = tuple(user_angles)
    return cfg
