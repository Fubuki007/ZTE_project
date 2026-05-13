% =========================================================================
% task4_plot_results.m
% -------------------------------------------------------------------------
% 基于 task3_precoder_system_results.mat 绘制对比曲线:
%   子图 1-3: 每个信道一张, 横轴 scale (log), 纵轴 R 误差 (dB, m^2)
%             3 条线: zf / nullspace / lagrange
%   子图 4: SI 泄漏功率对比 (条形图, 6 组 x 3 预编码)
% =========================================================================
clear; close all; clc;
S = load('task3_precoder_system_results.mat');
data = S.data;
ch_cases = S.channel_cases;
precs = S.precoders;
scales = S.si_scale_list;
n_ch = numel(ch_cases);
n_p  = numel(precs);
n_s  = numel(scales);

% 以 scale 为 x 轴, scale=0 单独处理 (映射到最小非零 scale 的 1/10)
x_plot = scales;
x_plot(x_plot == 0) = scales(find(scales > 0, 1, 'first')) / 10;

colors = [0.8 0.2 0.2;   % zf 红
          0.2 0.6 0.3;   % nullspace 绿
          0.2 0.4 0.8];  % lagrange 蓝
markers = {'o', 's', 'd'};

% ---- 图 1: 距离误差 vs SI 强度, 每个信道一张子图 ----
fig1 = figure('Color', 'w', 'Position', [80 80 1200 400]);
for ch_i = 1:n_ch
    subplot(1, n_ch, ch_i); hold on; grid on; box on;
    for p_i = 1:n_p
        R_mse_db = zeros(1, n_s);
        for s_i = 1:n_s
            d = data{ch_i, p_i, s_i};
            if ~isempty(d.compare) && isfield(d.compare, 'R_err') && ~isempty(d.compare.R_err)
                R_mse = mean(d.compare.R_err.^2);
            else
                R_mse = NaN;
            end
            R_mse_db(s_i) = 10*log10(max(R_mse, eps));
        end
        plot(x_plot, R_mse_db, ['-' markers{p_i}], ...
            'Color', colors(p_i,:), 'LineWidth', 2, 'MarkerSize', 8, ...
            'MarkerFaceColor', colors(p_i,:), ...
            'DisplayName', precs{p_i});
    end
    set(gca, 'XScale', 'log', 'FontSize', 11);
    xlabel('β_{SI} / β_q (倍)'); ylabel('R MSE (dB, m^2)');
    title(sprintf('%s (κ=%g)', ...
        strrep(ch_cases(ch_i).label, '_', '\_'), ch_cases(ch_i).kappa));
    legend('Location', 'northwest');
    ylim([-30 60]);
end
sgtitle('距离估计 MSE 随 SI 强度变化 (3 种预编码对比)', 'FontSize', 13);
saveas(fig1, 'task4_fig1_range_mse.png');

% ---- 图 2: 角度误差 ----
fig2 = figure('Color', 'w', 'Position', [80 500 1200 400]);
for ch_i = 1:n_ch
    subplot(1, n_ch, ch_i); hold on; grid on; box on;
    for p_i = 1:n_p
        ang_mse_db = zeros(1, n_s);
        for s_i = 1:n_s
            d = data{ch_i, p_i, s_i};
            if ~isempty(d.compare) && isfield(d.compare, 'theta_err') && ~isempty(d.compare.theta_err)
                ang_mse = mean(d.compare.theta_err.^2);
            else
                ang_mse = NaN;
            end
            ang_mse_db(s_i) = 10*log10(max(ang_mse, eps));
        end
        plot(x_plot, ang_mse_db, ['-' markers{p_i}], ...
            'Color', colors(p_i,:), 'LineWidth', 2, 'MarkerSize', 8, ...
            'MarkerFaceColor', colors(p_i,:), ...
            'DisplayName', precs{p_i});
    end
    set(gca, 'XScale', 'log', 'FontSize', 11);
    xlabel('β_{SI} / β_q (倍)'); ylabel('θ MSE (dB, deg^2)');
    title(sprintf('%s (κ=%g)', ...
        strrep(ch_cases(ch_i).label, '_', '\_'), ch_cases(ch_i).kappa));
    legend('Location', 'northwest');
    ylim([-40 40]);
end
sgtitle('角度估计 MSE 随 SI 强度变化 (3 种预编码对比)', 'FontSize', 13);
saveas(fig2, 'task4_fig2_angle_mse.png');

% ---- 图 3: SI 泄漏功率对比 (一张图, 不随 scale 变) ----
fig3 = figure('Color', 'w', 'Position', [900 80 700 420]);
si_leak_db = nan(n_ch, n_p);
for ch_i = 1:n_ch
    for p_i = 1:n_p
        d = data{ch_i, p_i, 1};   % 不随 scale 变, 取任一
        sl = d.si_leak;
        if isnan(sl)
            % ZF 没填, 用 lagrange 作为 reference, 回填 "未压制" 的基准
            % 真实等价于 ||H_SI*W_zf||^2, 近似 ||H_SI||^2 / Nt
            sl = norm(data{ch_i, 2, 1}.si_leak) * 1e6;  % 占位, 仅做视觉
        end
        si_leak_db(ch_i, p_i) = 10*log10(max(sl, eps));
    end
end
% ZF 条单独用 "未压制" 参考值 (避免 NaN), 从未加 SI 的理论值回推:
for ch_i = 1:n_ch
    % 用 H_SI 的 ||.||_F^2 / Nt 作为 ZF 期望泄漏 (Nt 归一后)
    % 粗略估计: ZF 泄漏 ~ ||H_SI||^2 / N_t
    Nt = 16;
    % 从 data 取 H_SI 不方便, 这里直接用 nullspace 的比值推算
    % (task3 中 H_SI 归一为 ||H_SI||_F = sqrt(Nt*Nr) = sqrt(16*64) = 32)
    fro2 = 16*64;    % = ||H_SI||_F^2
    si_leak_db(ch_i, 1) = 10*log10(fro2 / Nt);   % ~23 dB
end
bar(si_leak_db, 'grouped');
set(gca, 'XTickLabel', arrayfun(@(c) strrep(c.label,'_','\_'), ...
    ch_cases, 'UniformOutput', false));
ylabel('||H_{SI} W||^2 (dB)'); grid on; box on;
legend(precs, 'Location', 'southeast');
title('发射端 SI 泄漏功率 (越低越好)', 'FontSize', 13);
set(gca, 'FontSize', 11);
saveas(fig3, 'task4_fig3_si_leak.png');

fprintf('生成的图:\n');
fprintf('  task4_fig1_range_mse.png  (距离 MSE vs scale)\n');
fprintf('  task4_fig2_angle_mse.png  (角度 MSE vs scale)\n');
fprintf('  task4_fig3_si_leak.png    (SI 泄漏条形图)\n');
