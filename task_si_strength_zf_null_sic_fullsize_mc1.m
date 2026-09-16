% =========================================================================
% task_si_strength_zf_null_sic_fullsize_mc1.m
%   完整尺寸 SI 强度扫描：beta_SI = [1, 10, 1000, 10000]
%   Ns=12672, L=256, Mrx=64, MC=1
%   三条曲线：ZF / Null-space / Null-space + digital SIC
% =========================================================================
function task_si_strength_zf_null_sic_fullsize_mc1()
clear; close all; clc; warning('off','all');
t_all = tic;

methods       = {'zf', 'nullspace', 'nullspace'};
sic_flags     = [false, false, true];
method_labels = {'ZF', 'Null-space', 'Null-space + digital SIC'};
n_methods     = numel(methods);

beta_list = [1, 10, 1000, 10000];
n_beta = numel(beta_list);
n_mc = 1;
SNR_fixed = 0;
L_val = 256;
Mx_val = 8; My_val = 8;

baseParams = build_default_params();
fprintf('=== Full-size SI strength sweep (MC=1) ===\n');
fprintf('Ns=%d, L=%d, Mrx=%d, beta_SI=[%s], SNR=%d dB\n\n', ...
    baseParams.N, L_val, Mx_val*My_val, num2str(beta_list), SNR_fixed);

baseParams.theta_true = [24.63, 15.94];
baseParams.phi_true   = [30.99, 13.58];
baseParams.R_true     = [200.6, 210.4];
baseParams.v_true     = [15.1, -5.4];
baseParams.alpha      = [1.0, 0.8];
baseParams.enable_SI  = true;
baseParams.beta_SI    = 100;
baseParams.enable_SIC = false;
baseParams.sic_use_true_channel = false;
baseParams.SIC_pilot_len = 128;
baseParams.SNR        = SNR_fixed;
baseParams.K          = L_val;
baseParams.K_stream   = 2;
baseParams.user_theta_rad = deg2rad(baseParams.theta_true(:));
baseParams.user_phi_rad   = deg2rad(baseParams.phi_true(:));
baseParams.Mx = Mx_val;
baseParams.My = My_val;
baseParams.joint_fft_3d.Na_x = Mx_val;
baseParams.joint_fft_3d.Na_y = My_val;
baseParams.fast_estimator.n_samp_l = 64;
baseParams.fast_estimator.R_max_gate = 600;

Nt_total = baseParams.Ntx * baseParams.Nty;
Nr_total = Mx_val * My_val;

rng(20260731);
hsi_cfg = struct( ...
    'model','ura_rician', 'Nt_total',Nt_total, 'Nr_total',Nr_total, ...
    'kappa_SI',10, 'Ntx',baseParams.Ntx, 'Nty',baseParams.Nty, ...
    'Mx',Mx_val, 'My',My_val, 'd_lambda',0.5, ...
    'theta_tx_deg',baseParams.theta_SI, 'phi_tx_deg',baseParams.phi_SI, ...
    'theta_rx_deg',baseParams.theta_SI, 'phi_rx_deg',baseParams.phi_SI, ...
    'seed', 20260731);
H_SI = generate_HSI(hsi_cfg);

rng(20260801);
rng_seeds = randi(2^31-1, n_methods, n_beta, n_mc);

rmse_R = NaN(n_methods, n_beta, n_mc);
rmse_theta = NaN(n_methods, n_beta, n_mc);
rmse_v = NaN(n_methods, n_beta, n_mc);

for mi = 1:n_methods
    p_tx = baseParams;
    p_tx.precoder_type = methods{mi};
    p_tx.H_SI = H_SI;
    p_tx.H_SI_matrix = H_SI;

    for bi = 1:n_beta
        p = p_tx;
        p.beta_SI = beta_list(bi);
        p.enable_SI = true;
        p.enable_SIC = sic_flags(mi);
        p.H_SI_matrix = H_SI;

        fprintf('  [%s beta=%g] ', method_labels{mi}, beta_list(bi));
        res = local_mc_rmse_full(rng_seeds(mi,bi,1), p);
        rmse_R(mi,bi,1)     = res(1);
        rmse_theta(mi,bi,1) = res(2);
        rmse_v(mi,bi,1)     = res(3);
        fprintf(' -> R=%.4f m, th=%.4f deg, v=%.4f m/s\n', res(1), res(2), res(3));
    end
end

fprintf('\n=== Full-size SI strength results (MC=1) ===\n');
fprintf('Angle RMSE:\n');
for bi=1:n_beta
    fprintf(' beta=%6d  ZF=%.4f  NS=%.4f  NS+SIC=%.4f\n', ...
        beta_list(bi), rmse_theta(1,bi,1), rmse_theta(2,bi,1), rmse_theta(3,bi,1));
end
fprintf('Range RMSE:\n');
for bi=1:n_beta
    fprintf(' beta=%6d  ZF=%.4f  NS=%.4f  NS+SIC=%.4f\n', ...
        beta_list(bi), rmse_R(1,bi,1), rmse_R(2,bi,1), rmse_R(3,bi,1));
end
fprintf('Velocity RMSE:\n');
for bi=1:n_beta
    fprintf(' beta=%6d  ZF=%.4f  NS=%.4f  NS+SIC=%.4f\n', ...
        beta_list(bi), rmse_v(1,bi,1), rmse_v(2,bi,1), rmse_v(3,bi,1));
end

save('task_si_strength_zf_null_sic_fullsize_mc1.mat', ...
    'beta_list','method_labels','rmse_R','rmse_theta','rmse_v');
fprintf('\nSaved mat. 总耗时 %.1f min\n', toc(t_all)/60);
end

function res = local_mc_rmse_full(seed, p)
rng(seed);
tx = generate_mimo_ofdm_waveform(p);
X_tx = tx.X;
rx_cube = simulate_radar_channel_3d(X_tx, p);
[th, ph, R, v, ~] = joint_estimator_fast(rx_cube, X_tx, p);
cmp = evaluate_estimation(th, ph, R, v, p, false);
if isfield(cmp, 'rmse_R') && ~isnan(cmp.rmse_R)
    res = [cmp.rmse_R, cmp.rmse_theta, cmp.rmse_v];
else
    res = [NaN, NaN, NaN];
end
end
