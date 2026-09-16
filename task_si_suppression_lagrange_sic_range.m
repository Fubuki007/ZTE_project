% =========================================================================
% task_si_suppression_lagrange_sic_range.m
% -------------------------------------------------------------------------
% 距离 RMSE vs SNR, 两条曲线:
%   1. Lagrange              (拉格朗日预编码, 不数字 SIC)
%   2. Lagrange + digital SIC (拉格朗日 + 导频 LS 数字 SIC, 参考 SIC.m)
%
% 本脚本是 task_si_suppression_nullspace_sic_only.m 的“拉格朗日”对应版,
% 参数同源: SNR=-60:5:25, beta_SI=100, L=256, Mrx=64 (8x8), MC=100。
% 只记录/绘制 距离 RMSE (Range RMSE)。
%
% 运行 (在工程根目录, 与 bf.m/SIC.m/build_default_params.m 等同一目录):
%   matlab -batch "task_si_suppression_lagrange_sic_range"
%
% 内存提示:
%   Mrx=64 且 Ns=12672 时 rx_cube 约 3.3 GB, parfor 2 worker 峰值约 8 GB+,
%   建议服务器内存 >= 16 GB (已把 worker 数限制为 2)。内存不够可把
%   Mrx_fixed/Mx_fixed/My_fixed 改成 16/4/4。
%
% 输出:
%   task_si_suppression_lagrange_sic_range.mat
%   task_si_suppression_lagrange_sic_range_checkpoint.mat  (断点续跑)
%   fig/fig_si_suppression_lagrange_sic_range.fig/.png/.eps
% =========================================================================
function task_si_suppression_lagrange_sic_range()
t_all = tic;
warning('off','all');

% ==================== 0. Log ==============================================
log_path = fullfile(pwd, 'task_si_suppression_lagrange_sic_range.log');
if isfile(log_path), delete(log_path); end
diary(log_path); diary on;

fprintf('============================================================\n');
fprintf('  Range RMSE vs SNR : Lagrange | Lagrange + digital SIC\n');
fprintf('  Start: %s\n', char(datetime('now')));
fprintf('============================================================\n\n');

% ==================== 1. Config ==========================================
resume_from_checkpoint = true;   % true: 跳过 checkpoint 中已完成点
n_workers_target       = 2;     % 并行 worker 数 (改这里! Mrx=64 建议 2, Mrx=16 可到 8)

methods       = {'lagrange', 'lagrange'};
sic_flags     = [false, true];
method_labels = {'Lagrange', 'Lagrange + digital SIC'};
n_methods     = numel(methods);

snr_list = -60:5:25;       % 与 nullspace_sic_only 一致
n_snr    = numel(snr_list);
n_mc     = 100;            % 蒙特卡洛次数

L_val       = 256;
Mrx_fixed   = 64;
Mx_fixed    = 8;
My_fixed    = 8;
beta_SI_val = 100;

fprintf('  Methods: %s\n', strjoin(method_labels, ' | '));
fprintf('  SNR=[%d:%d:%d] (%d pts) | MC=%d | L=%d | Mrx=%d | beta_SI=%g\n', ...
    snr_list(1), snr_list(2)-snr_list(1), snr_list(end), n_snr, ...
    n_mc, L_val, Mrx_fixed, beta_SI_val);
fprintf('  Total trials: %d methods x %d SNR x %d MC = %d\n', ...
    n_methods, n_snr, n_mc, n_methods*n_snr*n_mc);
fprintf('============================================================\n\n');

% 可复现种子
rng(20260730);
rng_seeds = randi(2^31-1, n_methods, n_snr, n_mc);

% ==================== 2. Base parameters =================================
baseParams = build_default_params();
baseParams.theta_true = [24.63, 15.94];
baseParams.phi_true   = [30.99, 13.58];
baseParams.R_true     = [200.6, 210.4];
baseParams.v_true     = [15.1, -5.4];
baseParams.alpha      = [1.0, 0.8];
baseParams.enable_SI  = true;
baseParams.beta_SI    = beta_SI_val;
baseParams.enable_SIC = false;
baseParams.sic_use_true_channel = false;   % false = SIC.m 风格 LS 估计
baseParams.SIC_pilot_len = 128;            % 低 SNR 下 LS 更稳 (参考 lagrange_sic_full)
baseParams.K          = L_val;
baseParams.K_stream   = 2;
baseParams.user_theta_rad = deg2rad(baseParams.theta_true(:));
baseParams.user_phi_rad   = deg2rad(baseParams.phi_true(:));
baseParams.Mx = Mx_fixed;
baseParams.My = My_fixed;
baseParams.joint_fft_3d.Na_x = Mx_fixed;
baseParams.joint_fft_3d.Na_y = My_fixed;
baseParams.fast_estimator.n_samp_l = min(64, max(8, floor(L_val/2)));
baseParams.fast_estimator.R_max_gate = 600;   % 滤除 SI 相干假峰

Nt_total = baseParams.Ntx * baseParams.Nty;    % 4x4 = 16
Nr_fixed = Mx_fixed * My_fixed;                % 8x8 = 64
fprintf('  Mrx=%d (%dx%d), Nt=%d, Ns=%d, B=%.1f MHz\n', ...
    Nr_fixed, Mx_fixed, My_fixed, Nt_total, baseParams.N, baseParams.B/1e6);

% ---- H_SI: 预编码设计 / SI 注入 / 数字 SIC 共用同一个矩阵 (公平对比) ----
rng(20260731);
hsi_cfg = struct( ...
    'model','ura_rician', 'Nt_total',Nt_total, 'Nr_total',Nr_fixed, ...
    'kappa_SI',10, 'Ntx',baseParams.Ntx, 'Nty',baseParams.Nty, ...
    'Mx',Mx_fixed, 'My',My_fixed, 'd_lambda',0.5, ...
    'theta_tx_deg',baseParams.theta_SI, 'phi_tx_deg',baseParams.phi_SI, ...
    'theta_rx_deg',baseParams.theta_SI, 'phi_rx_deg',baseParams.phi_SI, ...
    'seed', 20260731);
H_SI = generate_HSI(hsi_cfg);

% ==================== 2.5 parfor =========================================
use_par = license('test', 'Distrib_Computing_Toolbox') && exist('parpool', 'file') == 2;
if use_par
    try
        n_workers = max(1, min(n_workers_target, feature('numcores')));   % 不超过物理核数
        if isempty(gcp('nocreate'))
            parpool('Processes', n_workers);
        end
        fprintf('  Parallel: parfor %d workers\n\n', n_workers);
    catch
        use_par = false;
        fprintf('  Parallel startup failed, use serial\n\n');
    end
else
    fprintf('  Parallel not available, use serial\n\n');
end

% ==================== 3. Result array + 断点续跑 =========================
rmse_R_all = NaN(n_methods, n_snr, n_mc);
ckpt_path  = fullfile(pwd, 'task_si_suppression_lagrange_sic_range_checkpoint.mat');
if resume_from_checkpoint && isfile(ckpt_path)
    tmp = load(ckpt_path, 'rmse_R_all');
    if isfield(tmp, 'rmse_R_all') && isequal(size(tmp.rmse_R_all), [n_methods, n_snr, n_mc])
        rmse_R_all = tmp.rmse_R_all;
        done = squeeze(any(isfinite(rmse_R_all), 3));
        fprintf('Checkpoint loaded: %d/%d points already done.\n\n', ...
            sum(done(:)), n_methods*n_snr);
    end
    clear tmp;
end

% ==================== 4. Main loop =======================================
for mi = 1:n_methods
    method = methods{mi};
    fprintf('\n==== Method %d/%d: %s ====\n', mi, n_methods, method_labels{mi});

    % TX 每方法生成一次 (与 lagrange_sic_full 一致), 各 SNR 复用
    p_tx = baseParams;
    p_tx.precoder_type = method;
    p_tx.H_SI          = H_SI;
    p_tx.H_SI_matrix   = H_SI;
    fprintf('  Generating TX waveform (precoder=%s)...\n', method);
    tx = generate_mimo_ofdm_waveform(p_tx);
    X_tx = tx.X;
    clear tx;
    fprintf('  TX: [%dx%dx%dx%d]\n', size(X_tx,1), size(X_tx,2), size(X_tx,3), size(X_tx,4));

    t_method = tic;
    for si = 1:n_snr
        snr_val = snr_list(si);

        if resume_from_checkpoint && any(isfinite(rmse_R_all(mi, si, :)))
            fprintf('  [SNR %+4d dB] already done, skip\n', snr_val);
            continue;
        end

        p = p_tx;
        p.SNR         = snr_val;
        p.enable_SI   = true;
        p.enable_SIC  = sic_flags(mi);
        p.H_SI_matrix = H_SI;
        p.beta_SI     = beta_SI_val;

        fprintf('  [SNR %+4d dB] (%d/%d) ', snr_val, si, n_snr);
        t_snr = tic;
        if use_par
            parfor mc_i = 1:n_mc
                rmse_R_all(mi, si, mc_i) = local_mc_rmse(rng_seeds(mi, si, mc_i), X_tx, p);
            end
        else
            for mc_i = 1:n_mc
                rmse_R_all(mi, si, mc_i) = local_mc_rmse(rng_seeds(mi, si, mc_i), X_tx, p);
                if mod(mc_i, 20) == 0, fprintf('.'); end
            end
        end

        el = toc(t_snr);
        fprintf(' | R=%.3f m | NaN:%d/%d | %s\n', ...
            median(rmse_R_all(mi,si,:),'omitnan'), ...
            sum(isnan(rmse_R_all(mi,si,:))), n_mc, ...
            duration(0,0,round(el),'Format','mm:ss'));

        % 每个 SNR 点存一次 checkpoint
        save(ckpt_path, 'snr_list', 'methods', 'method_labels', 'n_mc', ...
            'beta_SI_val', 'L_val', 'Mrx_fixed', 'Mx_fixed', 'My_fixed', ...
            'rmse_R_all');
    end

    fprintf('  %s finished: %.1f min\n', method_labels{mi}, toc(t_method)/60);
end

fprintf('\nTotal simulation time: %.1f min\n', toc(t_all)/60);

% ==================== 5. Summary / save ==================================
rmse_R_med = median(rmse_R_all, 3, 'omitnan');   % (n_methods, n_snr)

save(fullfile(pwd, 'task_si_suppression_lagrange_sic_range.mat'), ...
    'snr_list', 'methods', 'sic_flags', 'method_labels', ...
    'n_mc', 'beta_SI_val', 'L_val', 'Mrx_fixed', 'Mx_fixed', 'My_fixed', ...
    'rmse_R_all', 'rmse_R_med');

fprintf('\n--- Range RMSE summary (m) ---\n');
fprintf('%8s  %18s  %18s\n', 'SNR', method_labels{1}, method_labels{2});
for si = 1:n_snr
    fprintf('%+8d  %18.6f  %18.6f\n', ...
        snr_list(si), rmse_R_med(1, si), rmse_R_med(2, si));
end

% ==================== 6. Figure (Range RMSE vs SNR) ======================
fig_dir = fullfile(pwd, 'fig');
if ~exist(fig_dir, 'dir'), mkdir(fig_dir); end

colors     = {[0.200 0.627 0.173], [0.100 0.420 0.750]};   % 拉格朗日绿 / +SIC 蓝
markers    = {'^', 'v'};
linestyles = {'-.', '--'};

fig = figure('Color', 'w', 'Units', 'pixels', ...
    'Position', [120, 160, 640, 470]);
ax = axes('Parent', fig);
hold(ax, 'on');

for mi = 1:n_methods
    semilogy(ax, snr_list, max(rmse_R_med(mi, :), 1e-12), ...
        'Color', colors{mi}, ...
        'Marker', markers{mi}, ...
        'LineStyle', linestyles{mi}, ...
        'LineWidth', 1.3, ...
        'MarkerSize', 5.5, ...
        'MarkerFaceColor', 'w', ...
        'DisplayName', method_labels{mi});
end

xlabel(ax, 'Input SNR (dB)', 'FontName', 'Times New Roman', 'FontSize', 10);
ylabel(ax, 'Range RMSE (m)', 'FontName', 'Times New Roman', 'FontSize', 10);
title(ax, sprintf('Range RMSE vs SNR (L = %d, MC = %d, \beta_{SI} = %d)', ...
    L_val, n_mc, beta_SI_val), 'FontName', 'Times New Roman', ...
    'FontSize', 10, 'FontWeight', 'normal');
legend(ax, method_labels, 'Location', 'northeast', 'Box', 'on', ...
    'FontName', 'Times New Roman', 'FontSize', 9, 'Interpreter', 'none');
xlim(ax, [snr_list(1)-2, snr_list(end)+2]);

yvals = rmse_R_med(:);
yvals = yvals(~isnan(yvals) & yvals > 0);
if ~isempty(yvals)
    ylo = 10^floor(log10(min(yvals)));
    yhi = 10^ceil(log10(max(yvals)));
    ylim(ax, [ylo, yhi]);
end

apply_nature_axes(ax);
set(ax, 'YScale', 'log');
ytick_vals = 10.^(floor(log10(ylim(ax))) : ceil(log10(ylim(ax))));
set(ax, 'YTick', ytick_vals);
set(ax, 'YTickLabel', arrayfun(@(v) sprintf('10^{%d}', round(log10(v))), ...
    ytick_vals, 'UniformOutput', false));
hold(ax, 'off');

base_path = fullfile(fig_dir, 'fig_si_suppression_lagrange_sic_range');
savefig(fig, [base_path '.fig']);
exportgraphics(fig, [base_path '.png'], 'Resolution', 300);
print(fig, [base_path '.eps'], '-depsc2', '-r300');
fprintf('\n  saved: %s.fig / .png / .eps\n', base_path);

fprintf('\nDone. Saved .mat and figure.\n');
diary off;
end

% =========================================================================
% parfor helper
% =========================================================================
function res = local_mc_rmse(seed, X_tx, p)
rng(seed);
rx_cube = simulate_radar_channel_3d(X_tx, p);
[th, ph, R, v, ~] = joint_estimator_fast(rx_cube, X_tx, p);
cmp = evaluate_estimation(th, ph, R, v, p, false);
if isfield(cmp, 'rmse_R') && ~isnan(cmp.rmse_R)
    res = cmp.rmse_R;
else
    res = NaN;
end
end
