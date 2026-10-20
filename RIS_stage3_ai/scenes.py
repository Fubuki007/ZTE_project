"""Deterministic scene-disjoint splits, canonical target order and stable seeds."""
import numpy as np
from RIS_stage3.stage3_model import unit
from .storage import digest


def geometry_id(truth, user_angles):
    # Target permutation does not create a new scene.
    return digest(dict(targets=sorted([list(z) for z in truth]), user=list(user_angles)))


def target_geometry_id(truth):
    # Also exclude repeated target geometry with another user or velocity.
    return digest(sorted([[z[0], z[2], z[3]] for z in truth]))


def build_scenes(p):
    d = p['scene_domain']
    legacy = p['legacy_test']
    excluded = {target_geometry_id(legacy['truth'])}
    result = []
    learn_rng = np.random.default_rng(p['learning']['scene_seed'])
    held_rng = np.random.default_rng(p['heldout_test']['scene_seed'])
    for split, count, rng in [('train', p['learning']['train_scenes'], learn_rng),
                              ('validation', p['learning']['validation_scenes'], learn_rng),
                              ('heldout', p['heldout_test']['scenes'], held_rng)]:
        for index in range(count):
            for attempt in range(10000):
                truth = np.column_stack([rng.uniform(*d[key], size=2) for key in
                                         ('range_m', 'velocity_mps', 'theta_from_z_deg', 'phi_deg')])
                truth = truth[np.argsort(truth[:, 0])]
                gap = np.rad2deg(np.arccos(np.clip(unit(*truth[0, 2:]) @ unit(*truth[1, 2:]), -1, 1)))
                key = target_geometry_id(truth)
                if truth[1, 0]-truth[0, 0] >= d['min_target_range_gap_m'] and gap >= d['min_target_direction_gap_deg'] and key not in excluded:
                    break
            else:
                raise ValueError('Cannot sample requested scene separation after 10000 attempts')
            excluded.add(key)
            user = [float(rng.uniform(*d[k])) for k in ('user_theta_from_z_deg', 'user_phi_deg')]
            result.append(dict(scene_id=f'{split}_{index:04d}', split=split, truth=truth.tolist(),
                               user_angles=user, geometry_id=geometry_id(truth, user)))
    result.append(dict(scene_id='legacy_0000', split='legacy', truth=legacy['truth'],
                       user_angles=legacy['user_angles'],
                       geometry_id=geometry_id(legacy['truth'], legacy['user_angles'])))
    return result


def sample_seed(namespace, scene_id, snr, replicate, block):
    # No Python hash(), no dependence on process count, traversal or restart.
    return int(digest([namespace, scene_id, float(snr), replicate, block])[:16], 16)


def build_cases(p, scenes, splits=('train', 'validation')):
    result = []
    for scene in scenes:
        split = scene['split']
        if split not in splits:
            continue
        if split in ('train', 'validation'):
            group = p['learning']
            replicates, namespace = group['noise_replicates_per_scene_snr'], group['noise_seed']
        elif split == 'heldout':
            group = p['heldout_test']
            replicates, namespace = group['mc_per_scene_snr'], group['noise_seed']
        else:
            group = p['legacy_test']
            replicates, namespace = group['mc'], group['seed']
        for si, snr in enumerate(group['snr_db']):
            for replicate in range(replicates):
                result.append(dict(sample_id=f'{scene["scene_id"]}_snr{si:02d}_rep{replicate:04d}',
                    scene_id=scene['scene_id'], split=split, snr_db=snr, replicate=replicate,
                    coarse_seed=sample_seed(namespace, scene['scene_id'], snr, replicate, 'coarse'),
                    fine_seed=sample_seed(namespace, scene['scene_id'], snr, replicate, 'fine')))
    seeds = [case[key] for case in result for key in ('coarse_seed', 'fine_seed')]
    if len(set(seeds)) != len(seeds):
        raise RuntimeError('Noise seed collision')
    return result
