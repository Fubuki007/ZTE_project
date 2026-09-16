% =========================================================================
% plot_output_snr_ns_l_zf_null_nosic.m
%   只画 ZF 和 Null-space 两条曲线，去掉 digital SIC 曲线
%   数据使用之前完整版跑出的结果
%   输出 .fig + .png
% =========================================================================
function plot_output_snr_ns_l_zf_null_nosic()
close all; clc;

fig_dir = fullfile(pwd, 'fig');
if ~exist(fig_dir, 'dir'), mkdir(fig_dir); end

% ---- (b) subcarriers data ----
ns_x = [512, 1024, 2048, 3168, 6336];
ns_zf = [41.20, 43.11, 46.48, 48.73, 50.87];
ns_ns = [52.34, 55.33, 58.36, 60.26, 63.22];

% ---- (c) CPI length data ----
L_x = [16, 32, 64, 128, 256];
L_zf = [37.32, 39.69, 42.45, 46.38, 48.73];
L_ns = [48.26, 51.22, 54.23, 57.29, 60.26];

% ---- 画图 ----
plot_two(ns_x, [ns_zf; ns_ns], ...
    'The number of subcarriers', ...
    '(b) Impact of the number of subcarriers (beamforming)', ...
    fullfile(fig_dir, 'fig_output_snr_vs_subcarriers_zf_null_nosic'));

plot_two(L_x, [L_zf; L_ns], ...
    'The CPI length', ...
    '(c) Impact of CPI length (beamforming)', ...
    fullfile(fig_dir, 'fig_output_snr_vs_cpi_length_zf_null_nosic'));

fprintf('Done. Saved two no-SIC figures to fig/\n');
end

function plot_two(x, y_mat, xlabel_str, title_str, base_path)
fig = figure('Color', 'w', 'Units', 'pixels', ...
    'Position', [100, 140, 620, 470], 'Name', title_str);
ax = axes('Parent', fig);
hold(ax, 'on');

colors    = {[0.85 0.15 0.12], [0.00 0.45 0.74]};
markers   = {'o', 's'};
linestyles = {'-', '--'};
labels    = {'ZF', 'Null-space'};

for k = 1:size(y_mat, 1)
    plot(ax, x, y_mat(k, :), ...
        'Color', colors{k}, ...
        'Marker', markers{k}, ...
        'LineStyle', linestyles{k}, ...
        'MarkerSize', 6, ...
        'LineWidth', 1.4, ...
        'MarkerFaceColor', 'w', ...
        'DisplayName', labels{k});
end

xlabel(ax, xlabel_str, 'FontName', 'Times New Roman', 'FontSize', 10);
ylabel(ax, 'Output-SNR (dB)', 'FontName', 'Times New Roman', 'FontSize', 10);
title(ax, title_str, 'FontName', 'Times New Roman', ...
    'FontSize', 10, 'FontWeight', 'normal');
set(ax, 'XScale', 'log');
set(ax, 'XTick', [10, 100, 1000, 10000]);
xlim(ax, [min(x), max(x)]);
y_finite = y_mat(isfinite(y_mat));
if ~isempty(y_finite)
    ylo = floor(min(y_finite)/10)*10;
    yhi = ceil(max(y_finite)/10)*10;
    if yhi - ylo < 10, yhi = ylo + 10; end
    ylim(ax, [ylo, yhi]);
    set(ax, 'YTick', ylo:10:yhi);
end
legend(ax, labels, 'Location', 'southeast', 'Box', 'on');
apply_nature_axes(ax);
hold(ax, 'off');

savefig(fig, [base_path '.fig']);
exportgraphics(fig, [base_path '.png'], 'Resolution', 300);
close(fig);
fprintf('  saved: %s.fig/.png\n', base_path);
end
