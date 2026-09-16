% =========================================================================
% draw_angle_rmse_snr_si_fig.m
% 用 MATLAB 重新绘制“Angle RMSE vs SNR — SI Suppression Comparison”
% 并输出 .fig / .png / .eps
%
% 数据说明：
%   原始 ZF 在 -30~-10 dB 有“先下降后上升”的非物理趋势，这里按用户要求
%   做单调化修正：cummin() 保证 RMSE 不随 SNR 增大而回升；
%   再用 pchip 在 log10(RMSE) 域插值，保证曲线平滑无突刺。
%
% 输出：
%   fig/angle_rmse_vs_snr_si_suppression.fig
%   fig/angle_rmse_vs_snr_si_suppression.png
%   fig/angle_rmse_vs_snr_si_suppression.eps
% =========================================================================
clear; close all; clc;

% ---- 原始数据 ----
snr = -60:5:30;
zf_raw = [41.2593, 41.8659, 38.2143, 40.9728, 38.6473, 22.4889, 15.3584, ...
          12.0466, 10.3894, 10.6764, 14.3454, 15.8412, 16.4530, 16.6748, ...
          16.6567, 16.6882, 16.7008, 16.7086, 16.7050];
ns_raw = [41.3002, 43.5870, 41.8433, 34.3934, 38.6778, 22.6734, 12.3846, ...
          5.9106,  2.1370,  0.9749,  0.5235,  0.3219,  0.1875,  0.1539, ...
          0.1418,  0.1260,  0.1189,  0.1180,  0.1184];
lag_raw = [42.7098, 38.7181, 41.9595, 33.3748, 34.4338, 25.7222, 14.6590, ...
           5.6996,  2.2272,  0.9409,  0.5744,  0.3266,  0.1854,  0.0817, ...
           0.0805,  0.0620,  0.0609,  0.0606,  0.0609];

% ---- 单调化修正（不再出现先下降后上升） ----
zf = cummin(zf_raw);
ns = cummin(ns_raw);
lag = cummin(lag_raw);

% ---- 平滑插值 ----
snr_dense = linspace(snr(1), snr(end), 400);
zf_sm = 10.^(pchip(snr, log10(zf), snr_dense));
ns_sm = 10.^(pchip(snr, log10(ns), snr_dense));
lag_sm = 10.^(pchip(snr, log10(lag), snr_dense));

% ---- 图窗 ----
fig = figure('Color', 'w', 'Units', 'pixels', 'Position', [80 80 525 389]);
ax = axes('Parent', fig);
hold(ax, 'on');

colors = {[0.902 0.294 0.208], [0.302 0.733 0.835], [0.200 0.627 0.173]};
markers = {'o', 's', '^'};
linestyles = {'-', '--', '-.'};
labels = {'传统 ZF (不抑制)', '零空间法', '拉格朗日法'};

smooth_data = {zf_sm, ns_sm, lag_sm};
raw_data    = {zf, ns, lag};

% 先画平滑线，再画原始修正点的空心 marker（不进入 legend）
for k = 1:3
    plot(ax, snr_dense, smooth_data{k}, ...
        'Color', colors{k}, 'LineStyle', linestyles{k}, ...
        'LineWidth', 1.4, 'DisplayName', labels{k});
    plot(ax, snr, raw_data{k}, ...
        'Color', colors{k}, 'LineStyle', 'none', ...
        'Marker', markers{k}, 'MarkerSize', 5, ...
        'MarkerFaceColor', 'w', 'HandleVisibility', 'off');
end

% ---- 坐标轴与标签 ----
ax.XScale = 'linear';
ax.YScale = 'log';
ax.XLim = [-63, 33];
ax.YLim = [0.04, 100];
ax.XTick = -60:10:30;
ax.YTick = [0.1, 1, 10, 100];
ax.YTickLabel = {'10^{-1}', '10^{0}', '10^{1}', '10^{2}'};
ax.Box = 'on';
ax.TickDir = 'in';
ax.XMinorTick = 'on';
ax.YMinorTick = 'on';
ax.XGrid = 'on';
ax.YGrid = 'on';
ax.GridAlpha = 0.18;
ax.MinorGridAlpha = 0.12;
ax.FontName = 'Times New Roman';
ax.FontSize = 9;

xlabel(ax, 'Input SNR (dB)', 'FontName', 'Times New Roman', 'FontSize', 10);
ylabel(ax, 'Angle RMSE (°)', 'FontName', 'Times New Roman', 'FontSize', 10);
title(ax, 'Angle RMSE vs SNR  --  SI Suppression Comparison (L=256, MC=100)', ...
    'FontName', 'Times New Roman', 'FontSize', 9, 'FontWeight', 'normal');

% ---- 图例放在图内右上角，避免外置留白 ----
leg = legend(ax, labels, 'Location', 'northeast', 'Box', 'on');
leg.FontName = 'Microsoft YaHei';
leg.FontSize = 8;
leg.EdgeColor = [0.35 0.35 0.35];

hold(ax, 'off');

% ---- 输出 ----
fig_dir = fullfile(pwd, 'fig');
if ~exist(fig_dir, 'dir'), mkdir(fig_dir); end

base = fullfile(fig_dir, 'angle_rmse_vs_snr_si_suppression');
savefig(fig, [base '.fig']);
exportgraphics(fig, [base '.png'], 'Resolution', 300);
print(fig, [base '.eps'], '-depsc2', '-r300');

fprintf('已保存:\n  %s.fig\n  %s.png\n  %s.eps\n', base, base, base);
fprintf('修正后的 ZF 高 SNR 段保持 %.4f°，不再回升。\n', zf(end));
