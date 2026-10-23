"""Algebra checks for candidate contributions, not localization experiments."""
import ast
import json
from pathlib import Path

import numpy as np


def main():
    project = Path(__file__).resolve().parents[2]
    tree = ast.parse((project / 'RIS_stage3/stage3_model.py').read_text(encoding='utf-8'))
    config = next(n for n in tree.body if isinstance(n, ast.ClassDef) and n.name == 'Config')
    cfg = {n.target.id: ast.literal_eval(n.value)
           for n in config.body if isinstance(n, ast.AnnAssign)}
    symbol_time = 1 / cfg['df'] + cfg['cp_time']
    orders = np.arange(3)

    two = np.exp(1j * np.array([0., np.pi])[:, None] * orders)
    four = np.exp(1j * (np.pi / 2 * np.arange(4))[:, None] * orders)
    assert np.linalg.matrix_rank(two) == 2
    assert np.linalg.matrix_rank(four) == 3
    orthogonality_error = float(np.max(np.abs(four.conj().T @ four / 4 - np.eye(3))))
    assert orthogonality_error < 1e-12

    # This equality concerns slow-time factors, not the full wideband dictionary.
    length = 64
    sample = np.arange(length)
    times = sample * symbol_time
    doppler = 1800.
    shift = 1 / (4 * symbol_time)
    periodic = np.exp(1j * np.pi / 2 * sample)
    shifted_direct = np.exp(2j * np.pi * (doppler + shift) * times)
    coded_reflection = np.exp(2j * np.pi * doppler * times) * periodic
    alias_error = float(np.max(np.abs(shifted_direct - coded_reflection)))
    assert alias_error < 1e-11
    indices = np.array([0, 0, 1, 3, 2, 1, 2, 0, 3, 3, 1, 0, 2, 3, 0, 1])
    aperiodic = np.exp(1j * np.pi / 2 * np.tile(indices, 4))
    aperiodic_correlation = float(abs(np.vdot(shifted_direct,
        np.exp(2j * np.pi * doppler * times) * aperiodic)) / length)
    assert aperiodic_correlation < 1 - 1e-6

    # For rank-one LoS, replicate every target-independent feed coefficient
    # using a fixed array and no greater transmit power. Target factors cancel.
    rng = np.random.default_rng(20261023)
    nt, nf, blocks = cfg['tx_nx'] * cfg['tx_ny'], 17, 6
    freq = cfg['fc'] + np.linspace(0, (cfg['ns'] - 1) * cfg['df'], nf)
    k = 2 * np.pi * freq / cfg['c']
    direction = np.array(cfg['ris_position']) / np.linalg.norm(cfg['ris_position'])
    fixed_positions = rng.uniform(-.01, .01, (nt, 3))
    a_fixed = np.exp(1j * k[:, None] * (fixed_positions @ direction))
    feed_error, power_excess = 0., 0.
    for _ in range(blocks):
        positions = rng.uniform(-.01, .01, (nt, 3))
        a_moving = np.exp(1j * k[:, None] * (positions @ direction))
        w = rng.standard_normal((nf, nt)) + 1j * rng.standard_normal((nf, nt))
        w /= np.linalg.norm(w, axis=1, keepdims=True)
        feed = np.sum(a_moving.conj() * w, axis=1)
        equivalent = a_fixed * feed[:, None] / nt
        replicated = np.sum(a_fixed.conj() * equivalent, axis=1)
        feed_error = max(feed_error, float(np.max(np.abs(feed - replicated))))
        power_excess = max(power_excess, float(np.max(np.sum(abs(equivalent)**2, axis=1) - 1)))
    assert feed_error < 1e-12 and power_excess < 1e-12

    # Narrowband, single-path sequential sampling: an independent unknown phase
    # at every port can absorb every geometric phase change. Real nuisance phases.
    positions = rng.uniform(-.01, .01, (16, 2))
    kc = 2 * np.pi * cfg['fc'] / cfg['c']
    response = np.exp(-1j * kc * (positions @ np.array([.2, .3])))
    derivative = -1j * kc * response[:, None] * positions
    phases = 1j * np.diag(response)
    g = np.concatenate([derivative.real, derivative.imag], axis=0)
    b = np.concatenate([phases.real, phases.imag], axis=0)
    projected = g - b @ np.linalg.lstsq(b, g, rcond=None)[0]
    gauge_error = float(np.linalg.norm(projected) / np.linalg.norm(g))
    assert gauge_error < 1e-12

    result = {
        'status': 'ALGEBRA_ONLY_NOT_FAS_LOCALIZATION_PERFORMANCE',
        'seed': 20261023,
        'phase_order_code': {
            'orders': [0, 1, 2], 'two_phase_rank': int(np.linalg.matrix_rank(two)),
            'four_phase_rank': int(np.linalg.matrix_rank(four)),
            'four_phase_gram_error': orthogonality_error,
            'RD_DR_same_order_not_separated_by_global_phase_alone': True,
            'orthogonality_requires_static_or_doppler_aligned_factors': True,
        },
        'periodic_code_slow_time_alias': {
            'symbol_time_seconds': symbol_time, 'doppler_shift_hz': shift,
            'direct_monostatic_apparent_velocity_shift_mps': shift * cfg['c'] / (2 * cfg['fc']),
            'factor_identity_max_error': alias_error,
            'one_aperiodic_example_correlation_at_this_offset': aperiodic_correlation,
            'full_dictionary_or_all_offsets_ambiguity_not_tested': True,
        },
        'rank_one_reflected_feed_equivalence': {
            'conditions': 'RR-only target echo; rank-one constant-modulus BS-RIS; free per-frequency digital beams; no communication, SI, or port-dependent noise/loss constraints',
            'blocks': blocks, 'frequency_samples': nf,
            'feed_max_error': feed_error, 'positive_power_excess': power_excess,
        },
        'independent_port_phase_gauge': {
            'conditions': 'narrowband single-path phase-only sequential aperture; known port coordinates; independent unknown scalar phase per sample',
            'relative_projected_geometric_derivative': gauge_error,
            'claim_does_not_cover_wideband_delay_or_simultaneous_receive_information': True,
        },
    }
    target = Path(__file__).with_name('innovation_checks.json')
    target.write_text(json.dumps(result, ensure_ascii=False, indent=2, allow_nan=False)
                      + '\n', encoding='utf-8', newline='\n')
    print(json.dumps(result, ensure_ascii=False, indent=2))


if __name__ == '__main__':
    main()
