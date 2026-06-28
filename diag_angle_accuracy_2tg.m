% =========================================================================
% diag_angle_accuracy_2tg.m
% 角度估计精度诊断: 双目标 vs 单目标对比
% =========================================================================
clear; close all; clc;

% ==== 场景1: 单目标 (基线) ====
params1 = build_default_params();
params1.num_targets = 1;
params1.theta_true  = 25.83;
params1.phi_true    = 28.51;
params1.R_true      = 600.80;
params1.v_true      = 15.1;
params1.alpha       = 1.0;
params1.enable_SI   = false;
params1.K = 256;
params1.precoder_type = 'zf';
params1.K_stream = 1;
params1.user_theta_rad = deg2rad(params1.theta_true(1));
params1.user_phi_rad   = deg2rad(params1.phi_true(1));
params1.SNR = 200;

fprintf('========================================\n');
fprintf('场景1: 单目标 (基线)\n');
fprintf('========================================\n');
tx1 = generate_mimo_ofdm_waveform(params1);
rx1 = simulate_radar_channel_3d(tx1.X, params1);
[th1, ph1, r1, v1, info1] = joint_estimator_fast(rx1, tx1.X, params1);
fprintf('检测: %d目标 | θ=%.4f°(真%.2f) φ=%.4f°(真%.2f) R=%.2fm(真%.2f) v=%.2f(真%.2f)\n', ...
    info1.detected_targets, th1, params1.theta_true, ph1, params1.phi_true, r1, params1.R_true, v1, params1.v_true);

% ==== 场景2: 双目标 (标准设置) ====
params2 = build_default_params();
params2.num_targets = 2;
params2.theta_true  = [25.83, 15.94];
params2.phi_true    = [28.51, 13.58];
params2.R_true      = [600.80, 600.20];
params2.v_true      = [15.1, -5.4];
params2.alpha       = [1.0, 0.8];
params2.enable_SI   = false;
params2.K = 256;
params2.precoder_type = 'zf';
params2.K_stream = 1;
params2.user_theta_rad = deg2rad(params2.theta_true(1));
params2.user_phi_rad   = deg2rad(params2.phi_true(1));
params2.SNR = 200;

fprintf('\n========================================\n');
fprintf('场景2: 双目标 (标准设置, 无噪声无SI)\n');
fprintf('========================================\n');
tx2 = generate_mimo_ofdm_waveform(params2);
rx2 = simulate_radar_channel_3d(tx2.X, params2);
[th2, ph2, r2, v2, info2] = joint_estimator_fast(rx2, tx2.X, params2);
fprintf('检测: %d目标\n', info2.detected_targets);
for i = 1:info2.detected_targets
    fprintf('  目标%d: θ=%.4f° φ=%.4f° R=%.2fm v=%.2fm/s\n', i, th2(i), ph2(i), r2(i), v2(i));
end
cmp2 = evaluate_estimation(th2, ph2, r2, v2, params2, true);

% ==== 场景3: K_stream=4 + 不同用户角度 (保证H_c满秩) ====
params3 = build_default_params(struct(...
    'user_theta_rad', deg2rad([10, 20, 30, 40]'), ...
    'user_phi_rad',   deg2rad([15, 25, 35, 45]'), ...
    'K_stream', 4));
params3.num_targets = 2;
params3.theta_true  = [25.83, 15.94];
params3.phi_true    = [28.51, 13.58];
params3.R_true      = [600.80, 600.20];
params3.v_true      = [15.1, -5.4];
params3.alpha       = [1.0, 0.8];
params3.enable_SI   = false;
params3.K = 256;
params3.precoder_type = 'zf';
params3.SNR = 200;

fprintf('\n========================================\n');
fprintf('场景3: 双目标 + K_stream=4 (多流)\n');
fprintf('========================================\n');
tx3 = generate_mimo_ofdm_waveform(params3);
rx3 = simulate_radar_channel_3d(tx3.X, params3);
[th3, ph3, r3, v3, info3] = joint_estimator_fast(rx3, tx3.X, params3);
fprintf('检测: %d目标\n', info3.detected_targets);
for i = 1:info3.detected_targets
    fprintf('  目标%d: θ=%.4f° φ=%.4f° R=%.2fm v=%.2fm/s\n', i, th3(i), ph3(i), r3(i), v3(i));
end
cmp3 = evaluate_estimation(th3, ph3, r3, v3, params3, true);

% ==== 场景4: 同场景2, L=64 (快速模式) ====
params4 = params2;
params4.K = 64;
params4.joint_fft_3d.Nv = 64;

fprintf('\n========================================\n');
fprintf('场景4: 双目标 + L=64 (快速模式)\n');
fprintf('========================================\n');
tx4 = generate_mimo_ofdm_waveform(params4);
rx4 = simulate_radar_channel_3d(tx4.X, params4);
[th4, ph4, r4, v4, info4] = joint_estimator_fast(rx4, tx4.X, params4);
fprintf('检测: %d目标\n', info4.detected_targets);
for i = 1:info4.detected_targets
    fprintf('  目标%d: θ=%.4f° φ=%.4f° R=%.2fm v=%.2fm/s\n', i, th4(i), ph4(i), r4(i), v4(i));
end
cmp4 = evaluate_estimation(th4, ph4, r4, v4, params4, true);

fprintf('\n=== 诊断完成 ===\n');
