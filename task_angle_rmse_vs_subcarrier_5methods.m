% =========================================================================
% task_angle_rmse_vs_subcarrier_5methods.m
% -------------------------------------------------------------------------
% 横坐标 = 子载波数 Ns, 纵坐标 = 角度 RMSE (对数轴), 共 5 条曲线:
%   1. 传统 ZF             (bf.m 的 W0, 不考虑自干扰抑制)
%   2. 零空间法            (design_precoder 'nullspace', 即 bf.m 的 W1)
%   3. 拉格朗日法          (design_precoder 'lagrange',  即 bf.m 的 W2)
%   4. 零空间法 + 数字 SIC (SIC.m 的导频 LS 估计思路)
%   5. 拉格朗日法 + 数字 SIC
%
% 与 bf.m / SIC.m 的对应关系:
%   * bf.m 与 design_precoder.m 对两种干扰抑制预编码的中文命名恰好互换,
%     本脚本沿用本工程 (design_precoder.m / 之前各 task 脚本) 的命名:
%         'nullspace' = W0 - Nc*pinv(H_SI*Nc)*H_SI*W0      (bf.m 中的 W1)
%         'lagrange'  = R^{-1}*H*(H'*R^{-1}*H)^{-1},
%                       R = H_SI'*H_SI                     (bf.m 中的 W2)
%   * 数字 SIC 严格按 SIC.m 的思路: 先用已知导频做 LS 估计
%         G_hat = Y0*X0'*(X0*X0')^{-1},  Y0 = G_eff*X0 + noise
%     再从接收回波中减去 G_hat*x (simulate_radar_channel_3d.m 的
%     estimate_si_channel_ls 子函数, sic_use_true_channel=false)。
%
% 关键设置:
%   * 子载波间隔固定 delta_f = 120 kHz, 总带宽 B = Ns * 120 kHz;
%     因此最大不模糊距离 R_max = c/(2*delta_f) = 1250 m 不随 Ns 变化。
%   * 强自干扰 beta_SI = 10, 固定 SNR = 0 dB, L = 256, Mrx = 16 (4x4),
%     K_stream = 2 (用户方向 = 目标方向)。
%   * fast_estimator.R_max_gate = 600: 频率平坦 SI 在 R=Rmax=1250 m 处
%     形成相干假峰, 必须用距离门限滤除 (与 main.m 相同设置)。
%   * 预编码设计和 SI 注入/数字 SIC 使用同一个 16x16 H_SI 矩阵,
%     保证对比公平。
%
% 运行环境:
%   与 bf.m / SIC.m / build_default_params.m / generate_HSI.m /
%   design_precoder.m / generate_mimo_ofdm_waveform.m /
%   simulate_radar_channel_3d.m / joint_estimator_fast.m /
%   evaluate_estimation.m / apply_nature_axes.m 放在同一目录运行
%   (服务器上直接 run 本脚本即可)。
%
% 内存提示:
%   Ns=12672 时 tx.X 与 rx_cube 各约 830 MB, 建议服务器内存 >= 16 GB;
%   内存紧张可把 Ns_list 中的 6336/12672 去掉。
%
% 断点续跑:
%   resume_from_checkpoint = true 时自动读取
%   task_angle_rmse_vs_subcarrier_5methods_checkpoint.mat 并跳过已完成点。
%
% 输出:
%   task_angle_rmse_vs_subcarrier_5methods.mat
%   task_angle_rmse_vs_subcarrier_5methods_checkpoint.mat
%   data_angle_rmse_vs_subcarrier_5methods.csv
%   fig/fig_angle_rmse_vs_subcarrier_5methods.fig/.png/.eps
% =========================================================================
clear; close all; clc;
warning('off','all');
t_all = tic;

% ======================= 0. 日志 =========================================
log_path = fullfile(pwd, 'task_angle_rmse_vs_subcarrier_5methods_run.log');
if isfile(log_path), delete(log_path); end
diary(log_path);
diary on;

fprintf('============================================================\n');
fprintf('  task_angle_rmse_vs_subcarrier_5methods\n');
fprintf('  Methods: ZF | Null-space | Lagrange | NS+SIC | Lag+SIC\n');
fprintf('  Start: %s\n', char(datetime('now')));

% ======================= 1. 配置 =========================================
smoke_test             = false;   % true: MC=1 且只跑 2 个 Ns, 先在服务器上验证
resume_from_checkpoint = true;    % true: 自动跳过 checkpoint 中已完成的点
n_mc                   = 30;      % 每点蒙特卡洛次数 (服务器时间充裕可加到 50/100)
snr_fixed              = 0;       % 固定输入 SNR (dB)
beta_SI_val            = 10;      % 强自干扰, 与 task_si_suppression*.m 一致
L_val                  = 256;     % OFDM 符号数 / CPI 长度
K_stream               = 2;
Mrx_dim                = 4;       % 接收 URA 4x4 = 16 天线
delta_f_fixed          = 120e3;   % 子载波间隔固定 120 kHz (3GPP FR2 u=3)

% 子载波数扫描列表 (最后一个 12672 = 4 CC x 3168, 工程实际聚合值)
Ns_list = [512, 1024, 2048, 3168, 6336, 12672];

if smoke_test
    n_mc    = 1;
    Ns_list = [512, 1024];
end
n_ns = numel(Ns_list);

methods = struct( ...
    'tag',      {'zf', 'nullspace', 'lagrange', 'nullspace_sic', 'lagrange_sic'}, ...
    'label_cn', {'传统 ZF（不抑制）', '零空间法', '拉格朗日法', ...
                 '零空间法 + 数字SIC', '拉格朗日法 + 数字SIC'}, ...
    'precoder', {'zf', 'nullspace', 'lagrange', 'nullspace', 'lagrange'}, ...
    'use_sic',  {false, false, false, true, true});
n_methods = numel(methods);

fprintf('  SNR=%+d dB | beta_SI=%g | L=%d | K_stream=%d | Mrx=%d (4x4) | MC=%d\n', ...
    snr_fixed, beta_SI_val, L_val, K_stream, Mrx_dim^2, n_mc);
fprintf('  Ns_list = %s\n', mat2str(Ns_list));
fprintf('  delta_f = %.0f kHz (fixed), B = Ns*120 kHz, R_max = %.0f m (fixed)\n', ...
    delta_f_fixed/1e3, 3e8/(2*delta_f_fixed));
fprintf('  Total trials: %d methods x %d Ns x %d MC = %d\n', ...
    n_methods, n_ns, n_mc, n_methods*n_ns*n_mc);
fprintf('============================================================\n\n');

% 可复现的逐 trial 随机种子 (主种子同 task_si_sweep_5methods.m)
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
baseParams.enable_SIC = false;                % 逐 method 覆盖
baseParams.sic_use_true_channel = false;      % false = SIC.m 风格的 LS 估计
baseParams.SIC_pilot_len = 64;                % SI 信道估计导频长度 (同 SIC.m L=64)

baseParams.K          = L_val;
baseParams.K_stream   = K_stream;
baseParams.SNR        = snr_fixed;
baseParams.user_theta_rad = deg2rad(baseParams.theta_true(:));
baseParams.user_phi_rad   = deg2rad(baseParams.phi_true(:));
baseParams.fast_estimator.n_samp_l = min(64, max(8, floor(L_val/2)));
baseParams.fast_estimator.R_max_gate = 600;   % 滤除 R=Rmax=1250m 处 SI 相干假峰

% (可选) 想让角度快照 Y_snap 利用更多子载波时, 放开下一行:
%   baseParams.fast_estimator.n_samp_r = 512;   % 默认 256, 会被 min(Ns,...) 截断

Nt_total = baseParams.Ntx * baseParams.Nty;    % 4x4 = 16
fprintf('  Ntx=%d (Tx URA %dx%d), 目标: theta=[%.2f %.2f], R=[%.1f %.1f]m\n', ...
    Nt_total, baseParams.Ntx, baseParams.Nty, ...
    baseParams.theta_true(1), baseParams.theta_true(2), ...
    baseParams.R_true(1), baseParams.R_true(2));

% ---- 固定 SIC 导频 (所有 trial 共用, 与 SIC.m 思路一致) ----
rng(20260826);
if exist('qammod', 'file') == 2
    SIC_pilot = qammod(randi([0 15], Nt_total, 64), 16, 'UnitAveragePower', true);
else
    SIC_pilot = (randn(Nt_total, 64) + 1j*randn(Nt_total, 64)) / sqrt(2);
end
baseParams.SIC_pilot = SIC_pilot;

% ---- 固定 16x16 的 H_SI: 预编码设计、SI 注入、数字 SIC 共用同一矩阵 ----
H_SI_16 = local_hsi(Nt_total, Mrx_dim^2, Mrx_dim, Mrx_dim, 20260831, ...
    baseParams.theta_SI, baseParams.phi_SI);

% ======================= 3. 结果数组 + 断点续跑 ==========================
rmse_theta_ns = NaN(n_methods, n_ns, n_mc);
ckpt_path = fullfile(pwd, 'task_angle_rmse_vs_subcarrier_5methods_checkpoint.mat');
if resume_from_checkpoint && isfile(ckpt_path)
    tmp = load(ckpt_path, 'rmse_theta_ns');
    if isfield(tmp, 'rmse_theta_ns') && ...
       isequal(size(tmp.rmse_theta_ns), [n_methods, n_ns, n_mc])
        rmse_theta_ns = tmp.rmse_theta_ns;
        done = squeeze(any(isfinite(rmse_theta_ns), 3));
        fprintf('Checkpoint loaded: %d/%d points already done.\n\n', ...
            sum(done(:)), n_methods*n_ns);
    end
    clear tmp;
end

% ======================= 4. 主循环: 扫 Ns x 方法 =========================
fig_dir = fullfile(pwd, 'fig');
if ~exist(fig_dir, 'dir'), mkdir(fig_dir); end

for ni = 1:n_ns
    Ns_val = Ns_list(ni);
    fprintf('\n== Ns=%d ==\n', Ns_val);

    p_base_ns = baseParams;
    p_base_ns.N  = Ns_val;
    p_base_ns.B  = Ns_val * delta_f_fixed;
    p_base_ns.meta.range_resolution = p_base_ns.c / (2 * p_base_ns.B);
    p_base_ns.meta.R_max            = p_base_ns.c / (2 * delta_f_fixed);
    p_base_ns.joint_fft_3d.Nr = Ns_val;
    p_base_ns.Mx = Mrx_dim;
    p_base_ns.My = Mrx_dim;
    p_base_ns.joint_fft_3d.Na_x = Mrx_dim;
    p_base_ns.joint_fft_3d.Na_y = Mrx_dim;
    p_base_ns.H_SI        = H_SI_16;   % 预编码设计用
    p_base_ns.H_SI_matrix = H_SI_16;   % SI 注入 / 数字 SIC 用

    for mi = 1:n_methods
        method = methods(mi);

        if resume_from_checkpoint && any(isfinite(rmse_theta_ns(mi, ni, :)))
            fprintf('  %-28s | already done, skip\n', method.label_cn);
            continue;
        end

        % 生成该 (方法, Ns) 下的发射波形 (预编码逐子载波独立设计)
        p_tx = p_base_ns;
        p_tx.precoder_type = method.precoder;
        p_tx.enable_SIC = method.use_sic;

        rng(20270000 + ni*10 + mi);
        tx   = generate_mimo_ofdm_waveform(p_tx);
        X_tx = tx.X;                     % [Ntx, Nty, Ns, L]
        clear tx;

        p = p_tx;
        p.H_SI_matrix = H_SI_16;
        p.enable_SIC  = method.use_sic;
        p.enable_SI   = true;
        p.SNR         = snr_fixed;

        tt = NaN(1, n_mc);
        t_pt = tic;
        for mc_i = 1:n_mc
            rng(rng_seeds(mi, ni, mc_i));
            try
                rxCube = simulate_radar_channel_3d(X_tx, p);
                [th, ph, R_est, v_est, ~] = joint_estimator_fast(rxCube, X_tx, p);
                cmp = evaluate_estimation(th, ph, R_est, v_est, p, false);
                clear rxCube th ph R_est v_est;
                if isfield(cmp, 'rmse_theta') && ~isnan(cmp.rmse_theta)
                    tt(mc_i) = cmp.rmse_theta;
                end
                clear cmp;
            catch ME
                clear rxCube th ph R_est v_est cmp;
            end
            if mod(mc_i, 20) == 0, fprintf('.'); end
        end
        rmse_theta_ns(mi, ni, :) = tt;
        el = toc(t_pt);
        fprintf('  %-28s | th=%.4f deg | NaN:%d/%d | %s\n', ...
            method.label_cn, median(tt, 'omitnan'), sum(isnan(tt)), n_mc, ...
            duration(0,0,round(el),'Format','mm:ss'));

        clear X_tx;
    end

    % 每扫完一个 Ns 保存一次 checkpoint (断点续跑)
    save(ckpt_path, ...
        'Ns_list', 'Mrx_dim', 'methods', 'n_mc', 'snr_fixed', ...
        'beta_SI_val', 'L_val', 'rmse_theta_ns');
end

fprintf('\nTotal simulation: %.1f min\n', toc(t_all)/60);

% ======================= 5. 汇总 / 保存 ==================================
rmse_theta_ns_med = median(rmse_theta_ns, 3, 'omitnan');

fprintf('\n--- Angle RMSE median summary (MC=%d) ---\n', n_mc);
fprintf('%10s', 'Ns');
for mi = 1:n_methods
    fprintf('  %26s', methods(mi).tag);
end
fprintf('\n');
for ni = 1:n_ns
    fprintf('%10d', Ns_list(ni));
    for mi = 1:n_methods
        fprintf('  %26.6f', rmse_theta_ns_med(mi, ni));
    end
    fprintf('\n');
end

% ---- 数据文件 (CSV 表头用英文 tag, 避免服务器中文编码问题) ----
csv_path = fullfile(pwd, 'data_angle_rmse_vs_subcarrier_5methods.csv');
fid = fopen(csv_path, 'w');
fprintf(fid, 'Ns,zf,nullspace,lagrange,nullspace_sic,lagrange_sic\n');
fclose(fid);
writematrix([Ns_list(:), rmse_theta_ns_med'], csv_path, 'WriteMode', 'append');
fprintf('\nSaved: %s\n', csv_path);

% ---- .mat ----
mat_path = fullfile(pwd, 'task_angle_rmse_vs_subcarrier_5methods.mat');
save(mat_path, ...
    'Ns_list', 'Mrx_dim', 'methods', 'n_mc', 'snr_fixed', ...
    'beta_SI_val', 'L_val', 'delta_f_fixed', ...
    'rmse_theta_ns', 'rmse_theta_ns_med');
fprintf('Saved: %s\n', mat_path);

% ======================= 6. 画图 =========================================
labels_cn = {methods.label_cn};
local_plot_sweep( ...
    Ns_list, rmse_theta_ns_med, labels_cn, ...
    'Number of subcarriers N_s', ...
    'fig_angle_rmse_vs_subcarrier_5methods', ...
    sprintf('Angle RMSE vs subcarriers (M_{rx}=%d, L=%d, MC=%d, SNR=%+d dB)', ...
    Mrx_dim^2, L_val, n_mc, snr_fixed));

% ======================= 7. 结束 =========================================
toast_script = fullfile(pwd, 'toast_notify.py');
if isfile(toast_script)
    try
        cmd = sprintf('python "%s" "subcarrier sweep done" "%dx%dx%d, %.1fmin"', ...
            toast_script, n_methods, n_ns, n_mc, toc(t_all)/60);
        system(cmd);
    catch
    end
end

fprintf('\nDone. Finished: %s | Total: %.1f min\n', ...
    char(datetime('now')), toc(t_all)/60);
diary off;

% =========================================================================
% 局部函数
% =========================================================================
function H = local_hsi(Nt_total, Nr_total, Mx, My, seed, theta_si, phi_si)
% 生成莱斯 H_SI (与 task_si_sweep_5methods.m 完全一致)
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

function local_plot_sweep(x, ymed, labels, xlab, fname, title_str)
% 5 曲线图: 横轴子载波数(线性), 纵轴角度 RMSE(对数), 空心 marker + 平滑线
fig_dir = fullfile(pwd, 'fig');
if ~exist(fig_dir, 'dir'), mkdir(fig_dir); end

colors = {[0.902 0.294 0.208], ...   % ZF 红
          [0.302 0.733 0.835], ...   % 零空间 青
          [0.200 0.627 0.173], ...   % 拉格朗日 绿
          [0.100 0.420 0.750], ...   % 零空间+SIC 蓝
          [0.100 0.550 0.200]};      % 拉格朗日+SIC 深绿
markers    = {'o', 's', '^', 'd', 'v'};
linestyles = {'-', '--', '-.', ':', ':'};

fig = figure('Color', 'w', 'Units', 'pixels', ...
    'Position', [100, 100, 640, 470]);
hold on;

x = x(:)';
x_dense = linspace(min(x), max(x), 200);

for mi = 1:numel(labels)
    yy = ymed(mi, :);
    valid = isfinite(yy) & (yy > 0);
    if ~any(valid), continue; end

    yy_plot = max(yy(valid), 1e-12);
    xx_plot = x(valid);
    yy_sm = 10.^interp1(xx_plot, log10(yy_plot), x_dense, 'pchip');

    plot(x_dense, yy_sm, ...
        'Color', colors{mi}, 'LineStyle', linestyles{mi}, ...
        'LineWidth', 1.5, 'DisplayName', labels{mi});
    plot(xx_plot, yy_plot, ...
        'Color', colors{mi}, 'LineStyle', 'none', ...
        'Marker', markers{mi}, 'MarkerSize', 7, ...
        'MarkerFaceColor', 'w', 'HandleVisibility', 'off');
end

xlabel(xlab, 'FontName', 'Times New Roman', 'FontSize', 11);
ylabel('Angle RMSE (deg)', 'FontName', 'Times New Roman', 'FontSize', 11);
title(title_str, 'FontName', 'Times New Roman', 'FontSize', 10, ...
    'FontWeight', 'normal');
leg = legend('Location', 'northeast', 'Box', 'on');
set(leg, 'FontName', 'Microsoft YaHei', 'FontSize', 8);  % Linux 无雅黑时自动回退

apply_nature_axes(gca);
set(gca, 'YScale', 'log');

xrange = max(x) - min(x);
xlim([min(x) - 0.06*xrange, max(x) + 0.06*xrange]);

yvals = ymed(isfinite(ymed) & (ymed > 0));
if ~isempty(yvals)
    ylo = 10^floor(log10(min(yvals)));
    yhi = 10^ceil(log10(max(yvals)));
    ylim([ylo, yhi]);
    yticks = 10 .^ (floor(log10(ylo)) : ceil(log10(yhi)));
    set(gca, 'YTick', yticks);
    set(gca, 'YTickLabel', ...
        cellfun(@(n) sprintf('10^{%s}', n), ...
        arrayfun(@(v) num2str(log10(v)), yticks, 'UniformOutput', false), ...
        'UniformOutput', false));
end

base = fullfile(fig_dir, fname);
savefig(fig, [base '.fig']);
exportgraphics(fig, [base '.png'], 'Resolution', 300);
print(fig, [base '.eps'], '-depsc2', '-r300');
fprintf('\n  Saved: %s.fig / .png / .eps\n', base);
end
