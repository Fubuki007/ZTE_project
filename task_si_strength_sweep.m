% =========================================================================
% task_si_strength_sweep.m — SI 强度鲁棒性扫描: ZF vs Null-space (服务器版)
%
%   目的: 验证零空间法在不同自干扰强度下的性能鲁棒性
%         β_SI ∈ {1, 5, 10, 50, 100} (5 档)
%         固定 SNR = 0 dB, MC = 30
%
%   档位选择依据 (由 MC=8 本地预览 + MC=30 单点验证确定):
%     β=1     — 弱干扰基线: 两方法均健康 (检测层+角度层)
%     β=5     — 角度分叉前: ZF 开始抬头 (0.63°), NS 仍 0.14°
%     β=10    — 关键分叉点: ZF 角度 1.27~1.46° (成功率 0%),
%               nullspace 保持 0.21~0.22° (成功率 100%), 角度维 6~7 倍差距
%     β=50    — ZF 角度崩 (10°), nullspace 轻度退化 (1.8°)
%     β=100   — ZF 检测层全崩 (R=149m), nullspace 检测层仍活 (R=0.013m)
%   目的: 展示"门限解决检测层, 预编码解决估计层"的互补叙事:
%         角度子图 β=10 处分叉, β=50 处 ZF 崩 NS 轻退化,
%         距离子图 β=100 处 ZF 崩 NS 仍毫米级 (鲁棒区间 10 倍)
%
%   两条曲线 (同一图上, 横轴 = SI 强度 β_SI, 对数刻度):
%     1. 传统 ZF   — 有 SI, 不抑制 (precoder_type='zf')       [基线]
%     2. 零空间法   — 有 SI, 预编码抑制 (precoder_type='nullspace')
%
%   参数: Mrx=16, L=256, enable_SIC=false (纯靠预编码抑制),
%         K_stream=2, 与 task_si_suppression 链路完全一致
%   门限: R_max_gate=600 m (验收: 垂直感知覆盖 ≤600 m) — ★ 已启用
%         频率平坦 SI 在 RD 谱 DC bin (R=Rmax=1250 m) 的相干峰
%         超出感知范围, 用最大距离门限滤除 (详见 docs文档解说补充节)
%   出图: Nature 风格 semilogy (角度/速度/距离), .fig + .png (300dpi)
%   数据: task_si_strength_sweep_g600.mat
%   运行: matlab -batch "task_si_strength_sweep" (Linux/Windows 均可)
% =========================================================================

clear; close all; clc;
t_all = tic;
warning('off','all');

% ==================== 0. 日志 ============================================
log_path = fullfile(pwd, 'matlab_run.log');
if isfile(log_path), delete(log_path); end
diary(log_path);
diary on;

fprintf('═══════════════════════════════════════════════════════════════\n');
fprintf('  task_si_strength_sweep — SI 强度鲁棒性扫描 (门限版 g600)\n');
fprintf('  ZF (不抑制) vs 零空间法, 固定 SNR=%d dB\n', 0);
fprintf('  开始时间: %s\n', char(datetime('now')));

% ==================== 1. 参数 ============================================
methods        = {'zf', 'nullspace'};
method_labels  = {'ZF (no SI suppression)', 'Null-space'};
n_methods      = numel(methods);

beta_list      = [1, 5, 10, 50, 100]; % SI 幅度相对目标回波的倍数 (5 档)
n_beta         = numel(beta_list);
snr_fixed      = 0;                    % 固定输入 SNR (dB)
n_mc           = 30;                   % 蒙特卡洛次数
L_val          = 256;                  % OFDM 符号数
Mrx_fixed      = 16;
Mx_fixed       = 4;
My_fixed       = 4;

fprintf('  方法: %s\n', strjoin(method_labels, ' | '));
fprintf('  β_SI = [%s] (%d 档) | SNR=%d dB | MC=%d | L=%d | Mrx=%d\n', ...
    num2str(beta_list), n_beta, snr_fixed, n_mc, L_val, Mrx_fixed);
fprintf('  总估计次数: %d 方法 × %d β_SI × %d MC = %d\n', ...
    n_methods, n_beta, n_mc, n_methods * n_beta * n_mc);
fprintf('═══════════════════════════════════════════════════════════════\n\n');

% 预生成种子 (可复现)
rng(20260803);
rng_seeds = randi(2^31-1, n_methods, n_beta, n_mc);

% ==================== 2. 基础参数 ========================================
fprintf('--- 基础参数 ---\n');
baseParams = build_default_params();
baseParams.theta_true = [24.63, 15.94];
baseParams.phi_true   = [30.99, 13.58];
baseParams.R_true     = [200.6, 210.4];
baseParams.v_true     = [15.1, -5.4];
baseParams.alpha      = [1.0, 0.8];
baseParams.enable_SI  = true;          % 开启 SI
baseParams.beta_SI    = 0.1;           % 占位, 循环内按档位覆盖
baseParams.enable_SIC = false;         % ★ 关闭数字 SIC, 纯靠预编码
baseParams.K          = L_val;
baseParams.K_stream   = 2;
baseParams.user_theta_rad = deg2rad(baseParams.theta_true(:));
baseParams.user_phi_rad   = deg2rad(baseParams.phi_true(:));
baseParams.Mx = Mx_fixed;
baseParams.My = My_fixed;
baseParams.joint_fft_3d.Na_x = Mx_fixed;
baseParams.joint_fft_3d.Na_y = My_fixed;
baseParams.fast_estimator.n_samp_l = min(64, max(8, floor(L_val/2)));
baseParams.fast_estimator.R_max_gate = 600;   % ★ 最大距离门限: 滤除
                                               %   SI 的 DC 相干假峰 (1250 m)

Nt_total = baseParams.Ntx * baseParams.Nty;
Nr_fixed = Mx_fixed * My_fixed;
fprintf('  Mrx=%d (%d×%d), Nt=%d, Ns=%d, B=%.1f MHz\n', ...
    Mrx_fixed, Mx_fixed, My_fixed, Nt_total, baseParams.N, baseParams.B/1e6);

% 构造 H_SI (对两种方法、所有 β_SI 档位都相同 — 固定 seed)
rng(20260730);                          % 与 task_si_suppression 相同 seed
hsi_cfg_tx = struct( ...
    'model','ura_rician', 'Nt_total',Nt_total, 'Nr_total',64, ...
    'kappa_SI',10, 'Ntx',baseParams.Ntx, 'Nty',baseParams.Nty, ...
    'Mx',8, 'My',8, 'd_lambda',0.5, ...
    'theta_tx_deg',baseParams.theta_SI, 'phi_tx_deg',baseParams.phi_SI, ...
    'theta_rx_deg',baseParams.theta_SI, 'phi_rx_deg',baseParams.phi_SI);
H_SI_common = generate_HSI(hsi_cfg_tx);   % 预编码器用 (Nr=64)

hsi_cfg_rx = struct( ...
    'model','ura_rician', 'Nt_total',Nt_total, 'Nr_total',Nr_fixed, ...
    'kappa_SI',10, 'Ntx',baseParams.Ntx, 'Nty',baseParams.Nty, ...
    'Mx',Mx_fixed, 'My',My_fixed, 'd_lambda',0.5, ...
    'theta_tx_deg',baseParams.theta_SI, 'phi_tx_deg',baseParams.phi_SI, ...
    'theta_rx_deg',baseParams.theta_SI, 'phi_rx_deg',baseParams.phi_SI);
H_SI_rx = generate_HSI(hsi_cfg_rx);      % 接收端回波模拟用 (Nr=16)

% ==================== 3. 预分配 + 输出目录 ================================
rmse_R_all     = NaN(n_methods, n_beta, n_mc);
rmse_theta_all = NaN(n_methods, n_beta, n_mc);
rmse_v_all     = NaN(n_methods, n_beta, n_mc);

fig_dir = fullfile(pwd, 'fig');
if ~exist(fig_dir, 'dir'), mkdir(fig_dir); end

% ==================== 4. 主仿真 ==========================================
for mi = 1:n_methods
    method = methods{mi};
    fprintf('\n==== 方法 %d/%d: %s ====\n', mi, n_methods, method_labels{mi});

    % --- 生成该方法的 TX 波形 (与 β_SI 无关, 只生成一次, 4 档共享) ---
    p_tx = baseParams;
    p_tx.precoder_type = method;
    p_tx.H_SI = H_SI_common;        % 预编码器需要 H_SI
    p_tx.H_SI_matrix = H_SI_rx;     % 接收端回波模拟需要

    fprintf('  生成 TX 波形 (precoder=%s)...\n', method);
    tx = generate_mimo_ofdm_waveform(p_tx);
    X_tx = tx.X;                    % [Ntx, Nty, Ns, L]
    clear tx;
    fprintf('  TX: [%d×%d×%d×%d]\n', size(X_tx,1), size(X_tx,2), size(X_tx,3), size(X_tx,4));

    % --- β_SI 强度循环 ---
    t_method = tic;
    for bi = 1:n_beta
        beta_val = beta_list(bi);
        rr = NaN(1, n_mc);
        tt = NaN(1, n_mc);
        vv = NaN(1, n_mc);

        fprintf('  [β_SI=%g] (%d/%d) ', beta_val, bi, n_beta);
        t_beta = tic;

        for mc_i = 1:n_mc
            rng(rng_seeds(mi, bi, mc_i));
            p = p_tx;
            p.SNR = snr_fixed;
            p.beta_SI = beta_val;

            try
                rxCube = simulate_radar_channel_3d(X_tx, p);
                [th, ph, R_est, v_est, ~] = joint_estimator_fast(rxCube, X_tx, p);
                cmp = evaluate_estimation(th, ph, R_est, v_est, p, false);
                clear rxCube th ph R_est v_est;

                if isfield(cmp, 'rmse_R') && ~isnan(cmp.rmse_R)
                    rr(mc_i) = cmp.rmse_R;
                    tt(mc_i) = cmp.rmse_theta;
                    vv(mc_i) = cmp.rmse_v;
                end
                clear cmp;
            catch ME
                fprintf('x');
                clear rxCube th ph R_est v_est cmp;
            end

            if mod(mc_i, 20) == 0, fprintf('.'); end
        end

        rmse_R_all(mi, bi, :)     = rr;
        rmse_theta_all(mi, bi, :) = tt;
        rmse_v_all(mi, bi, :)     = vv;

        el = toc(t_beta);
        nan_r = sum(isnan(rr));
        fprintf(' | R=%.2f m  th=%.2f°  v=%.2f m/s | NaN:%d/%d | %s\n', ...
            median(rr, 'omitnan'), median(tt, 'omitnan'), ...
            median(vv, 'omitnan'), nan_r, n_mc, ...
            duration(0,0,round(el),'Format','mm:ss'));
    end

    fprintf('  %s 完成: %.1f min\n', method_labels{mi}, toc(t_method)/60);
end

fprintf('\n总仿真时间: %.1f min\n', toc(t_all)/60);

% ==================== 5. 汇总 + 保存数据 =================================
rmse_R_med     = median(rmse_R_all, 3, 'omitnan');
rmse_theta_med = median(rmse_theta_all, 3, 'omitnan');
rmse_v_med     = median(rmse_v_all, 3, 'omitnan');

fprintf('\n═══════════════════════════════════════════════════════════════\n');
fprintf('  RMSE 汇总 (median over %d MC, SNR=%d dB)\n', n_mc, snr_fixed);
fprintf('═══════════════════════════════════════════════════════════════\n');

for metric = {'距离', '角度', '速度'}
    switch metric{1}
        case '距离', data = rmse_R_med;     unit = 'm';
        case '角度', data = rmse_theta_med; unit = '°';
        case '速度', data = rmse_v_med;     unit = 'm/s';
    end
    fprintf('\n--- %s RMSE (%s) ---\n', metric{1}, unit);
    fprintf('%8s', 'β_SI');
    for mi = 1:n_methods, fprintf('  %-24s', method_labels{mi}); end
    fprintf('\n');
    for bi = 1:n_beta
        fprintf('%8g', beta_list(bi));
        for mi = 1:n_methods, fprintf('  %24.6f', data(mi,bi)); end
        fprintf('\n');
    end
end

mat_path = fullfile(pwd, 'task_si_strength_sweep_g600.mat');
save(mat_path, ...
    'beta_list', 'snr_fixed', 'methods', 'method_labels', 'n_mc', ...
    'rmse_R_med', 'rmse_theta_med', 'rmse_v_med', ...
    'rmse_R_all', 'rmse_theta_all', 'rmse_v_all');
fprintf('\n数据已保存: %s\n', mat_path);

% ==================== 6. 出图 (Nature 风格, semilogy) ====================
fprintf('\n--- 出图 (Nature 风格, semilogy) ---\n');

% 两条线颜色: 红(ZF) / 蓝(零空间)
colors    = {[0.902 0.294 0.208], [0.302 0.733 0.835]};
markers   = {'o', 's'};
linestyle = {'-', '--'};
leg_str   = method_labels;

titles  = {'Angle', 'Velocity', 'Range'};
ylabels = {'Angle RMSE (deg)', 'Velocity RMSE (m/s)', 'Range RMSE (m)'};
datas   = {rmse_theta_med, rmse_v_med, rmse_R_med};
fnames  = {'angle', 'velocity', 'range'};

for fi = 1:3
    fig = figure('Color', 'w', 'Units', 'pixels', ...
        'Position', [120+fi*30, 160+fi*30, 620, 470]);
    hold on;

    for mi = 1:n_methods
        semilogy(beta_list, max(datas{fi}(mi, :), 1e-12), ...
            'Color', colors{mi}, ...
            'Marker', markers{mi}, ...
            'LineStyle', linestyle{mi}, ...
            'LineWidth', 1.3, ...
            'MarkerSize', 6.0, ...
            'MarkerFaceColor', 'w');
    end

    xlabel('Self-interference strength \beta_{SI} (relative to target)', ...
        'FontName', 'Times New Roman', 'FontSize', 10);
    ylabel(ylabels{fi}, 'FontName', 'Times New Roman', 'FontSize', 10);
    title(sprintf('%s RMSE vs SI Strength -- Robustness (SNR=%d dB, MC=%d)', ...
        titles{fi}, snr_fixed, n_mc), ...
        'FontName', 'Times New Roman', 'FontSize', 10, 'FontWeight', 'normal');
    legend(leg_str, 'Location', 'northeastoutside', 'Box', 'on', ...
        'FontName', 'Times New Roman', 'FontSize', 9, 'Interpreter', 'none');

    xlim([beta_list(1)*0.8, beta_list(end)*1.3]);
    set(gca, 'XScale', 'log');
    set(gca, 'XTick', beta_list);
    set(gca, 'XTickLabel', cellstr(num2str(beta_list(:), '%.3g')));

    % log-scale y limits spanning the data in integer powers of 10
    yvals = datas{fi}(:);
    yvals = yvals(~isnan(yvals) & yvals > 0);
    ylo = 10^floor(log10(min(yvals)));
    yhi = 10^ceil(log10(max(yvals)));
    ylim([ylo, yhi]);

    apply_nature_axes(gca);
    set(gca, 'YScale', 'log');

    % explicit 10^n tick labels
    ytick_vals = 10 .^ (floor(log10(ylo)) : ceil(log10(yhi)));
    set(gca, 'YTick', ytick_vals);
    set(gca, 'YTickLabel', ...
        cellfun(@(n) sprintf('10^{%s}', n), ...
        arrayfun(@(v) num2str(log10(v)), ytick_vals, 'UniformOutput', false), ...
        'UniformOutput', false));

    % export .fig and .png
    base_path = fullfile(fig_dir, sprintf('fig_si_strength_g600_%s', fnames{fi}));
    savefig(fig, [base_path '.fig']);
    exportgraphics(fig, [base_path '.png'], 'Resolution', 300);
    close(fig);
    fprintf('  %s -> fig/ (.fig + .png)\n', fnames{fi});
end

% ==================== 7. Toast 通知 (仅 Windows 本地) ======================
if ~isunix
    toast_script = fullfile(pwd, 'toast_notify.py');
    if isfile(toast_script)
        try
            cmd = sprintf('python "%s" "SI强度扫描完成(g600)" "%d方法x%d强度x%dMC, %.1fmin"', ...
                toast_script, n_methods, n_beta, n_mc, toc(t_all)/60);
            system(cmd);
        catch
        end
    end
end

fprintf('\n═══════════════════════════════════════════════════════════════\n');
fprintf('  完成时间: %s\n', char(datetime('now')));
fprintf('  总耗时: %.1f min\n', toc(t_all)/60);
fprintf('  日志: %s\n', log_path);
fprintf('═══════════════════════════════════════════════════════════════\n');

diary off;
