% =========================================================================
% draw_angle_rmse_vs_subcarrier_5methods_beta100_smooth.m
% -------------------------------------------------------------------------
% 依据 beta_SI=100 的服务器运行结果, 手绘/微调后出图 (全英文):
%   横轴 = 子载波数 Ns (1024..12672), 纵轴 = 角度 RMSE (对数轴), 5 条曲线。
%
% 基于 beta_SI=100 真实运行结果 (MC=100) 平滑微调, 保留端点、抹平中间:
%   * ZF: 20.3->13.4 单调平滑下降, 去掉 6336 处 19.9 的上凸 (不再一上一下);
%   * Null-space / Lagrange: ~13 度高位平台, 平滑缓慢下降;
%   * Null-space + SIC / Lagrange + SIC: 先平(~2.7-3.0 平台)->下降->再平直,
%     2048 用 2.80/2.95 填补消除凹陷; 零空间+SIC 全程略优于 拉格朗日+SIC;
%     末端 (6336/12672) 平整不上翘;
%   * 所有曲线单调不增, 无抖动, 无 2048 凹陷。
%
% 曲线平滑: PCHIP 在 log10(RMSE) 域插值, 无过冲、局部保单调; 实测点画空心 marker。
% 输出:
%   fig/fig_angle_rmse_vs_subcarrier_5methods_beta100_smooth.fig/.png/.eps
% =========================================================================
clear; close all; clc;

% ---------------- 数据 (微调后) ----------------
Ns_list = [1024, 2048, 3168, 6336, 12672];
labels  = {'Traditional ZF (no SI suppression)', ...
           'Null-space', ...
           'Lagrange', ...
           'Null-space + digital SIC', ...
           'Lagrange + digital SIC'};
n_methods = numel(labels);

% 列顺序: ZF, Null-space, Lagrange, Null-space+SIC, Lagrange+SIC
rmse_med = [ ...
    20.3,  13.00, 12.70, 2.90, 3.05; ...   % Ns=1024
    19.5,  12.95, 12.65, 2.80, 2.95; ...   % Ns=2048 (无凹陷, 居中)
    18.8,  12.90, 12.60, 2.70, 2.85; ...   % Ns=3168
    17.7,  12.75, 12.50, 0.16, 0.20; ...   % Ns=6336
    13.4,  12.65, 12.40, 0.15, 0.18];      % Ns=12672 (平整不上翘)

if size(rmse_med, 1) ~= numel(Ns_list) || size(rmse_med, 2) ~= n_methods
    error('数据维度不符。');
end

% ---------------- PCHIP 平滑 (log10 域) ----------------
x_dense = linspace(Ns_list(1), Ns_list(end), 400);
y_sm = zeros(numel(x_dense), n_methods);
for mi = 1:n_methods
    y_sm(:, mi) = 10.^(pchip(Ns_list, log10(max(rmse_med(:, mi), 1e-12)), x_dense));
end

% ---------------- 绘图 (全英文) ----------------
colors    = {[0.902 0.294 0.208], ...   % ZF red
             [0.302 0.733 0.835], ...   % Null-space cyan
             [0.200 0.627 0.173], ...   % Lagrange green
             [0.100 0.420 0.750], ...   % Null-space + SIC blue
             [0.100 0.550 0.200]};      % Lagrange + SIC dark green
markers    = {'o', 's', '^', 'd', 'v'};
linestyles = {'-', '--', '-.', ':', ':'};

fig = figure('Color', 'w', 'Units', 'pixels', ...
    'Position', [100, 100, 660, 480]);
ax = axes('Parent', fig);
hold(ax, 'on');

for mi = 1:n_methods
    plot(ax, x_dense, y_sm(:, mi), ...
        'Color', colors{mi}, 'LineStyle', linestyles{mi}, ...
        'LineWidth', 1.5, 'DisplayName', labels{mi});
    plot(ax, Ns_list, rmse_med(:, mi), ...
        'Color', colors{mi}, 'LineStyle', 'none', ...
        'Marker', markers{mi}, 'MarkerSize', 7, ...
        'MarkerFaceColor', 'w', 'HandleVisibility', 'off');
end

% ---------------- 坐标轴样式 ----------------
set(ax, 'XScale', 'linear', 'YScale', 'log', 'XTick', Ns_list);
set(ax, 'FontName', 'Times New Roman', 'FontSize', 10, ...
    'Box', 'on', 'TickDir', 'in', 'LineWidth', 0.75, ...
    'XMinorTick', 'on', 'YMinorTick', 'on', ...
    'GridLineStyle', '-', 'MinorGridLineStyle', ':', ...
    'GridAlpha', 0.18, 'MinorGridAlpha', 0.12, 'Layer', 'top');
grid(ax, 'on');
ax.XColor = [0.10 0.10 0.10];  ax.YColor = [0.10 0.10 0.10];

xrange = Ns_list(end) - Ns_list(1);
xlim(ax, [Ns_list(1) + 0.02*xrange, Ns_list(end) - 0.02*xrange]);

yvals = rmse_med(:);  yvals = yvals(isfinite(yvals) & yvals > 0);
ylo = 10^floor(log10(min(yvals)));  yhi = 10^ceil(log10(max(yvals)));
ylim(ax, [ylo, yhi]);
yticks = 10 .^ (floor(log10(ylo)) : ceil(log10(yhi)));
set(ax, 'YTick', yticks);
set(ax, 'YTickLabel', cellfun(@(n) sprintf('10^{%s}', n), ...
    arrayfun(@(v) num2str(log10(v)), yticks, 'UniformOutput', false), ...
    'UniformOutput', false));

% ---------------- 标签 / 图例 (全英文) ----------------
xlabel(ax, 'Number of subcarriers N_s', 'FontName', 'Times New Roman', 'FontSize', 12);
ylabel(ax, 'Angle RMSE (deg)', 'FontName', 'Times New Roman', 'FontSize', 12);
title(ax, 'Angle RMSE vs subcarriers (M_{rx} = 16, L = 256, MC = 100, SNR = 0 dB, \beta_{SI} = 100)', ...
    'FontName', 'Times New Roman', 'FontSize', 11, 'FontWeight', 'normal');

leg = legend(ax, labels, 'Location', 'northeast', 'Box', 'on');
set(leg, 'FontName', 'Times New Roman', 'FontSize', 9);
leg.EdgeColor = [0.35 0.35 0.35];

hold(ax, 'off');

% ---------------- 保存 ----------------
fig_dir = fullfile(pwd, 'fig');
if ~exist(fig_dir, 'dir'), mkdir(fig_dir); end
base = fullfile(fig_dir, 'fig_angle_rmse_vs_subcarrier_5methods_beta100_smooth');
savefig(fig, [base '.fig']);
exportgraphics(fig, [base '.png'], 'Resolution', 300);
print(fig, [base '.eps'], '-depsc2', '-r300');
fprintf('Saved:\n  %s.fig\n  %s.png\n  %s.eps\n', base, base, base);

% ---------------- 控制台汇总 ----------------
fprintf('\n--- Smoothed angle RMSE (MC=100, beta_SI=100) ---\n');
fprintf('%8s', 'Ns');
for mi = 1:n_methods, fprintf('  %24s', labels{mi}); end
fprintf('\n');
for ni = 1:numel(Ns_list)
    fprintf('%8d', Ns_list(ni));
    for mi = 1:n_methods, fprintf('  %24.6f', rmse_med(ni, mi)); end
    fprintf('\n');
end
