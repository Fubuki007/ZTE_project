% =========================================================================
% test_lagrange_fullsize_rep.m
%   全尺寸本地复核（Ns=12672, L=256, Mrx=64）：验证服务器上
%   "Lagrange 单独崩、Lagrange+SIC 完美" 的异常能否在本地复现。
%   zf / nullspace / lagrange / lagrange+SIC, beta=[1,10], MC=2, 串行。
%   单 trial 约 25-30 s，总约 8 分钟。
% =========================================================================
function test_lagrange_fullsize_rep()
clear; close all; clc; warning('off','all');
t_all = tic;

log_path = fullfile(pwd, 'test_lagrange_fullsize_rep.log');
if isfile(log_path), delete(log_path); end
diary(log_path); diary on;

methods   = {'zf', 'nullspace', 'lagrange', 'lagrange'};
sic_flags = [false, false, false, true];
labels    = {'ZF', 'Null-space', 'Lagrange', 'Lagrange+SIC'};
beta_list = [1, 10];
n_mc = 2;

baseParams = build_default_params();
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
baseParams.SNR = 0;
baseParams.K = 256;
baseParams.K_stream = 2;
baseParams.user_theta_rad = deg2rad(baseParams.theta_true(:));
baseParams.user_phi_rad   = deg2rad(baseParams.phi_true(:));
baseParams.Mx = 8; baseParams.My = 8;
baseParams.joint_fft_3d.Na_x = 8;
baseParams.joint_fft_3d.Na_y = 8;
baseParams.fast_estimator.n_samp_l = 64;
baseParams.fast_estimator.R_max_gate = 600;

Nt_total = baseParams.Ntx * baseParams.Nty;

rng(20260731);
hsi_cfg = struct( ...
    'model','ura_rician', 'Nt_total',Nt_total, 'Nr_total',64, ...
    'kappa_SI',10, 'Ntx',baseParams.Ntx, 'Nty',baseParams.Nty, ...
    'Mx',8, 'My',8, 'd_lambda',0.5, ...
    'theta_tx_deg',baseParams.theta_SI, 'phi_tx_deg',baseParams.phi_SI, ...
    'theta_rx_deg',baseParams.theta_SI, 'phi_rx_deg',baseParams.phi_SI, ...
    'seed', 20260731);
H_SI = generate_HSI(hsi_cfg);

rng(20260801);
rng_seeds = randi(2^31-1, numel(methods), numel(beta_list), n_mc);

res = NaN(numel(methods), numel(beta_list), n_mc, 3);
for mi = 1:numel(methods)
    p_tx = baseParams;
    p_tx.precoder_type = methods{mi};
    p_tx.H_SI = H_SI;
    p_tx.H_SI_matrix = H_SI;
    for bi = 1:numel(beta_list)
        p = p_tx;
        p.beta_SI = beta_list(bi);
        p.enable_SI = true;
        p.enable_SIC = sic_flags(mi);
        p.H_SI_matrix = H_SI;
        for mc = 1:n_mc
            rng(rng_seeds(mi, bi, mc));
            t1 = tic;
            tx = generate_mimo_ofdm_waveform(p);
            X_tx = tx.X; clear tx;
            rx_cube = simulate_radar_channel_3d(X_tx, p);
            [th, ph, R, v, ~] = joint_estimator_fast(rx_cube, X_tx, p);
            clear rx_cube;
            cmp = evaluate_estimation(th, ph, R, v, p, false);
            res(mi, bi, mc, :) = [cmp.rmse_R, cmp.rmse_theta, cmp.rmse_v];
            fprintf('%-14s beta=%-4d mc=%d: R=%.4f th=%.4f v=%.4f (%.0fs)\n', ...
                labels{mi}, beta_list(bi), mc, ...
                cmp.rmse_R, cmp.rmse_theta, cmp.rmse_v, toc(t1));
        end
    end
end

save(fullfile(pwd, 'test_lagrange_fullsize_rep.mat'), ...
    'methods','labels','sic_flags','beta_list','n_mc','res');
fprintf('总耗时 %.1f min\n', toc(t_all)/60);
diary off;
end
