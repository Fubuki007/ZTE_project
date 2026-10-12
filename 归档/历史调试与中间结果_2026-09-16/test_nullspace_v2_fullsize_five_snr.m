% =========================================================================
% test_nullspace_v2_fullsize_five_snr.m
%   完整尺寸 v2 逻辑测试：
%     Ns=12672, L=256, Mrx=64, beta_SI=100
%     SNR=[0,5,10,15,20], MC=5
%     每个 MC 重新生成发射波形
% =========================================================================
function test_nullspace_v2_fullsize_five_snr()
clear; close all; clc; warning('off','all');
t_all = tic;

methods       = {'zf', 'nullspace', 'nullspace'};
sic_flags     = [false, false, true];
method_labels = {'ZF', 'Null-space', 'Null-space + digital SIC'};
n_methods     = numel(methods);

snr_list = [0, 5, 10, 15, 20];
n_mc = 5;
beta_SI = 100;
L_val = 256;
Mx_val = 8; My_val = 8;

fprintf('=== Full-size v2 5-SNR test ===\n');
fprintf('Ns=%d, L=%d, Mrx=%d, beta_SI=%g, MC=%d\n', ...
    build_default_params().N, L_val, Mx_val*My_val, beta_SI, n_mc);

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
rng_seeds = randi(2^31-1, n_methods, numel(snr_list), n_mc);

use_par = license('test', 'Distrib_Computing_Toolbox') && exist('parpool', 'file') == 2;
if use_par
    try
        n_workers = min(2, max(1, feature('numcores')));
        if isempty(gcp('nocreate'))
            parpool('Processes', n_workers);
        end
        fprintf('Parallel: parfor %d workers\n', n_workers);
    catch
        use_par = false;
    end
end

rmse_R = NaN(n_methods, numel(snr_list), n_mc);
rmse_theta = NaN(n_methods, numel(snr_list), n_mc);
rmse_v = NaN(n_methods, numel(snr_list), n_mc);

for mi = 1:n_methods
    p_tx = baseParams;
    p_tx.precoder_type = methods{mi};
    p_tx.H_SI = H_SI;
    p_tx.H_SI_matrix = H_SI;

    for si = 1:numel(snr_list)
        p = p_tx;
        p.SNR = snr_list(si);
        p.enable_SI = true;
        p.enable_SIC = sic_flags(mi);
        p.H_SI_matrix = H_SI;
        p.beta_SI = beta_SI;

        fprintf('  [%s SNR=%+d dB] ', method_labels{mi}, snr_list(si));
        if use_par
            parfor mc_i = 1:n_mc
                res = local_mc_rmse_full(rng_seeds(mi, si, mc_i), p);
                rmse_R(mi, si, mc_i)     = res(1);
                rmse_theta(mi, si, mc_i) = res(2);
                rmse_v(mi, si, mc_i)     = res(3);
            end
        else
            for mc_i = 1:n_mc
                res = local_mc_rmse_full(rng_seeds(mi, si, mc_i), p);
                rmse_R(mi, si, mc_i)     = res(1);
                rmse_theta(mi, si, mc_i) = res(2);
                rmse_v(mi, si, mc_i)     = res(3);
                fprintf('.');
            end
        end
        fprintf(' -> R=%.4f m, th=%.4f deg, v=%.4f m/s\n', ...
            median(rmse_R(mi,si,:),'omitnan'), ...
            median(rmse_theta(mi,si,:),'omitnan'), ...
            median(rmse_v(mi,si,:),'omitnan'));
    end
end

rmse_R_med = median(rmse_R, 3, 'omitnan');
rmse_theta_med = median(rmse_theta, 3, 'omitnan');
rmse_v_med = median(rmse_v, 3, 'omitnan');

fprintf('\n=== Full-size v2 summary ===\n');
fprintf('%8s %14s %14s %16s\n', 'SNR', 'ZF', 'Null-space', 'Null-space+SIC');
for si=1:numel(snr_list)
    fprintf('Angle  %+4d %14.4f %14.4f %16.4f\n', snr_list(si), ...
        rmse_theta_med(1,si), rmse_theta_med(2,si), rmse_theta_med(3,si));
end
for si=1:numel(snr_list)
    fprintf('Range  %+4d %14.4f %14.4f %16.4f\n', snr_list(si), ...
        rmse_R_med(1,si), rmse_R_med(2,si), rmse_R_med(3,si));
end
for si=1:numel(snr_list)
    fprintf('Vel    %+4d %14.4f %14.4f %16.4f\n', snr_list(si), ...
        rmse_v_med(1,si), rmse_v_med(2,si), rmse_v_med(3,si));
end
fprintf('\n总耗时 %.1f min\n', toc(t_all)/60);
save('test_nullspace_v2_fullsize_five_snr.mat', ...
    'snr_list','method_labels','rmse_R_med','rmse_theta_med','rmse_v_med', ...
    'rmse_R','rmse_theta','rmse_v');
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
