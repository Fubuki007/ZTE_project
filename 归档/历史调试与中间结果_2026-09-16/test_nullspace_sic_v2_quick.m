% =========================================================================
% test_nullspace_sic_v2_quick.m
%   v2 思路快速测试：每个 MC 重新生成发射波形
%   三条曲线：ZF / Null-space / Null-space + digital SIC
%   小规模：Ns=1024, L=128, Mrx=64, beta_SI=100, MC=3, SNR=-10/0/10
% =========================================================================
function test_nullspace_sic_v2_quick()
clear; close all; clc; warning('off','all');
t_all = tic;

methods       = {'zf', 'nullspace', 'nullspace'};
sic_flags     = [false, false, true];
method_labels = {'ZF', 'Null-space', 'Null-space + digital SIC'};
n_methods     = numel(methods);

snr_list = [-10, 0, 10];
n_mc = 3;
beta_SI = 100;
N_val = 1024;
L_val = 128;
Mx_val = 8; My_val = 8;

fprintf('=== v2 quick test ===\n');
fprintf('Ns=%d, L=%d, Mrx=%d, beta_SI=%g, MC=%d\n\n', ...
    N_val, L_val, Mx_val*My_val, beta_SI, n_mc);

baseParams = build_default_params();
baseParams.theta_true = [24.63, 15.94];
baseParams.phi_true   = [30.99, 13.58];
baseParams.R_true     = [200.6, 210.4];
baseParams.v_true     = [15.1, -5.4];
baseParams.alpha      = [1.0, 0.8];
baseParams.enable_SI  = true;
baseParams.beta_SI    = beta_SI;
baseParams.enable_SIC = false;
baseParams.sic_use_true_channel = false;
baseParams.SIC_pilot_len = 128;
baseParams.K          = L_val;
baseParams.K_stream   = 2;
baseParams.user_theta_rad = deg2rad(baseParams.theta_true(:));
baseParams.user_phi_rad   = deg2rad(baseParams.phi_true(:));
baseParams.Mx = Mx_val;
baseParams.My = My_val;
baseParams.N = N_val;
baseParams.B = N_val * 120e3;
baseParams.joint_fft_3d.Na_x = Mx_val;
baseParams.joint_fft_3d.Na_y = My_val;
baseParams.joint_fft_3d.Nr = N_val;
baseParams.joint_fft_3d.Nv = L_val;
baseParams.fast_estimator.n_samp_l = min(64, max(8, floor(L_val/2)));
baseParams.fast_estimator.n_pad_v = L_val;
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
rng_seeds = randi(2^31-1, n_methods, numel(snr_list), n_mc);

rmse_R = NaN(n_methods, numel(snr_list), n_mc);
rmse_theta = NaN(n_methods, numel(snr_list), n_mc);
rmse_v = NaN(n_methods, numel(snr_list), n_mc);

for mi = 1:n_methods
    p_tx = baseParams;
    p_tx.precoder_type = methods{mi};
    p_tx.H_SI = H_SI;
    p_tx.H_SI_matrix = H_SI;

    for si = 1:numel(snr_list)
        snr_val = snr_list(si);
        p = p_tx;
        p.SNR = snr_val;
        p.enable_SI = true;
        p.enable_SIC = sic_flags(mi);
        p.H_SI_matrix = H_SI;
        p.beta_SI = beta_SI;

        for mc = 1:n_mc
            % v2 关键：每个 MC 用不同 seed 重新生成波形
            res = local_mc_rmse_full(rng_seeds(mi, si, mc), p);
            rmse_R(mi, si, mc)     = res(1);
            rmse_theta(mi, si, mc) = res(2);
            rmse_v(mi, si, mc)     = res(3);
        end
        fprintf('  %-28s SNR=%+3d -> R=%.4f m, th=%.4f deg, v=%.4f m/s\n', ...
            method_labels{mi}, snr_val, ...
            median(rmse_R(mi,si,:),'omitnan'), ...
            median(rmse_theta(mi,si,:),'omitnan'), ...
            median(rmse_v(mi,si,:),'omitnan'));
    end
end

rmse_R_med = median(rmse_R, 3, 'omitnan');
rmse_theta_med = median(rmse_theta, 3, 'omitnan');
rmse_v_med = median(rmse_v, 3, 'omitnan');

fprintf('\n=== Summary ===\n');
fprintf('%8s %14s %14s %16s\n', 'SNR', 'ZF', 'Null-space', 'Null-space+SIC');
for si = 1:numel(snr_list)
    fprintf('Angle  %+4d %14.4f %14.4f %16.4f\n', snr_list(si), ...
        rmse_theta_med(1,si), rmse_theta_med(2,si), rmse_theta_med(3,si));
end
for si = 1:numel(snr_list)
    fprintf('Range  %+4d %14.4f %14.4f %16.4f\n', snr_list(si), ...
        rmse_R_med(1,si), rmse_R_med(2,si), rmse_R_med(3,si));
end
for si = 1:numel(snr_list)
    fprintf('Vel    %+4d %14.4f %14.4f %16.4f\n', snr_list(si), ...
        rmse_v_med(1,si), rmse_v_med(2,si), rmse_v_med(3,si));
end
fprintf('\n总耗时 %.1f s\n', toc(t_all));
save('test_nullspace_sic_v2_quick.mat', ...
    'snr_list','method_labels','rmse_R_med','rmse_theta_med','rmse_v_med', ...
    'rmse_R','rmse_theta','rmse_v');
end

function res = local_mc_rmse_full(seed, p)
rng(seed);
tx = generate_mimo_ofdm_waveform(p);   % 每个 MC 重新生成数据波形
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
