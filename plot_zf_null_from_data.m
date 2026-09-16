% =========================================================================
% plot_zf_null_from_data.m
%   用已经跑出来的数据画 ZF vs Null-space 对比图，保存 .fig 和 .png
%
%   数据来源:
%     - task_execution_time_zf_null 运行输出
%     - task_output_snr_zf_null 运行输出
%
%   输出:
%     fig/fig_output_snr_vs_mrx_zf_null.fig/.png
%     fig/fig_output_snr_vs_subcarriers_zf_null.fig/.png
%     fig/fig_output_snr_vs_cpi_length_zf_null.fig/.png
%     fig/execution_time_vs_cpi_length_zf_null.fig/.png
%     fig/execution_time_vs_subcarriers_zf_null.fig/.png
%
%   运行:
%     matlab -batch "plot_zf_null_from_data"
% =========================================================================
function plot_zf_null_from_data()
close all; clc;

fig_dir = fullfile(pwd, 'fig');
if ~exist(fig_dir, 'dir'), mkdir(fig_dir); end

% =========================================================================
% 1. Output-SNR 数据
% =========================================================================
snr_mrx_x = [4, 16, 36, 64];
snr_mrx_zf = [49.70, 49.73, 49.72, 49.70];
snr_mrx_ns = [49.70, 49.72, 49.71, 49.70];

snr_ns_x = [512, 1024, 2048, 3168, 6336];
snr_ns_zf = [42.14, 44.12, 47.49, 49.71, 51.89];
snr_ns_ns = [42.15, 44.10, 47.46, 49.71, 51.88];

snr_L_x = [16, 32, 64, 128, 256];
snr_L_zf = [38.41, 40.71, 43.41, 47.38, 49.71];
snr_L_ns = [38.38, 40.72, 43.42, 47.36, 49.71];

% =========================================================================
% 2. Execution-time 数据
% =========================================================================
time_ns_x = [512, 1024, 2048, 3168, 6336];
time_ns_zf = [0.016215, 0.024088, 0.035209, 0.054179, 0.081429];
time_ns_ns = [0.019008, 0.029603, 0.041307, 0.058088, 0.084167];

time_L_x = [16, 32, 64, 128, 256];
time_L_zf = [0.017344, 0.032303, 0.055614, 0.089477, 0.142280];
time_L_ns = [0.015394, 0.032762, 0.055975, 0.094899, 0.165414];

% =========================================================================
% 3. Output-SNR 图
% =========================================================================
plot_output_snr(snr_mrx_x, [snr_mrx_zf; snr_mrx_ns], ...
    'The number of receive antennas', ...
    '(a) Impact of the number of receive antennas', ...
    fullfile(fig_dir, 'fig_output_snr_vs_mrx_zf_null'), 1);

plot_output_snr(snr_ns_x, [snr_ns_zf; snr_ns_ns], ...
    'The number of subcarriers', ...
    '(b) Impact of the number of subcarriers', ...
    fullfile(fig_dir, 'fig_output_snr_vs_subcarriers_zf_null'), 2);

plot_output_snr(snr_L_x, [snr_L_zf; snr_L_ns], ...
    'The CPI length', ...
    '(c) Impact of CPI length (beamforming)', ...
    fullfile(fig_dir, 'fig_output_snr_vs_cpi_length_zf_null'), 3);

% =========================================================================
% 4. Execution-time 图
% =========================================================================
plot_execution_time(time_ns_x, [time_ns_zf; time_ns_ns], ...
    'The number of subcarriers', ...
    'Impact of the number of subcarriers', ...
    fullfile(fig_dir, 'execution_time_vs_subcarriers_zf_null'), 1);

plot_execution_time(time_L_x, [time_L_zf; time_L_ns], ...
    'CPI length', ...
    'Impact of CPI length', ...
    fullfile(fig_dir, 'execution_time_vs_cpi_length_zf_null'), 2);

fprintf('Done. Saved .fig + .png to %s\n', fig_dir);
end

% =========================================================================
function plot_output_snr(x, y_mat, x_label, title_text, base_path, fig_index)
fig = figure('Color', 'w', 'Units', 'pixels', ...
    'Position', [100 + 35*fig_index, 140 + 35*fig_index, 560, 420], ...
    'Name', title_text);
ax = axes('Parent', fig);
hold(ax, 'on');

colors    = {[0.85 0.15 0.12], [0.00 0.45 0.74]};
markers   = {'o', 's'};
linestyles = {'-', '--'};
labels    = {'ZF', 'Null-space'};

for k = 1:2
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
function plot_execution_time(x, y_mat, x_label, title_text, base_path, fig_index)
fig = figure('Color', 'w', 'Units', 'inches', ...
    'Position', [1.0 + 0.3*fig_index, 1.0 + 0.3*fig_index, 4.3, 3.35], ...
    'PaperPositionMode', 'auto', 'Visible', 'off', 'Name', title_text);
ax = axes('Parent', fig);
hold(ax, 'on');

colors    = {[0.08, 0.35, 0.52], [0.85, 0.15, 0.12]};
markers   = {'d', 's'};
linestyles = {'-', '--'};
labels    = {'ZF', 'Null-space'};

for k = 1:2
    loglog(ax, x, max(y_mat(k, :), 1e-12), ...
        'Color', colors{k}, ...
        'Marker', markers{k}, ...
        'LineStyle', linestyles{k}, ...
        'MarkerEdgeColor', colors{k}, ...
        'MarkerFaceColor', 'w', ...
        'MarkerSize', 5.2, ...
        'LineWidth', 1.35, ...
        'DisplayName', labels{k});
end

xlabel(ax, x_label, 'FontName', 'Times New Roman', 'FontSize', 10);
ylabel(ax, 'Execution time per estimation (s)', ...
    'FontName', 'Times New Roman', 'FontSize', 10);
title(ax, title_text, 'FontName', 'Times New Roman', ...
    'FontSize', 10, 'FontWeight', 'normal');
legend(ax, labels, 'Location', 'northwest', 'Box', 'on', ...
    'FontName', 'Times New Roman', 'FontSize', 8);
xticks(ax, x);
xticklabels(ax, compose('%g', x));
xlim(ax, [min(x) * 0.92, max(x) * 1.08]);
y_finite = y_mat(isfinite(y_mat));
if ~isempty(y_finite)
    ylim(ax, [min(y_finite) * 0.85, max(y_finite) * 1.15]);
end
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
