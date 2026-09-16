% =========================================================================
% task_si_strength_lagrange_sic_fullsize_mc10.m
%   完整尺寸 SI 强度扫描：beta_SI = [1, 10, 100, 1000, 10000]
%   Ns=12672, L=256, Mrx=64, SNR=0 dB, MC=10
%   串行运行（省内存），每个 MC 重新生成发射波形
%
%   两个方案（补 task_si_strength_zf_null_sic_fullsize_mc10.m 的缺）：
%     1. Lagrange
%     2. Lagrange + digital SIC（LS 估计 SI 信道后减去重建的 SI 信号）
%
%   与 task_si_strength_zf_null_sic_fullsize_mc10.m 完全同参数、同种子，
%   结果可直接和已有 ZF / Null-space / Null-space+SIC 曲线合并画图。
%
%   服务器运行（在项目根目录）：
%     matlab -batch "task_si_strength_lagrange_sic_fullsize_mc10"
%   Linux 后台运行：
%     nohup matlab -batch "task_si_strength_lagrange_sic_fullsize_mc10" \
%         > run_strength_lagrange_mc10.out 2>&1 &
%
%   预期耗时：约 45 分钟（2 方案，参考 3 方案版本 63.9 分钟）
%
%   输出：
%     task_si_strength_lagrange_sic_fullsize_mc10.mat
%     task_si_strength_lagrange_sic_fullsize_mc10_checkpoint.mat
%     task_si_strength_lagrange_sic_fullsize_mc10.log
% =========================================================================
function task_si_strength_lagrange_sic_fullsize_mc10()
clear; close all; clc; warning('off','all');
t_all = tic;

log_path = fullfile(pwd, 'task_si_strength_lagrange_sic_fullsize_mc10.log');
if isfile(log_path), delete(log_path); end
diary(log_path); diary on;

methods       = {'lagrange', 'lagrange'};
sic_flags     = [false, true];
method_labels = {'Lagrange', 'Lagrange + digital SIC'};
n_methods     = numel(methods);

beta_list = [1, 10, 100, 1000, 10000];
n_beta = numel(beta_list);
n_mc = 10;
SNR_fixed = 0;
L_val = 256;
Mx_val = 8; My_val = 8;

baseParams = build_default_params();
fprintf('=== Full-size SI strength sweep: Lagrange / Lagrange+SIC (MC=10, serial) ===\n');
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
        for mc = 1:n_mc
            res = local_mc_rmse_full(rng_seeds(mi, bi, mc), p);
            rmse_R(mi, bi, mc)     = res(1);
            rmse_theta(mi, bi, mc) = res(2);
            rmse_v(mi, bi, mc)     = res(3);
            if mod(mc, 5) == 0, fprintf('.'); end
        end
        fprintf(' -> R=%.4f m, th=%.4f deg, v=%.4f m/s\n', ...
            median(rmse_R(mi,bi,:),'omitnan'), ...
            median(rmse_theta(mi,bi,:),'omitnan'), ...
            median(rmse_v(mi,bi,:),'omitnan'));

        % checkpoint
        save(fullfile(pwd, 'task_si_strength_lagrange_sic_fullsize_mc10_checkpoint.mat'), ...
            'beta_list','methods','sic_flags','method_labels','n_mc', ...
            'rmse_R','rmse_theta','rmse_v','mi','bi');
    end
end

fprintf('\n=== Full-size SI strength results (MC=10) ===\n');
for bi=1:n_beta
    fprintf('beta=%6d  Lagrange: R=%.4f th=%.4f v=%.4f | Lagrange+SIC: R=%.4f th=%.4f v=%.4f\n', ...
        beta_list(bi), ...
        median(rmse_R(1,bi,:),'omitnan'), median(rmse_theta(1,bi,:),'omitnan'), median(rmse_v(1,bi,:),'omitnan'), ...
        median(rmse_R(2,bi,:),'omitnan'), median(rmse_theta(2,bi,:),'omitnan'), median(rmse_v(2,bi,:),'omitnan'));
end

save(fullfile(pwd, 'task_si_strength_lagrange_sic_fullsize_mc10.mat'), ...
    'beta_list','methods','sic_flags','method_labels','n_mc', ...
    'rmse_R','rmse_theta','rmse_v');
fprintf('\nSaved mat. 总耗时 %.1f min\n', toc(t_all)/60);
diary off;
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
