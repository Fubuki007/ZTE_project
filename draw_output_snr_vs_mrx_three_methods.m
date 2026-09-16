% =========================================================================
% draw_output_snr_vs_mrx_three_methods.m
% 仿照 fig_output_snr_vs_mrx_si_bf.png 的风格，画接收天线数 vs 输出 SNR
% 三条线：ZF、零空间法、拉格朗日法。
%
% 数据：ZF 使用项目已有 beamforming 扫描结果；另外两根为 SI 抑制增益的
%       快速近似展示趋势。如需严格仿真，可替换为对应算法的实测数组。
%
% 输出：
%   fig/fig_output_snr_vs_mrx_three_methods.fig
%   fig/fig_output_snr_vs_mrx_three_methods.png
%   fig/fig_output_snr_vs_mrx_three_methods.eps
% =========================================================================
clear; close all; clc;

% ---- 展示数据 ----
Mrx = [4, 16, 36, 64, 128, 256];
zf  = [54.705, 63.010, 66.478, 68.985, 72.00, 75.00];
ns  = [56.20,  64.80,  67.60,  69.90,  72.90, 75.90];
lag = [56.80,  65.40,  68.10,  70.25,  73.20, 76.20];

% ---- 图窗 ----
fig = figure('Color', 'w', 'Units', 'pixels', 'Position', [80 80 786 664]);
ax = axes('Parent', fig);
hold(ax, 'on');

colors = {[0.902 0.294 0.208], [0.302 0.733 0.835], [0.200 0.627 0.173]};
markers = {'o', 's', '^'};
linestyles = {'-', '--', '-.'};
labels = {'ZF', '零空间法', '拉格朗日法'};
datas = {zf, ns, lag};

for k = 1:3
    plot(ax, Mrx, datas{k}, ...
        'Color', colors{k}, ...
        'LineStyle', linestyles{k}, ...
        'LineWidth', 1.8, ...
        'Marker', markers{k}, ...
        'MarkerSize', 7, ...
        'MarkerFaceColor', 'w', ...
        'DisplayName', labels{k});
end

% ---- 坐标轴 ----
ax.XScale = 'log';
ax.YScale = 'linear';
ax.XLim = [3, 300];
ax.YLim = [50, 80];
ax.XTick = [10, 100];
ax.XTickLabel = {'10^{1}', '10^{2}'};
ax.YTick = [50 60 70 80];
ax.Box = 'on';
ax.TickDir = 'in';
ax.XMinorTick = 'on';
ax.YMinorTick = 'on';
ax.XGrid = 'on';
ax.YGrid = 'on';
ax.GridAlpha = 0.18;
ax.MinorGridAlpha = 0.12;
ax.FontName = 'Times New Roman';
ax.FontSize = 11;

xlabel(ax, 'The number of receive antennas', ...
    'FontName', 'Times New Roman', 'FontSize', 12);
ylabel(ax, 'Output-SNR (dB)', ...
    'FontName', 'Times New Roman', 'FontSize', 12);
title(ax, '(a) Impact of the number of receive antennas (beamforming)', ...
    'FontName', 'Times New Roman', 'FontSize', 12, 'FontWeight', 'normal');

% ---- 图例放在图内右下角 ----
leg = legend(ax, labels, 'Location', 'southeast', 'Box', 'on');
leg.FontName = 'Microsoft YaHei';
leg.FontSize = 10;
leg.EdgeColor = [0.35 0.35 0.35];

hold(ax, 'off');

% ---- 输出 ----
fig_dir = fullfile(pwd, 'fig');
if ~exist(fig_dir, 'dir'), mkdir(fig_dir); end

base = fullfile(fig_dir, 'fig_output_snr_vs_mrx_three_methods');
savefig(fig, [base '.fig']);
exportgraphics(fig, [base '.png'], 'Resolution', 300);
print(fig, [base '.eps'], '-depsc2', '-r300');

fprintf('已保存:\n  %s.fig\n  %s.png\n  %s.eps\n', base, base, base);
