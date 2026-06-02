% =========================================================================
% task5_rmse_vs_snr.m
% -------------------------------------------------------------------------
% RMSE vs SNR 对比: ZF / Lagrange / Nullspace 三种预编码方案
% 三张图: 距离 RMSE / 角度 RMSE / 速度 RMSE
% 横轴 SNR, 纵轴 RMSE (科学计数法)
%
% 蒙特卡洛: 每 SNR 点多次独立 trial (噪声种子随机)
% 预编码: 关闭 SI, 纯对比预编码对波束方向图的效应
% =========================================================================
clear; close all; clc;
t_all = tic;
warning('off', 'all');

fprintf('============================================================\n');
fprintf('  Task 5: RMSE vs SNR — ZF / Lagrange / Nullspace 对比\n');
fprintf('============================================================\n\n');

% ---- 1. 基础参数 (先构造 override, 再一次性 build) ----
% K_stream=4 + 不同用户角度 → LoS H_c 满秩 (rank=4), nullspace 正常工作
override_cfg = struct(...
    'user_theta_rad', deg2rad([10, 20, 30, 40]'), ...
    'user_phi_rad',   deg2rad([15, 25, 35, 45]'), ...
    'K_stream', 4);
params = build_default_params(override_cfg);
params.K_stream = 4;

% --- 快速模式 (控制 ~5min 总耗时) ---
params.K = 64;
params.joint_fft_3d.Nv = 64;
params.joint_4d.memory_cap_gb = 4;

% --- 关闭 SI (纯对比预编码波束方向图) ---
params.enable_SI = false;

% --- 构造 H_SI (nullspace/lagrange 设计需要, 即使 SI 关闭) ---
Nt_total = params.Ntx * params.Nty;
Nr_total = params.Mx  * params.My;
hsi_cfg = struct( ...
    'model',    'ura_rician', ...
    'Nt_total', Nt_total, ...
    'Nr_total', Nr_total, ...
    'kappa_SI', 100, ...          % 中等 κ, 保证 nullspace 有可操作零空间
    'Ntx', params.Ntx, 'Nty', params.Nty, ...
    'Mx',  params.Mx,  'My',  params.My, ...
    'd_lambda', 0.5, ...
    'theta_tx_deg', params.theta_SI, 'phi_tx_deg', params.phi_SI, ...
    'theta_rx_deg', params.theta_SI, 'phi_rx_deg', params.phi_SI, ...
    'seed', 2026);
H_SI = generate_HSI(hsi_cfg);
H_SI = H_SI / norm(H_SI, 'fro') * sqrt(Nt_total * Nr_total);

fprintf('规模: Nt=%d, Nr=%d, Ns=%d, L=%d, K_stream=%d\n', ...
    Nt_total, Nr_total, params.N, params.K, params.K_stream);
fprintf('用户角度 (°): [%s], Rmax=%.1fm, ΔR=%.3fm\n', ...
    num2str(rad2deg(params.user_theta_rad'), '%.1f '), ...
    params.meta.R_max, params.meta.range_resolution);

% ---- 2. 实验矩阵 ----
precoders     = {'zf', 'nullspace', 'lagrange'};
% SNR 范围 (先试 -30:10:20, 若无下降趋势则扩到 -40:5:10)
snr_list      = -50:5:5;
n_mc          = 5;                % 蒙特卡洛次数 (控制总时长)
n_prec        = numel(precoders);
n_snr         = numel(snr_list);

fprintf('SNR 范围: [%d, %d] dB, 步长 5 dB, 共 %d 点\n', snr_list(1), snr_list(end), n_snr);
fprintf('蒙特卡洛: %d 次/点, 总计 %d 次估计\n', n_mc, n_snr * n_prec * n_mc);
est_total = n_snr * n_prec * n_mc;
fprintf('预估耗时: ~%.0f 分钟 (每估计 ~%.1fs)\n\n', est_total * 1.2 / 60, 1.2);

% ---- 3. 预编码器准备 (波形生成一次, 信道固定) ----
%    每种预编码的 W 是固定的, 但每次 trial 的噪声不同
fprintf('--- 生成波形 (3种预编码) ---\n');
tx_signals = cell(1, n_prec);
for prec_i = 1:n_prec
    pt = precoders{prec_i};
    tx_cfg = params;
    tx_cfg.precoder_type = pt;
    tx_cfg.H_SI = H_SI;
    tx = generate_mimo_ofdm_waveform(tx_cfg);
    tx_signals{prec_i} = tx;
    fprintf('  %-10s: si_leak=%.3g, comm_err=%.3g\n', pt, ...
        tx.precoder_info.si_leak_avg, tx.precoder_info.comm_err_avg);
end
fprintf('\n');

% ---- 4. 主循环: SNR × 预编码 × MC ----
%    存储: rmse_R(prec, snr, mc), rmse_theta, rmse_v
rmse_R     = zeros(n_prec, n_snr, n_mc);
rmse_theta = zeros(n_prec, n_snr, n_mc);
rmse_v     = zeros(n_prec, n_snr, n_mc);

est_total = n_snr * n_prec * n_mc;
est_done  = 0;
t_loop_start = tic;

for snr_i = 1:n_snr
    snr_val = snr_list(snr_i);

    for prec_i = 1:n_prec
        pt = precoders{prec_i};
        tx_signal = tx_signals{prec_i}.X;

        p = params;
        p.SNR = snr_val;
        p.enable_SI = false;

        for mc_i = 1:n_mc
            est_done = est_done + 1;

            if mc_i > 1
                rng('shuffle');
            end

            t_est = tic;
            rx_cube = simulate_radar_channel_3d(tx_signal, p);
            tx_sum = squeeze(sum(sum(tx_signal, 1), 2));
            [th, ph, R, v, ~] = joint_estimator_fast(rx_cube, tx_sum, p);
            rt = toc(t_est);

            cmp = evaluate_estimation(th, ph, R, v, p, false);

            if isfield(cmp, 'rmse_R') && ~isnan(cmp.rmse_R)
                rmse_R(prec_i, snr_i, mc_i)     = cmp.rmse_R;
                rmse_theta(prec_i, snr_i, mc_i) = cmp.rmse_theta;
                rmse_v(prec_i, snr_i, mc_i)     = cmp.rmse_v;
            else
                rmse_R(prec_i, snr_i, mc_i)     = NaN;
                rmse_theta(prec_i, snr_i, mc_i) = NaN;
                rmse_v(prec_i, snr_i, mc_i)     = NaN;
            end

            clear rx_cube;

            % ---- 进度条 ----
            pct = 100 * est_done / est_total;
            elapsed = toc(t_loop_start);
            eta = elapsed / est_done * (est_total - est_done);
            bar_len = 30;
            bar_fill = round(bar_len * est_done / est_total);
            bar_str = ['[', repmat('=', 1, bar_fill), repmat(' ', 1, bar_len - bar_fill), ']'];
            fprintf('%s %3.0f%% | SNR=%+3ddB %-10s | mc=%d/%d | t=%.1fs | %s elapsed ETA %s\r', ...
                bar_str, pct, snr_val, pt, mc_i, n_mc, rt, ...
                datestr(seconds(elapsed), 'MM:SS'), datestr(seconds(eta), 'MM:SS'));
        end
    end
    fprintf('\n');
end
fprintf('\n');

% 每 SNR 点取中位数 (稳健, 抗野值)
rmse_R_med     = nanmedian(rmse_R, 3);
rmse_theta_med = nanmedian(rmse_theta, 3);
rmse_v_med     = nanmedian(rmse_v, 3);

% ---- 5. 保存结果 ----
results = struct();
results.snr_list      = snr_list;
results.precoders     = {precoders};
results.n_mc          = n_mc;
results.rmse_R        = rmse_R;
results.rmse_theta    = rmse_theta;
results.rmse_v        = rmse_v;
results.rmse_R_med    = rmse_R_med;
results.rmse_theta_med= rmse_theta_med;
results.rmse_v_med    = rmse_v_med;
results.params_summary = struct(...
    'Nt', Nt_total, 'Nr', Nr_total, 'Ns', params.N, 'L', params.K, ...
    'K_stream', params.K_stream);
results.total_runtime = toc(t_all);

save('task5_rmse_vs_snr_results.mat', '-struct', 'results', '-v7.3');
fprintf('结果已保存: task5_rmse_vs_snr_results.mat\n');
fprintf('总耗时: %.1f 分钟\n', results.total_runtime / 60);

% ---- 6. 绘图 (Nature 风格) ----
fprintf('\n--- 绘制 ---\n');

% 颜色方案 (Nature 友好: 红/蓝/绿, 色盲友好)
colors = {[0.8 0.2 0.2], [0.2 0.4 0.8], [0.2 0.7 0.3]};  % ZF/Nullspace/Lagrange
line_styles = {'-', '--', '-.'};
markers     = {'o', 's', '^'};
prec_labels = {'ZF', 'Nullspace', 'Lagrange'};

% 通用 Nature 风格设置
nature_fontsize  = 10;
nature_linewidth = 1.2;
nature_markersize = 5;

plot_rmse_vs_snr(snr_list, rmse_R_med,     prec_labels, colors, line_styles, markers, ...
    'SNR (dB)', 'Range RMSE (m)', 'Range Estimation', ...
    'task5_fig_range', nature_fontsize, nature_linewidth, nature_markersize);

plot_rmse_vs_snr(snr_list, rmse_theta_med, prec_labels, colors, line_styles, markers, ...
    'SNR (dB)', 'Angle RMSE (deg)', 'Angle Estimation', ...
    'task5_fig_angle', nature_fontsize, nature_linewidth, nature_markersize);

plot_rmse_vs_snr(snr_list, rmse_v_med,     prec_labels, colors, line_styles, markers, ...
    'SNR (dB)', 'Velocity RMSE (m/s)', 'Velocity Estimation', ...
    'task5_fig_velocity', nature_fontsize, nature_linewidth, nature_markersize);

fprintf('三张图已生成: task5_fig_range.png / task5_fig_angle.png / task5_fig_velocity.png\n');
fprintf('============================================================\n');
fprintf('全部完成! 总耗时 %.1f 分钟\n', results.total_runtime / 60);
fprintf('============================================================\n');

% =========================================================================
function plot_rmse_vs_snr(snr_list, rmse_med, prec_labels, colors, ...
    line_styles, markers, xlabel_str, ylabel_str, title_str, ...
    save_name, fontsize, lw, ms)
% =========================================================================
    figure('Position', [100, 100, 600, 450], 'Color', 'w');
    hold on;

    n_prec = size(rmse_med, 1);
    h = zeros(1, n_prec);
    for i = 1:n_prec
        y = rmse_med(i, :);
        % 跳过 NaN
        valid = ~isnan(y);
        h(i) = plot(snr_list(valid), y(valid), ...
            'Color', colors{i}, 'LineStyle', line_styles{i}, ...
            'LineWidth', lw, 'Marker', markers{i}, ...
            'MarkerSize', ms, 'MarkerFaceColor', colors{i});
    end

    hold off;

    % --- Nature 风格美化 ---
    ax = gca;
    ax.FontSize = fontsize;
    ax.FontName = 'Helvetica';
    ax.LineWidth = 0.8;
    ax.TickDir = 'out';
    ax.TickLength = [0.005 0.005];
    ax.Box = 'off';

    % 纵轴: 科学计数法 (10^0 ~ 10^2)
    ax.YScale = 'log';
    % 手动设置刻度为 10 的整数次幂
    y_min = min(rmse_med(rmse_med > 0 & ~isnan(rmse_med)));
    y_max = max(rmse_med(~isnan(rmse_med)));
    if isempty(y_min), y_min = 1e-3; end
    if isempty(y_max), y_max = 10; end
    y_exp_lo = floor(log10(y_min));
    y_exp_hi = ceil(log10(y_max));
    y_ticks = 10.^(y_exp_lo:y_exp_hi);
    ax.YTick = y_ticks;
    % 科学计数法标签
    y_labels = arrayfun(@(e) sprintf('10^{%d}', e), y_exp_lo:y_exp_hi, 'UniformOutput', false);
    ax.YTickLabel = y_labels;
    ax.YLim = [10^(y_exp_lo - 0.3), 10^(y_exp_hi + 0.3)];

    % 横轴
    xlabel(xlabel_str, 'FontSize', fontsize + 1, 'FontName', 'Helvetica');
    ylabel(ylabel_str, 'FontSize', fontsize + 1, 'FontName', 'Helvetica');
    title(title_str, 'FontSize', fontsize + 2, 'FontName', 'Helvetica', 'FontWeight', 'normal');

    % 图例
    lgd = legend(h, prec_labels, 'Location', 'northeast');
    lgd.FontSize = fontsize - 1;
    lgd.FontName = 'Helvetica';
    lgd.Box = 'off';

    % 网格
    grid on;
    ax.GridAlpha = 0.15;
    ax.MinorGridAlpha = 0.05;

    % 保存
    saveas(gcf, [save_name, '.png']);
    saveas(gcf, [save_name, '.fig']);
    fprintf('  → %s.png / .fig\n', save_name);
end
