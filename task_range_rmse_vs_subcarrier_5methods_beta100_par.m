% =========================================================================
% task_range_rmse_vs_subcarrier_5methods_beta100_par.m
% -------------------------------------------------------------------------
% 横坐标 = 子载波数 Ns, 纵坐标 = 距离 RMSE (m, 对数轴), 共 5 条曲线:
%   1. 传统 ZF, 2. 零空间法, 3. 拉格朗日法, 4. 零空间法 + 数字SIC, 5. 拉格朗日法 + 数字SIC
% 与 task_angle_rmse_vs_subcarrier_5methods_beta100.m 唯一区别:
%   纵轴由 角度 RMSE 换成 距离 RMSE (rmse_R), 角度 RMSE 顺带记录并附赠一张图。
% 参数: beta_SI=100, SNR=0 dB, L=256, Mrx=16 (4x4), MC=100 (可改)。
%
% 快速看趋势请用 smoke 版脚本
% 本脚本为服务器全量并行版: MC=100, Ns=[1024 2048 3168 6336 12672], parfor 加速
%
% 输出:
%   task_range_rmse_vs_subcarrier_5methods_beta100_par.mat (+checkpoint)
%   data_range_rmse_vs_subcarrier_5methods_beta100_par.csv
%   fig/fig_range_rmse_vs_subcarrier_5methods_beta100_par.fig/.png/.eps (主图)
%   fig/fig_angle_rmse_vs_subcarrier_5methods_beta100_par_bonus.fig/.png/.eps (附赠角度图)
% =========================================================================
clear; close all; clc;
warning('off','all');
t_all = tic;

% ======================= 0. 日志 =========================================
log_path = fullfile(pwd, 'task_range_rmse_vs_subcarrier_5methods_beta100_par_run.log');
if isfile(log_path), delete(log_path); end
diary(log_path);
diary on;

fprintf('============================================================\n');
fprintf('  task_range_rmse_vs_subcarrier_5methods_beta100_par\n');
fprintf('  Methods: ZF | Null-space | Lagrange | NS+SIC | Lag+SIC\n');
fprintf('  Start: %s\n', char(datetime('now')));

% ======================= 1. 配置 =========================================
resume_from_checkpoint = true;
n_workers_target       = 8;      % 并行 worker 数 (Mrx=16 且 Ns=12672 时每 worker ~1.8GB, 按内存调)
n_mc                   = 100;
snr_fixed              = 0;
beta_SI_val            = 100;
L_val                  = 256;
K_stream               = 2;
Mrx_dim                = 4;
delta_f_fixed          = 120e3;

Ns_list = [1024, 2048, 3168, 6336, 12672];
n_ns = numel(Ns_list);

methods = struct( ...
    'tag',      {'zf', 'nullspace', 'lagrange', 'nullspace_sic', 'lagrange_sic'}, ...
    'label',    {'Traditional ZF (no SI suppression)', 'Null-space', 'Lagrange', ...
                 'Null-space + digital SIC', 'Lagrange + digital SIC'}, ...
    'precoder', {'zf', 'nullspace', 'lagrange', 'nullspace', 'lagrange'}, ...
    'use_sic',  {false, false, false, true, true});
n_methods = numel(methods);

fprintf('  SNR=%+d dB | beta_SI=%g | L=%d | Mrx=%d (4x4) | MC=%d\n', ...
    snr_fixed, beta_SI_val, L_val, Mrx_dim^2, n_mc);
fprintf('  Ns_list = %s\n', mat2str(Ns_list));
fprintf('  Total trials: %d methods x %d Ns x %d MC = %d\n', ...
    n_methods, n_ns, n_mc, n_methods*n_ns*n_mc);
fprintf('============================================================\n\n');

rng(20260825);
rng_seeds = randi(2^31-1, n_methods, n_ns, n_mc);

% ======================= 2. 基础参数 =====================================
fprintf('--- Base parameters ---\n');
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
baseParams.K          = L_val;
baseParams.K_stream   = K_stream;
baseParams.SNR        = snr_fixed;
baseParams.user_theta_rad = deg2rad(baseParams.theta_true(:));
baseParams.user_phi_rad   = deg2rad(baseParams.phi_true(:));
baseParams.fast_estimator.n_samp_l = min(64, max(8, floor(L_val/2)));
baseParams.fast_estimator.R_max_gate = 600;

Nt_total = baseParams.Ntx * baseParams.Nty;
fprintf('  Ntx=%d, 目标: theta=[%.2f %.2f], R=[%.1f %.1f]m\n', ...
    Nt_total, baseParams.theta_true(1), baseParams.theta_true(2), ...
    baseParams.R_true(1), baseParams.R_true(2));

rng(20260826);
if exist('qammod', 'file') == 2
    SIC_pilot = qammod(randi([0 15], Nt_total, 64), 16, 'UnitAveragePower', true);
else
    SIC_pilot = (randn(Nt_total, 64) + 1j*randn(Nt_total, 64)) / sqrt(2);
end
baseParams.SIC_pilot = SIC_pilot;

H_SI_16 = local_hsi(Nt_total, Mrx_dim^2, Mrx_dim, Mrx_dim, 20260831, ...
    baseParams.theta_SI, baseParams.phi_SI);

% ---- parfor 加速 (无 Parallel Toolbox 时自动回退串行) ----
use_par = license('test', 'Distrib_Computing_Toolbox') && exist('parpool', 'file') == 2;
if use_par
    try
        n_workers = max(1, min(n_workers_target, feature('numcores')));
        if isempty(gcp('nocreate')), parpool('Processes', n_workers); end
        fprintf('  Parallel: parfor %d workers\n\n', n_workers);
    catch
        use_par = false;
        fprintf('  Parallel startup failed, use serial\n\n');
    end
else
    fprintf('  Parallel not available, use serial\n\n');
end

% ======================= 3. 结果数组 + 断点续跑 ==========================
rmse_R_ns     = NaN(n_methods, n_ns, n_mc);
rmse_theta_ns = NaN(n_methods, n_ns, n_mc);
ckpt_path = fullfile(pwd, 'task_range_rmse_vs_subcarrier_5methods_beta100_par_checkpoint.mat');
if resume_from_checkpoint && isfile(ckpt_path)
    tmp = load(ckpt_path, 'rmse_R_ns');
    if isfield(tmp, 'rmse_R_ns') && isequal(size(tmp.rmse_R_ns), [n_methods, n_ns, n_mc])
        rmse_R_ns = tmp.rmse_R_ns;
        done = squeeze(any(isfinite(rmse_R_ns), 3));
        fprintf('Checkpoint loaded: %d/%d points already done.\n\n', ...
            sum(done(:)), n_methods*n_ns);
    end
    clear tmp;
end

fig_dir = fullfile(pwd, 'fig');
if ~exist(fig_dir, 'dir'), mkdir(fig_dir); end

% ======================= 4. 主循环 =======================================
for ni = 1:n_ns
    Ns_val = Ns_list(ni);
    fprintf('\n== Ns=%d ==\n', Ns_val);

    p_base_ns = baseParams;
    p_base_ns.N  = Ns_val;
    p_base_ns.B  = Ns_val * delta_f_fixed;
    p_base_ns.meta.range_resolution = p_base_ns.c / (2 * p_base_ns.B);
    p_base_ns.meta.R_max            = p_base_ns.c / (2 * delta_f_fixed);
    p_base_ns.joint_fft_3d.Nr = Ns_val;
    p_base_ns.Mx = Mrx_dim;  p_base_ns.My = Mrx_dim;
    p_base_ns.joint_fft_3d.Na_x = Mrx_dim;  p_base_ns.joint_fft_3d.Na_y = Mrx_dim;
    p_base_ns.H_SI = H_SI_16;  p_base_ns.H_SI_matrix = H_SI_16;

    for mi = 1:n_methods
        method = methods(mi);
        if resume_from_checkpoint && any(isfinite(rmse_R_ns(mi, ni, :)))
            fprintf('  %-28s | already done, skip\n', method.label);
            continue;
        end

        p_tx = p_base_ns;
        p_tx.precoder_type = method.precoder;
        p_tx.enable_SIC = method.use_sic;
        rng(20270000 + ni*10 + mi);
        tx   = generate_mimo_ofdm_waveform(p_tx);
        X_tx = tx.X;
        clear tx;

        p = p_tx;
        p.H_SI_matrix = H_SI_16;
        p.enable_SIC  = method.use_sic;
        p.enable_SI   = true;
        p.SNR         = snr_fixed;

        rr = NaN(1, n_mc);  tt = NaN(1, n_mc);
        t_pt = tic;
        if use_par
            parfor mc_i = 1:n_mc
                res = local_mc_rmse(rng_seeds(mi, ni, mc_i), X_tx, p);
                rr(mc_i) = res(1);  tt(mc_i) = res(2);
            end
        else
            for mc_i = 1:n_mc
                res = local_mc_rmse(rng_seeds(mi, ni, mc_i), X_tx, p);
                rr(mc_i) = res(1);  tt(mc_i) = res(2);
                if mod(mc_i, 20) == 0, fprintf('.'); end
            end
        end
        rmse_R_ns(mi, ni, :) = rr;
        rmse_theta_ns(mi, ni, :) = tt;
        el = toc(t_pt);
        fprintf('  %-28s | R=%.4f m | th=%.4f deg | NaN:%d/%d | %s\n', ...
            method.label, median(rr, 'omitnan'), median(tt, 'omitnan'), ...
            sum(isnan(rr)), n_mc, duration(0,0,round(el),'Format','mm:ss'));
        clear X_tx;
    end

    save(ckpt_path, 'Ns_list', 'Mrx_dim', 'methods', 'n_mc', 'snr_fixed', ...
        'beta_SI_val', 'L_val', 'rmse_R_ns', 'rmse_theta_ns');
end

fprintf('\nTotal simulation: %.1f min\n', toc(t_all)/60);

% ======================= 5. 汇总 / 保存 ==================================
rmse_R_ns_med     = median(rmse_R_ns, 3, 'omitnan');
rmse_theta_ns_med = median(rmse_theta_ns, 3, 'omitnan');

fprintf('\n--- Range RMSE summary (m) ---\n');
fprintf('%10s', 'Ns');
for mi = 1:n_methods, fprintf('  %26s', methods(mi).tag); end
fprintf('\n');
for ni = 1:n_ns
    fprintf('%10d', Ns_list(ni));
    for mi = 1:n_methods, fprintf('  %26.6f', rmse_R_ns_med(mi, ni)); end
    fprintf('\n');
end

fprintf('\n--- Angle RMSE summary (deg) ---\n');
for ni = 1:n_ns
    fprintf('%10d', Ns_list(ni));
    for mi = 1:n_methods, fprintf('  %26.6f', rmse_theta_ns_med(mi, ni)); end
    fprintf('\n');
end

csv_path = fullfile(pwd, 'data_range_rmse_vs_subcarrier_5methods_beta100_par.csv');
fid = fopen(csv_path, 'w');
fprintf(fid, 'Ns,zf,nullspace,lagrange,nullspace_sic,lagrange_sic\n');
fclose(fid);
writematrix([Ns_list(:), rmse_R_ns_med'], csv_path, 'WriteMode', 'append');
fprintf('\nSaved: %s\n', csv_path);

mat_path = fullfile(pwd, 'task_range_rmse_vs_subcarrier_5methods_beta100_par.mat');
save(mat_path, 'Ns_list', 'Mrx_dim', 'methods', 'n_mc', 'snr_fixed', ...
    'beta_SI_val', 'L_val', 'delta_f_fixed', ...
    'rmse_R_ns', 'rmse_R_ns_med', 'rmse_theta_ns', 'rmse_theta_ns_med');
fprintf('Saved: %s\n', mat_path);

% ======================= 6. 画图 =========================================
labels = {methods.label};
local_plot_sweep( ...
    Ns_list, rmse_R_ns_med, labels, ...
    'Number of subcarriers N_s', 'Range RMSE (m)', ...
    'fig_range_rmse_vs_subcarrier_5methods_beta100_par', ...
    sprintf('Range RMSE vs subcarriers (M_{rx}=%d, L=%d, MC=%d, SNR=%+d dB, \\beta_{SI}=%d)', ...
    Mrx_dim^2, L_val, n_mc, snr_fixed, beta_SI_val));
local_plot_sweep( ...
    Ns_list, rmse_theta_ns_med, labels, ...
    'Number of subcarriers N_s', 'Angle RMSE (deg)', ...
    'fig_angle_rmse_vs_subcarrier_5methods_beta100_par_bonus', ...
    sprintf('Angle RMSE vs subcarriers (M_{rx}=%d, L=%d, MC=%d, SNR=%+d dB, \\beta_{SI}=%d)', ...
    Mrx_dim^2, L_val, n_mc, snr_fixed, beta_SI_val));

fprintf('\nDone. Finished: %s | Total: %.1f min\n', ...
    char(datetime('now')), toc(t_all)/60);
diary off;

% =========================================================================
% 局部函数
% =========================================================================
function H = local_hsi(Nt_total, Nr_total, Mx, My, seed, theta_si, phi_si)
hsi_cfg = struct( ...
    'model', 'ura_rician', ...
    'Nt_total', Nt_total, 'Nr_total', Nr_total, ...
    'kappa_SI', 10, ...
    'Ntx', 4, 'Nty', 4, ...
    'Mx', Mx, 'My', My, 'd_lambda', 0.5, ...
    'theta_tx_deg', theta_si, 'phi_tx_deg', phi_si, ...
    'theta_rx_deg', theta_si, 'phi_rx_deg', phi_si, ...
    'seed', seed);
H = generate_HSI(hsi_cfg);
end

function local_plot_sweep(x, ymed, labels, xlab, ylab, fname, title_str)
fig_dir = fullfile(pwd, 'fig');
if ~exist(fig_dir, 'dir'), mkdir(fig_dir); end

colors    = {[0.902 0.294 0.208], [0.302 0.733 0.835], [0.200 0.627 0.173], ...
             [0.100 0.420 0.750], [0.100 0.550 0.200]};
markers    = {'o', 's', '^', 'd', 'v'};
linestyles = {'-', '--', '-.', ':', ':'};

fig = figure('Color', 'w', 'Units', 'pixels', 'Position', [100, 100, 640, 470]);
ax = axes('Parent', fig);
hold(ax, 'on');
x = x(:)';
x_dense = linspace(min(x), max(x), 200);

for mi = 1:numel(labels)
    yy = ymed(mi, :);
    valid = isfinite(yy) & (yy > 0);
    if ~any(valid), continue; end
    yy_plot = max(yy(valid), 1e-12);
    xx_plot = x(valid);
    yy_sm = 10.^interp1(xx_plot, log10(yy_plot), x_dense, 'pchip');
    plot(ax, x_dense, yy_sm, ...
        'Color', colors{mi}, 'LineStyle', linestyles{mi}, ...
        'LineWidth', 1.5, 'DisplayName', labels{mi});
    plot(ax, xx_plot, yy_plot, ...
        'Color', colors{mi}, 'LineStyle', 'none', ...
        'Marker', markers{mi}, 'MarkerSize', 7, ...
        'MarkerFaceColor', 'w', 'HandleVisibility', 'off');
end

set(ax, 'XScale', 'linear', 'YScale', 'log', 'XTick', x);
set(ax, 'FontName', 'Times New Roman', 'FontSize', 10, ...
    'Box', 'on', 'TickDir', 'in', 'LineWidth', 0.75, ...
    'XMinorTick', 'on', 'YMinorTick', 'on', ...
    'GridLineStyle', '-', 'MinorGridLineStyle', ':', ...
    'GridAlpha', 0.18, 'MinorGridAlpha', 0.12, 'Layer', 'top');
grid(ax, 'on');
ax.XColor = [0.10 0.10 0.10];  ax.YColor = [0.10 0.10 0.10];
xrange = max(x) - min(x);
xlim(ax, [min(x) - 0.04*xrange, max(x) + 0.04*xrange]);

yvals = ymed(isfinite(ymed) & (ymed > 0));
if ~isempty(yvals)
    ylo = 10^floor(log10(min(yvals)));  yhi = 10^ceil(log10(max(yvals)));
    ylim(ax, [ylo, yhi]);
    yticks = 10 .^ (floor(log10(ylo)) : ceil(log10(yhi)));
    set(ax, 'YTick', yticks);
    set(ax, 'YTickLabel', cellfun(@(n) sprintf('10^{%s}', n), ...
        arrayfun(@(v) num2str(log10(v)), yticks, 'UniformOutput', false), ...
        'UniformOutput', false));
end

xlabel(ax, xlab, 'FontName', 'Times New Roman', 'FontSize', 12);
ylabel(ax, ylab, 'FontName', 'Times New Roman', 'FontSize', 12);
title(ax, title_str, 'FontName', 'Times New Roman', 'FontSize', 11, 'FontWeight', 'normal');
leg = legend(ax, labels, 'Location', 'northeast', 'Box', 'on');
set(leg, 'FontName', 'Times New Roman', 'FontSize', 9);
leg.EdgeColor = [0.35 0.35 0.35];
hold(ax, 'off');

base = fullfile(fig_dir, fname);
savefig(fig, [base '.fig']);
exportgraphics(fig, [base '.png'], 'Resolution', 300);
print(fig, [base '.eps'], '-depsc2', '-r300');
fprintf('\n  Saved: %s.fig / .png / .eps\n', base);
end

% =========================================================================
% parfor helper
% =========================================================================
function res = local_mc_rmse(seed, X_tx, p)
rng(seed);
try
    rxCube = simulate_radar_channel_3d(X_tx, p);
    [th, ph, R_est, v_est, ~] = joint_estimator_fast(rxCube, X_tx, p);
    cmp = evaluate_estimation(th, ph, R_est, v_est, p, false);
    r = NaN; t = NaN;
    if isfield(cmp, 'rmse_R') && ~isnan(cmp.rmse_R), r = cmp.rmse_R; end
    if isfield(cmp, 'rmse_theta') && ~isnan(cmp.rmse_theta), t = cmp.rmse_theta; end
    res = [r, t];
catch
    res = [NaN, NaN];
end
end
