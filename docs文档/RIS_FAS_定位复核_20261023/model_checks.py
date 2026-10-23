"""Small algebra/geometry checks for the literature review, not sensing simulations.

Run from any directory with Python and NumPy. Results describe only the stated
ideal models; they are not measured FAS localization gains.
"""
import ast
import json
from pathlib import Path

import numpy as np


def main():
    project = Path(__file__).resolve().parents[2]
    tree = ast.parse((project / 'RIS_stage3/stage3_model.py').read_text(encoding='utf-8'))
    config = next(node for node in tree.body if isinstance(node, ast.ClassDef) and node.name == 'Config')
    cfg = {node.target.id: ast.literal_eval(node.value)
           for node in config.body if isinstance(node, ast.AnnAssign)}
    wavelength = cfg['c'] / cfg['fc']
    tx_aperture = np.hypot(cfg['tx_nx'] - 1, cfg['tx_ny'] - 1) * wavelength / 2
    rx_aperture = np.hypot(cfg['rx_nx'] - 1, cfg['rx_ny'] - 1) * wavelength / 2
    bandwidth = cfg['ns'] * cfg['df']

    # Ideal far-field, constant-modulus LoS steering with an unconstrained beam.
    direction = np.array(cfg['ris_position']) / np.linalg.norm(cfg['ris_position'])
    rng = np.random.default_rng(20261023)
    nt = cfg['tx_nx'] * cfg['tx_ny']
    gains = []
    for _ in range(12):
        positions = rng.uniform(-wavelength, wavelength, (nt, 3))
        steering = np.exp(2j * np.pi / wavelength * (positions @ direction))
        matched_beam = steering / np.sqrt(nt)
        gains.append(float(abs(np.vdot(steering, matched_beam)) ** 2))
    deviation = float(np.max(np.abs(np.array(gains) - nt)))
    assert deviation < 1e-10

    # D-optimality and A-optimality can rank position information differently.
    info_a, info_b = np.diag([100., 1., 1.]), np.diag([4., 4., 4.])
    det_a, det_b = float(np.linalg.det(info_a)), float(np.linalg.det(info_b))
    peb_a = float(np.sqrt(np.trace(np.linalg.inv(info_a))))
    peb_b = float(np.sqrt(np.trace(np.linalg.inv(info_b))))
    assert det_a > det_b and peb_a > peb_b

    # A derivative inside the nuisance-amplitude span adds no efficient info.
    dictionary = rng.standard_normal((32, 4)) + 1j * rng.standard_normal((32, 4))
    transform = rng.standard_normal((4, 3)) + 1j * rng.standard_normal((4, 3))
    derivative = dictionary @ transform
    projected = derivative - dictionary @ np.linalg.lstsq(dictionary, derivative, rcond=None)[0]
    ratio = float(np.linalg.norm(projected) / np.linalg.norm(derivative))
    assert ratio < 1e-12

    results = {
        'review_date': '2026-10-23',
        'status': 'ALGEBRA_AND_GEOMETRY_ONLY_NOT_LOCALIZATION_PERFORMANCE',
        'source_config': 'RIS_stage3/stage3_model.py:Config',
        'seed': 20261023,
        'wavelength_m': wavelength,
        'bandwidth_hz': bandwidth,
        'cpi_seconds': (cfg['lc'] + cfg['lf']) * (1 / cfg['df'] + cfg['cp_time']),
        'monostatic_range_bin_m': cfg['c'] / (2 * bandwidth),
        'tx_diagonal_aperture_m': float(tx_aperture),
        'rx_diagonal_aperture_m': float(rx_aperture),
        'tx_fraunhofer_distance_m': float(2 * tx_aperture ** 2 / wavelength),
        'rx_fraunhofer_distance_m': float(2 * rx_aperture ** 2 / wavelength),
        'bs_ris_distance_m': float(np.linalg.norm(cfg['ris_position'])),
        'one_degree_lateral_scale_at_first_target_m': cfg['truth'][0][0] * np.deg2rad(1),
        'rank_one_los_check': {
            'conditions': 'constant-modulus far-field LoS, free matched beam, no other paths or QoS',
            'configurations': len(gains), 'expected_gain': nt, 'max_abs_error': deviation,
        },
        'd_optimal_is_not_a_optimal': {
            'information_a_diagonal': [100, 1, 1], 'information_b_diagonal': [4, 4, 4],
            'det_a': det_a, 'det_b': det_b, 'peb_a': peb_a, 'peb_b': peb_b,
        },
        'nuisance_span_projection_relative_norm': ratio,
    }
    target = Path(__file__).with_name('model_checks.json')
    target.write_text(json.dumps(results, ensure_ascii=False, indent=2, allow_nan=False) + '\n', encoding='utf-8', newline='\n')
    print(json.dumps(results, ensure_ascii=False, indent=2))


if __name__ == '__main__':
    main()
