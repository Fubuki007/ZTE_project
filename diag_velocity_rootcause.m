% =========================================================================
% diag_velocity_rootcause.m
% Quick diagnosis: why velocity RMSE ~4 m/s while angle/distance are sub-mm
% Tests: 1-target vs 2-target, checks bin detection and interpolation
% =========================================================================
clear; close all; clc;
warning('off', 'all');

% ---- Fixed params ----
params = build_default_params();
params.K = 256;
params.K_stream = 4;
params.comm_channel_type = 'random';
params.enable_SI = true;
params.beta_SI = 0.02;
params.SNR = 10;
params.fast_estimator.n_pad_v = 256;
params.fast_estimator.enable_refine = true;
params.fast_estimator.enable_hann = true;

% Construct H_SI
Nt_total = params.Ntx * params.Nty;
Nr_total = params.Mx * params.My;
hsi_cfg = struct('model', 'ura_rician', 'Nt_total', Nt_total, 'Nr_total', Nr_total, ...
    'kappa_SI', 100, 'Ntx', params.Ntx, 'Nty', params.Nty, ...
    'Mx', params.Mx, 'My', params.My, 'd_lambda', 0.5, ...
    'theta_tx_deg', params.theta_SI, 'phi_tx_deg', params.phi_SI, ...
    'theta_rx_deg', params.theta_SI, 'phi_rx_deg', params.phi_SI, 'seed', 42);
H_SI = generate_HSI(hsi_cfg);
H_SI = H_SI / norm(H_SI, 'fro') * sqrt(Nt_total * Nr_total);

% Generate waveform (Lagrange only - most stable)
params.precoder_type = 'lagrange';
tx_cfg = params;
tx_cfg.H_SI = H_SI;
tx = generate_mimo_ofdm_waveform(tx_cfg);
tx_signal = tx.X;
fprintf('Precoder: %s, si_leak=%.3g, comm_err=%.3g\n', ...
    tx.precoder_info.method, tx.precoder_info.si_leak_avg, tx.precoder_info.comm_err_avg);

% Speed resolution
delta_v = params.c / (2 * params.fc * params.Ts * params.K);
fprintf('Delta_v = %.3f m/s (K=%d, Ts=%.3f us)\n', delta_v, params.K, params.Ts*1e6);
fprintf('True v bins: nv1=%.3f, nv2=%.3f\n\n', params.v_true(1)/delta_v, params.v_true(2)/delta_v);

% ---- Test 1: Single target (target 1 only, v=15.1 m/s) ----
fprintf('=== TEST 1: Single target (v=%.1f m/s) ===\n', params.v_true(1));
p1 = params;
p1.num_targets = 1;
p1.theta_true = params.theta_true(1);
p1.phi_true = params.phi_true(1);
p1.R_true = params.R_true(1);
p1.v_true = params.v_true(1);
p1.alpha = params.alpha(1);
p1.H_SI_matrix = H_SI;

rng(42);
rx1 = simulate_radar_channel_3d(tx_signal, p1);
[th1, ph1, R1, v1, info1] = joint_estimator_fast(rx1, tx_signal, p1);
fprintf('  Detected: %d target(s)\n', info1.detected_targets);
fprintf('  Est  v=%.4f m/s (true=%.2f, err=%.4f m/s, %.2f bins)\n', ...
    v1(1), p1.v_true(1), v1(1)-p1.v_true(1), (v1(1)-p1.v_true(1))/delta_v);
fprintf('  Est  R=%.4f m (true=%.2f, err=%.4f m)\n', R1(1), p1.R_true(1), R1(1)-p1.R_true(1));
fprintf('  Est th=%.4f deg (true=%.2f, err=%.4f deg)\n\n', th1(1), p1.theta_true(1), th1(1)-p1.theta_true(1));

% ---- Test 2: Single target (target 2 only, v=-5.4 m/s) ----
fprintf('=== TEST 2: Single target (v=%.1f m/s) ===\n', params.v_true(2));
p2 = params;
p2.num_targets = 1;
p2.theta_true = params.theta_true(2);
p2.phi_true = params.phi_true(2);
p2.R_true = params.R_true(2);
p2.v_true = params.v_true(2);
p2.alpha = params.alpha(2);
p2.H_SI_matrix = H_SI;

rng(42);
rx2 = simulate_radar_channel_3d(tx_signal, p2);
[th2, ph2, R2, v2, info2] = joint_estimator_fast(rx2, tx_signal, p2);
fprintf('  Detected: %d target(s)\n', info2.detected_targets);
fprintf('  Est  v=%.4f m/s (true=%.2f, err=%.4f m/s, %.2f bins)\n', ...
    v2(1), p2.v_true(1), v2(1)-p2.v_true(1), (v2(1)-p2.v_true(1))/delta_v);
fprintf('  Est  R=%.4f m (true=%.2f, err=%.4f m)\n', R2(1), p2.R_true(1), R2(1)-p2.R_true(1));
fprintf('  Est th=%.4f deg (true=%.2f, err=%.4f deg)\n\n', th2(1), p2.theta_true(1), th2(1)-p2.theta_true(1));

% ---- Test 3: Two targets (baseline, v=15.1 and -5.4) ----
fprintf('=== TEST 3: Two targets (v=[%.1f, %.1f] m/s) ===\n', params.v_true(1), params.v_true(2));
p3 = params;
p3.H_SI_matrix = H_SI;

rng(42);
rx3 = simulate_radar_channel_3d(tx_signal, p3);
[th3, ph3, R3, v3, info3] = joint_estimator_fast(rx3, tx_signal, p3);
fprintf('  Detected: %d target(s)\n', info3.detected_targets);
for i = 1:info3.detected_targets
    fprintf('  Peak %d: v=%.4f, R=%.4f, th=%.4f deg\n', i, v3(i), R3(i), th3(i));
end

% Manual matching for clarity
for i = 1:info3.detected_targets
    d1 = abs(v3(i) - params.v_true(1));
    d2 = abs(v3(i) - params.v_true(2));
    if d1 < d2
        true_v = params.v_true(1);
    else
        true_v = params.v_true(2);
    end
    fprintf('  Peak %d matched to true v=%.1f: est=%.4f, err=%.4f m/s (%.2f bins)\n', ...
        i, true_v, v3(i), v3(i)-true_v, (v3(i)-true_v)/delta_v);
end

cmp3 = evaluate_estimation(th3, ph3, R3, v3, p3, false);
fprintf('  RMSE: R=%.4f m, th=%.4f deg, v=%.4f m/s\n\n', cmp3.rmse_R, cmp3.rmse_theta, cmp3.rmse_v);

% ---- Test 4: Two targets further apart in velocity ----
fprintf('=== TEST 4: Two targets, larger v-separation ===\n');
p4 = params;
p4.v_true = [30.0, -15.0];   % 45 m/s apart (~19 bins)
p4.H_SI_matrix = H_SI;
fprintf('  True v=[%.1f, %.1f] m/s (%.1f bins apart)\n', p4.v_true(1), p4.v_true(2), ...
    (p4.v_true(1)-p4.v_true(2))/delta_v);

rng(42);
rx4 = simulate_radar_channel_3d(tx_signal, p4);
[th4, ph4, R4, v4, info4] = joint_estimator_fast(rx4, tx_signal, p4);
fprintf('  Detected: %d target(s)\n', info4.detected_targets);
for i = 1:info4.detected_targets
    fprintf('  Peak %d: v=%.4f m/s\n', i, v4(i));
    d1 = abs(v4(i) - p4.v_true(1));
    d2 = abs(v4(i) - p4.v_true(2));
    true_v = p4.v_true(1); if d1 > d2, true_v = p4.v_true(2); end
    fprintf('    matched true=%.1f, err=%.4f m/s (%.2f bins)\n', true_v, v4(i)-true_v, (v4(i)-true_v)/delta_v);
end
cmp4 = evaluate_estimation(th4, ph4, R4, v4, p4, false);
fprintf('  RMSE_v=%.4f m/s\n\n', cmp4.rmse_v);

% ---- Summary ----
fprintf('========================================\n');
fprintf('SUMMARY\n');
fprintf('========================================\n');
fprintf('Speed resolution: delta_v = %.3f m/s\n', delta_v);
fprintf('Single target 1 (v=%.1f): err = %.4f m/s\n', params.v_true(1), v1(1)-params.v_true(1));
fprintf('Single target 2 (v=%.1f): err = %.4f m/s\n', params.v_true(2), v2(1)-params.v_true(2));
fprintf('Two targets (separated %.1f m/s = %.1f bins): RMSE_v = %.4f m/s\n', ...
    params.v_true(1)-params.v_true(2), (params.v_true(1)-params.v_true(2))/delta_v, cmp3.rmse_v);
fprintf('Two targets wide (separated %.1f m/s = %.1f bins): RMSE_v = %.4f m/s\n', ...
    45.0, 45.0/delta_v, cmp4.rmse_v);
fprintf('\nKey question: does single-target velocity error stay small?\n');
fprintf('If yes -> two-target interference is the root cause.\n');
fprintf('If no  -> estimator intrinsic limitation (FFT+interp on 256 pts).\n');
