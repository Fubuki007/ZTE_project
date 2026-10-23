"""Audit existing full results and a stated plate model; no new simulation."""
import ast
import csv
import hashlib
import json
import math
from pathlib import Path


def read_json(path):
    return json.loads(path.read_text(encoding='utf-8'))


def read_csv(path):
    with path.open(encoding='utf-8-sig', newline='') as stream:
        return list(csv.DictReader(stream))


def main():
    root = Path(__file__).resolve().parents[2]
    source = root / 'server-results/stage3/results_full_mc100'
    metrics = source / 'range_velocity_metrics'
    progress = read_json(source / 'progress.json')
    identity = read_json(source / 'manifest.json')
    metric_progress = read_json(metrics / 'metrics_progress.json')
    assert progress['complete'] and metric_progress['complete']
    assert progress['total_completed'] == progress['total_expected'] == 1100
    assert metric_progress['source_manifest_id'] == identity['id']
    angle = read_csv(source / 'angle_rmse_vs_snr.csv')
    ranges = read_csv(metrics / 'range_rmse_vs_snr.csv')
    velocities = read_csv(metrics / 'velocity_rmse_vs_snr.csv')
    assert len(angle) == len(ranges) == len(velocities) == 44
    assert all(int(row['mc_completed']) == 100 for row in angle + ranges + velocities)
    improvements = []
    for snr in progress['snr_db']:
        selected = {row['method']: row for row in angle if float(row['snr_db']) == snr}
        baseline = float(selected['DD joint refinement']['angle_rmse_deg'])
        optimized = float(selected['Stage-3 optimized RIS']['angle_rmse_deg'])
        improvements.append(1 - optimized / baseline)
    evidence = {
        'source_profile': identity['profile'],
        'source_manifest_id': identity['id'],
        'completed_cases': progress['total_completed'],
        'cases_per_snr': progress['counts'],
        'snr_db': progress['snr_db'],
        'optimized_angle_rmse_reduction_fraction_min_max': [min(improvements), max(improvements)],
        'max_angle_outlier_rate': max(float(row['outlier_rate']) for row in angle),
        'angle_outlier_definition': 'any absolute theta/phi error above 5 degrees in a trial',
        'max_range_outlier_rate': max(float(row['outlier_rate']) for row in ranges),
        'max_velocity_outlier_rate': max(float(row['outlier_rate']) for row in velocities),
        'range_velocity_outlier_definition': metric_progress['outlier_definition'],
        'range_outlier_threshold_m': metric_progress['range_outlier_threshold_m'],
        'velocity_outlier_threshold_mps': metric_progress['velocity_outlier_threshold_mps'],
        'does_not_establish_zero_failure_probability_or_FAS_gain': True,
        'selected_angle_rows': [row for row in angle if float(row['snr_db']) == -30
            and row['method'] in ('DD joint refinement', 'Stage-3 optimized RIS')],
    }

    config_path = root / 'RIS_stage3/stage3_model.py'
    tree = ast.parse(config_path.read_text(encoding='utf-8'))
    config_node = next(n for n in tree.body if isinstance(n, ast.ClassDef) and n.name == 'Config')
    cfg = {n.target.id: ast.literal_eval(n.value)
           for n in config_node.body if isinstance(n, ast.AnnAssign)}
    wavelength = cfg['c'] / cfg['fc']
    area = cfg['ris_nx'] * cfg['ris_ny'] * (wavelength / 2)**2
    ris = cfg['ris_position']
    dbr = math.sqrt(sum(x*x for x in ris))
    estimates = []
    for radius, _, theta, phi in cfg['truth']:
        theta, phi = math.radians(theta), math.radians(phi)
        direction = [math.sin(theta)*math.cos(phi), math.sin(theta)*math.sin(phi), math.cos(theta)]
        drt = math.sqrt(sum((radius*u-r)**2 for u, r in zip(direction, ris)))
        eta = area * radius / (wavelength * dbr * drt)
        assert 0 < eta < 1
        estimates.append(dict(target_range_m=radius, ris_target_distance_m=drt,
            one_reflected_leg_field_ratio=eta, one_reflected_leg_power_ratio_db=20*math.log10(eta),
            two_reflected_legs_field_ratio=eta**2, two_reflected_legs_power_ratio_db=40*math.log10(eta)))
    plate = dict(
        status='IDEAL_PLATE_ORDER_OF_MAGNITUDE_NOT_CALIBRATED_CHANNEL_OR_PERFORMANCE',
        formula='eta = A * R / (lambda * d_BR * d_RT); RR/direct field ratio approximately eta^2',
        derivation='ideal broadside aperture RCS sigma_RIS approximately 4*pi*A^2/lambda^2; compare free-space propagation factors',
        assumptions=[
            '64 half-wavelength cells occupy N*(lambda/2)^2 physical area',
            'far-field ideal broadside coherent plate, unity reflection efficiency',
            'comparable BS directional gains and target scattering for direct/reflected legs; no blockage',
            'beam-dependent gains, angular projection, polarization, coupling, cell response and RCS are not calibrated',
            'this is a favorable reference approximation, not a universal passive-RIS bound',
            'normalized hop_amplitude is not measured physical reflection efficiency',
        ],
        wavelength_m=wavelength, assumed_area_m2=area, bs_ris_distance_m=dbr,
        configured_hop_amplitude=cfg['hop_amplitude'], targets=estimates)

    files = [source/'manifest.json', source/'progress.json', source/'angle_rmse_vs_snr.csv',
        metrics/'metrics_progress.json', metrics/'range_rmse_vs_snr.csv',
        metrics/'velocity_rmse_vs_snr.csv', config_path]
    result = dict(review_date='2026-10-23', status='EXISTING_RESULT_AUDIT_AND_GEOMETRY_ONLY',
        new_monte_carlo_run=False, existing_results=evidence, plate_reference=plate,
        source_sha256={p.relative_to(root).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest()
                       for p in files})
    output = Path(__file__).with_name('three_question_audit.json')
    output.write_text(json.dumps(result, ensure_ascii=False, indent=2, allow_nan=False)
                      + '\n', encoding='utf-8', newline='\n')
    print(json.dumps(result, ensure_ascii=False, indent=2))


if __name__ == '__main__':
    main()
