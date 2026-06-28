% =========================================================================
% diag_angle_accuracy.m
% 角度估计精度诊断: 单目标, 无噪声, 无 SI, 纯测 ESPRIT 精度
% =========================================================================
clear; close all; clc;

params = build_default_params();
params.num_targets = 1;
params.theta_true  = 25.83;
params.phi_true    = 28.51;
params.R_true      = 600.80;
params.v_true      = 15.1;
params.alpha       = 1.0;
params.enable_SI   = false;
params.K           = 256;       % 全尺寸
params.precoder_type = 'zf';
params.K_stream = 1;
params.user_theta_rad = deg2rad(params.theta_true(1));
params.user_phi_rad   = deg2rad(params.phi_true(1));

fprintf('=== 角度估计精度诊断 (单目标, 无噪声, 无SI, L=256) ===\n');
fprintf('真值: θ=%.2f°, φ=%.2f°, R=%.2fm, v=%.2fm/s\n', ...
    params.theta_true, params.phi_true, params.R_true, params.v_true);

% 生成波形
tx = generate_mimo_ofdm_waveform(params);
fprintf('波形: Nt=%d, Nr=%d, Ns=%d, L=%d\n', ...
    tx.Ntx*tx.Nty, params.Mx*params.My, params.N, params.K);

% 无噪声回波
params.SNR = 200;  % 几乎无噪声
rx_cube = simulate_radar_channel_3d(tx.X, params);

% 估计
[theta_est, phi_est, R_est, v_est, info] = joint_estimator_fast(rx_cube, tx.X, params);

fprintf('\n--- 估计结果 ---\n');
fprintf('检测到 %d 个目标\n', info.detected_targets);
fprintf('θ_est = %.4f°  (真值 %.2f°, 误差 %.4f°)\n', theta_est, params.theta_true, theta_est - params.theta_true);
fprintf('φ_est = %.4f°  (真值 %.2f°, 误差 %.4f°)\n', phi_est, params.phi_true, phi_est - params.phi_true);
fprintf('R_est = %.4f m  (真值 %.2f m, 误差 %.4f m)\n', R_est, params.R_true, R_est - params.R_true);
fprintf('v_est = %.4f m/s (真值 %.2f m/s, 误差 %.4f m/s)\n', v_est, params.v_true, v_est - params.v_true);

% 总角度误差
angle_err_total = sqrt((theta_est - params.theta_true)^2 + (phi_est - params.phi_true)^2);
fprintf('总角度误差 = %.4f°\n', angle_err_total);

% 多跑几次看方差
fprintf('\n--- 10 次独立运行 (无噪声, 随机种子) ---\n');
theta_errs = zeros(1, 10);
phi_errs = zeros(1, 10);
for i = 1:10
    rng(i * 100);
    tx_i = generate_mimo_ofdm_waveform(params);
    rx_i = simulate_radar_channel_3d(tx_i.X, params);
    [th, ph, ~, ~] = joint_estimator_fast(rx_i, tx_i.X, params);
    theta_errs(i) = th - params.theta_true;
    phi_errs(i) = ph - params.phi_true;
    fprintf('  第%d次: θ_err=%.4f°, φ_err=%.4f°\n', i, theta_errs(i), phi_errs(i));
end
fprintf('θ RMSE = %.4f° (std=%.4f°)\n', sqrt(mean(theta_errs.^2)), std(theta_errs));
fprintf('φ RMSE = %.4f° (std=%.4f°)\n', sqrt(mean(phi_errs.^2)), std(phi_errs));

fprintf('\n=== 诊断完成 ===\n');
