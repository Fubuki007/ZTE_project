% =========================================================================
% plot_zf_null_sic_full_from_data.m
%   用 task_output_snr_sweep_zf_null_sic_full_fixed 跑出的数据
%   画三张 Output-SNR 对比图，每条图三条曲线：
%     ZF / Null-space / Null-space + digital SIC
%   输出 .fig + .png 到 fig/ 目录
%
%   运行:
%     matlab -batch "plot_zf_null_sic_full_from_data"
% =========================================================================
function plot_zf_null_sic_full_from_data()
close all; clc;

fig_dir = fullfile(pwd, 'fig');
if ~exist(fig_dir, 'dir'), mkdir(fig_dir); end

% =========================================================================
% 数据
% =========================================================================
mrx_x  = [4, 16, 36, 64];
mrx_zf = [61.61, 60.30, 49.57, 49.65];
mrx_ns = [61.99, 53.17, 58.43, 60.92];
mrx_nssic = [49.71, 49.69, 49.72, 49.71];

ns_x  = [512, 1024, 2048, 3168, 6336];
ns_zf = [41.20, 43.11, 46.48, 48.73, 50.87];
ns_ns = [52.34, 55.33, 58.36, 60.26, 63.22];
ns_nssic = [42.16, 44.10, 47.46, 49.72, 51.87];

L_x  = [16, 32, 64, 128, 256];
L_zf = [37.32, 39.69, 42.45, 46.38, 48.73];
L_ns = [48.26, 51.22, 54.23, 57.29, 60.26];
L_nssic = [38.35, 40.71, 43.45, 47.37, 49.72];

% =========================================================================
% 出图
% =========================================================================
plot_output_snr(mrx_x, [mrx_zf; mrx_ns; mrx_nssic], ...
    'The number of receive antennas', ...
    '(a) Impact of the number of receive antennas', ...
    fullfile(fig_dir, 'fig_output_snr_vs_mrx_zf_null_sic_full'), 1);

plot_output_snr(ns_x, [ns_zf; ns_ns; ns_nssic], ...
    'The number of subcarriers', ...
    '(b) Impact of the number of subcarriers', ...
    fullfile(fig_dir, 'fig_output_snr_vs_subcarriers_zf_null_sic_full'), 2);

plot_output_snr(L_x, [L_zf; L_ns; L_nssic], ...
    'The CPI length', ...
    '(c) Impact of CPI length (beamforming)', ...
    fullfile(fig_dir, 'fig_output_snr_vs_cpi_length_zf_null_sic_full'), 3);

fprintf('Done. Saved .fig + .png to %s\n', fig_dir);
end

% =========================================================================
function plot_output_snr(x, y_mat, x_label, title_text, base_path, fig_index)
fig = figure('Color', 'w', 'Units', 'pixels', ...
    'Position', [100 + 35*fig_index, 140 + 35*fig_index, 560, 420], ...
    'Name', title_text);
ax = axes('Parent', fig);
hold(ax, 'on');

colors    = {[0.85 0.15 0.12], [0.00 0.45 0.74], [0.10 0.60 0.20]};
markers   = {'o', 's', '^'};
linestyles = {'-', '--', '-.'};
labels    = {'ZF', 'Null-space', 'Null-space + digital SIC'};

for k = 1:size(y_mat, 1)
    plot(ax, x, y_mat(k, :), ...
        'Color', colors{k}, ...
        'Marker', markers{k}, ...
        'LineStyle', linestyles{k}, ...
        'MarkerSize', 5.5, ...
        'LineWidth', 1.3, ...
        'MarkerFaceColor', 'w', ...
        'DisplayName', labels{k});
end

xlabel(ax, x_label, 'FontName', 'Times New Roman', 'FontSize', 10);
ylabel(ax, 'Output-SNR (dB)', 'FontName', 'Times New Roman', 'FontSize', 10);
title(ax, title_text, 'FontName', 'Times New Roman', ...
    'FontSize', 10, 'FontWeight', 'normal');
set(ax, 'XScale', 'log');
set(ax, 'XTick', [10, 100, 1000, 10000]);
xlim(ax, [min(x), max(x)]);

y_finite = y_mat(isfinite(y_mat));
if ~isempty(y_finite)
    ylo = floor(min(y_finite) / 10) * 10;
    yhi = ceil(max(y_finite) / 10) * 10;
    if yhi - ylo < 10, yhi = ylo + 10; end
    ylim(ax, [ylo, yhi]);
    set(ax, 'YTick', ylo:10:yhi);
end
legend(ax, labels, 'Location', 'southeast', 'Box', 'on');
apply_nature_axes(ax);
hold(ax, 'off');
save_figure(fig, base_path);
end

% =========================================================================
function save_figure(fig, base_path)
savefig(fig, [base_path '.fig']);
exportgraphics(fig, [base_path '.png'], 'Resolution', 300);
fprintf('  saved: %s.fig / .png\n', base_path);
close(fig);
end
