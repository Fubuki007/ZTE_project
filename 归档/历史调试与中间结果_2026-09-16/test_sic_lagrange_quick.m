% =========================================================================
% test_sic_lagrange_quick.m
%   快速验证：数字 SIC 是否能降低 RMSE
%   三条曲线/方案：ZF, Lagrange, Lagrange + digital SIC
%   使用项目现有 simulate_radar_channel_3d + joint_estimator_fast
%
%   参数刻意调小，仅用于本地快速验证趋势。
% =========================================================================
function test_sic_lagrange_quick()
clear; close all; clc;
warning('off','all');

methods     = {'zf', 'lagrange', 'lagrange'};
sic_flags   = [false, false, true];
method_labels = {'ZF', 'Lagrange', 'Lagrange + digital SIC'};
n_methods   = numel(methods);

snr_list    = [-20, 0, 20];
n_mc        = 5;
beta_SI_val = 10;

% 减小规模，快速出结果
N_val = 512;
L_val = 64;
Mx_val = 4; My_val = 4;

fprintf('=== Quick SIC validation ===\n');
fprintf('Ns=%d, L=%d, Mrx=%dx%d, MC=%d, beta_SI=%g\n', ...
    N_val, L_val, Mx_val, My_val, n_mc, beta_SI_val);

baseParams = build_default_params();
baseParams.theta_true = [24.63, 15.94];
baseParams.phi_true   = [30.99, 13.58];
baseParams.R_true     = [200.6, 210.4];
baseParams.v_true     = [15.1, -5.4];
baseParams.alpha      = [1.0, 0.8];
baseParams.enable_SI  = true;
baseParams.beta_SI    = beta_SI_val;
baseParams.enable_SIC = false;
baseParams.sic_use_true_channel = false;
baseParams.SIC_pilot_len = 64;
baseParams.K = L_val;
baseParams.K_stream = 2;
baseParams.Mx = Mx_val;
baseParams.My = My_val;
baseParams.N = N_val;
baseParams.B = N_val * 120e3;
baseParams.joint_fft_3d.Na_x = Mx_val;
baseParams.joint_fft_3d.Na_y = My_val;
baseParams.joint_fft_3d.Nr = N_val;
baseParams.joint_fft_3d.Nv = L_val;
baseParams.fast_estimator.n_samp_l = min(32, max(8, floor(L_val/2)));
baseParams.fast_estimator.n_pad_v = L_val;
baseParams.user_theta_rad = deg2rad(baseParams.theta_true(:));
baseParams.user_phi_rad   = deg2rad(baseParams.phi_true(:));

Nt_total = baseParams.Ntx * baseParams.Nty;
Nr_total = Mx_val * My_val;

% H_SI: 预编码用 64xNt，接收/SIC 用 Mrx x Nt
rng(20260730);
hsi_cfg_tx = struct( ...
    'model','ura_rician', 'Nt_total',Nt_total, 'Nr_total',64, ...
    'kappa_SI',10, 'Ntx',baseParams.Ntx, 'Nty',baseParams.Nty, ...
    'Mx',8, 'My',8, 'd_lambda',0.5, ...
    'theta_tx_deg',baseParams.theta_SI, 'phi_tx_deg',baseParams.phi_SI, ...
    'theta_rx_deg',baseParams.theta_SI, 'phi_rx_deg',baseParams.phi_SI);
H_SI_common = generate_HSI(hsi_cfg_tx);

rng(20260731);
hsi_cfg_rx = struct( ...
    'model','ura_rician', 'Nt_total',Nt_total, 'Nr_total',Nr_total, ...
    'kappa_SI',10, 'Ntx',baseParams.Ntx, 'Nty',baseParams.Nty, ...
    'Mx',Mx_val, 'My',My_val, 'd_lambda',0.5, ...
    'theta_tx_deg',baseParams.theta_SI, 'phi_tx_deg',baseParams.phi_SI, ...
    'theta_rx_deg',baseParams.theta_SI, 'phi_rx_deg',baseParams.phi_SI);
H_SI_rx = generate_HSI(hsi_cfg_rx);

% 预分配
rmse_R = NaN(n_methods, numel(snr_list), n_mc);
rmse_theta = NaN(n_methods, numel(snr_list), n_mc);
rmse_v = NaN(n_methods, numel(snr_list), n_mc);

rng(20260801);
rng_seeds = randi(2^31-1, n_methods, numel(snr_list), n_mc);

for mi = 1:n_methods
    p_tx = baseParams;
    p_tx.precoder_type = methods{mi};
    p_tx.H_SI = H_SI_common;          % 预编码器用
    p_tx.H_SI_matrix = H_SI_rx;       % 接收/SIC 用
    tx = generate_mimo_ofdm_waveform(p_tx);
    X_tx = tx.X;
    clear tx;
    fprintf('\nMethod %d: %s, TX size %dx%dx%dx%d\n', ...
        mi, method_labels{mi}, size(X_tx,1), size(X_tx,2), size(X_tx,3), size(X_tx,4));

    for si = 1:numel(snr_list)
        snr_val = snr_list(si);
        p = p_tx;
        p.SNR = snr_val;
        p.enable_SI = true;
        p.enable_SIC = sic_flags(mi);
        p.H_SI_matrix = H_SI_rx;
        p.beta_SI = beta_SI_val;

        for mc = 1:n_mc
            rng(rng_seeds(mi, si, mc));
            rx_cube = simulate_radar_channel_3d(X_tx, p);
            [th, ph, R, v, ~] = joint_estimator_fast(rx_cube, X_tx, p);
            cmp = evaluate_estimation(th, ph, R, v, p, false);
            if isfield(cmp, 'rmse_R') && ~isnan(cmp.rmse_R)
                rmse_R(mi, si, mc) = cmp.rmse_R;
                rmse_theta(mi, si, mc) = cmp.rmse_theta;
                rmse_v(mi, si, mc) = cmp.rmse_v;
            end
            clear rx_cube th ph R v cmp;
        end
        fprintf('  SNR=%+3d dB: R=%.3f m, th=%.3f deg, v=%.3f m/s\n', ...
            snr_val, median(rmse_R(mi,si,:),'omitnan'), ...
            median(rmse_theta(mi,si,:),'omitnan'), ...
            median(rmse_v(mi,si,:),'omitnan'));
    end
end

rmse_R_med = median(rmse_R, 3, 'omitnan');
rmse_theta_med = median(rmse_theta, 3, 'omitnan');
rmse_v_med = median(rmse_v, 3, 'omitnan');

fprintf('\n=== Summary (median over MC) ===\n');
fprintf('%8s %14s %14s %14s\n', 'SNR', 'ZF', 'Lagrange', 'Lagrange+SIC');
for si = 1:numel(snr_list)
    fprintf('Angle  %+4d %14.4f %14.4f %14.4f\n', snr_list(si), ...
        rmse_theta_med(1,si), rmse_theta_med(2,si), rmse_theta_med(3,si));
end
for si = 1:numel(snr_list)
    fprintf('Range  %+4d %14.4f %14.4f %14.4f\n', snr_list(si), ...
        rmse_R_med(1,si), rmse_R_med(2,si), rmse_R_med(3,si));
end
for si = 1:numel(snr_list)
    fprintf('Vel    %+4d %14.4f %14.4f %14.4f\n', snr_list(si), ...
        rmse_v_med(1,si), rmse_v_med(2,si), rmse_v_med(3,si));
end

% 简单判断
fprintf('\n=== SIC gain check ===\n');
for si = 1:numel(snr_list)
    if rmse_theta_med(3,si) < rmse_theta_med(2,si)
        fprintf('SNR=%+d: SIC better for Angle (%.4f < %.4f)\n', ...
            snr_list(si), rmse_theta_med(3,si), rmse_theta_med(2,si));
    else
        fprintf('SNR=%+d: SIC NOT better for Angle (%.4f >= %.4f)\n', ...
            snr_list(si), rmse_theta_med(3,si), rmse_theta_med(2,si));
    end
end

save('test_sic_lagrange_quick_results.mat', ...
    'snr_list', 'methods', 'method_labels', 'n_mc', 'beta_SI_val', ...
    'rmse_R_med', 'rmse_theta_med', 'rmse_v_med', 'rmse_R', 'rmse_theta', 'rmse_v');
fprintf('\nSaved: test_sic_lagrange_quick_results.mat\n');
end
