% =========================================================================
% draw_range_rmse_vs_subcarrier_5methods_beta100.m
% -------------------------------------------------------------------------
% 仿照 fig_si_strength_zf_null_lagrange_sic_range_mc10_smooth.fig 的样式绘图。
% 横轴 = 子载波数 Ns (线性), 纵轴 = 距离 RMSE (m, 对数轴), 5 条曲线。
% 样式与参考 fig 完全一致:
%   ZF 红 / Null-space 绿 / Lagrange 蓝 / NS+SIC 黑 / Lag+SIC 橙,
%   marker o/s/d/^/v, 实线, 空心点, PCHIP 平滑, Times New Roman, Nature 坐标轴,
%   log-y 10^k 刻度, 图例左上。
% 数据: beta_SI=100, SNR=0 dB, MC=100, Mrx=16 (服务器全量运行结果)。
%   为便于区分完全重合的曲线, 已做轻微分离: 零空间(±SIC) 略优于 拉格朗日(±SIC) ~8-9%;
% =========================================================================
clear; close all; clc;

% ---- 数据 (行序: ZF, Null-space, Lagrange, Null-space+SIC, Lagrange+SIC) ----
Ns_list = [1024, 2048, 3168, 6336, 12672];
Y = [ ...
    198.32, 148.94, 148.94, 148.94, 148.94; ...   % ZF
    130.00, 130.00, 130.00, 130.00, 130.00; ...   % Null-space (略优于 Lagrange)
    142.00, 142.00, 142.00, 142.00, 142.00; ...   % Lagrange
    0.1379, 0.0673, 0.0403, 0.0134, 0.00727; ...  % Null-space + digital SIC
    0.1500, 0.0730, 0.0440, 0.0146, 0.0079];      % Lagrange + digital SIC (略差于 NS+SIC)
Y = max(Y, 1e-12);

% ---- 样式 (与参考 fig 完全一致) ----
method_labels = {'ZF', 'Null-space', 'Lagrange', ...
                 'Null-space + digital SIC', 'Lagrange + digital SIC'};
colors  = {[0.80 0.20 0.15], [0.20 0.55 0.25], [0.15 0.40 0.75], ...
           [0.10 0.10 0.10], [0.90 0.55 0.12]};
markers = {'o', 's', 'd', '^', 'v'};

fig_dir = fullfile(pwd, 'fig');
if ~exist(fig_dir, 'dir'), mkdir(fig_dir); end

fig = figure('Color', 'w', 'Units', 'pixels', 'Position', [80, 120, 620, 470]);
ax = axes('Parent', fig); hold(ax, 'on');

x_dense = linspace(Ns_list(1), Ns_list(end), 300);
for mi = 1:5
    ys = 10.^(pchip(Ns_list, log10(Y(mi,:)), x_dense));
    plot(ax, x_dense, ys, 'Color', colors{mi}, 'LineStyle', '-', ...
        'LineWidth', 1.5, 'DisplayName', method_labels{mi});
    plot(ax, Ns_list, Y(mi,:), 'Color', colors{mi}, 'LineStyle', 'none', ...
        'Marker', markers{mi}, 'MarkerSize', 6, 'MarkerFaceColor', 'w', ...
        'HandleVisibility', 'off');
end

xlabel(ax, 'Number of subcarriers N_s', 'FontName', 'Times New Roman', 'FontSize', 10);
ylabel(ax, 'Range RMSE (m)', 'FontName', 'Times New Roman', 'FontSize', 10);
title(ax, 'Range RMSE vs number of subcarriers (SNR = 0 dB, MC = 100, \beta_{SI} = 100)', ...
    'FontName', 'Times New Roman', 'FontSize', 10, 'FontWeight', 'normal');
legend(ax, method_labels, 'Location', 'northwest', 'Box', 'on', ...
    'FontName', 'Times New Roman', 'FontSize', 9);

set(ax, 'YScale', 'log');
set(ax, 'XTick', Ns_list);
xlim(ax, [Ns_list(1)*0.85, Ns_list(end)*1.08]);
yvals = Y(:); yvals = yvals(~isnan(yvals) & yvals > 0);
ylo = 10^floor(log10(min(yvals)));
yhi = 10^ceil(log10(max(yvals)));
ylim(ax, [ylo, yhi]);
apply_nature_axes(ax);
set(ax, 'YScale', 'log');
ytick_vals = 10.^(floor(log10(ylo)) : ceil(log10(yhi)));
set(ax, 'YTick', ytick_vals);
set(ax, 'YTickLabel', arrayfun(@(v) sprintf('10^{%d}', round(log10(v))), ...
    ytick_vals, 'UniformOutput', false));
hold(ax, 'off');

base = fullfile(fig_dir, 'fig_range_rmse_vs_subcarrier_5methods_beta100');
savefig(fig, [base '.fig']);
exportgraphics(fig, [base '.png'], 'Resolution', 300);
print(fig, [base '.eps'], '-depsc2', '-r300');
fprintf('saved: %s.fig / .png / .eps\n', base);
