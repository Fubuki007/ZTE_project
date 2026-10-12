% =========================================================================
% plot_output_snr_ns_l_nullspace_sic_quick.m
%   用快速测试结果画两张 Output-SNR 图：
%     (b) Ns sweep
%     (c) L sweep
%   三条曲线：ZF / Null-space / Null-space + digital SIC
% =========================================================================
function plot_output_snr_ns_l_nullspace_sic_quick()
close all; clc;
fig_dir = fullfile(pwd, 'fig');
if ~exist(fig_dir, 'dir'), mkdir(fig_dir); end

% ---- Ns sweep data ----
ns_x = [512, 1024, 2048];
ns_zf = [46.58, 49.53, 52.56];
ns_ns = [48.27, 51.23, 54.28];
ns_sic = [48.28, 51.24, 54.27];

% ---- L sweep data ----
L_x = [16, 32, 64, 128];
L_zf = [43.54, 46.52, 49.47, 52.56];
L_ns = [45.21, 48.22, 51.21, 54.27];
L_sic = [45.26, 48.27, 51.21, 54.30];

plot_one(ns_x, [ns_zf; ns_ns; ns_sic], ...
    'The number of subcarriers', ...
    '(b) Impact of the number of subcarriers (quick test)', ...
    fullfile(fig_dir, 'fig_output_snr_vs_subcarriers_zf_null_sic_quick'));
plot_one(L_x, [L_zf; L_ns; L_sic], ...
    'The CPI length', ...
    '(c) Impact of CPI length (beamforming) (quick test)', ...
    fullfile(fig_dir, 'fig_output_snr_vs_cpi_length_zf_null_sic_quick'));

fprintf('Done. Saved two quick-test figures to fig/\n');
end

function plot_one(x, y_mat, xlabel_str, title_str, base_path)
fig = figure('Color', 'w', 'Units', 'pixels', ...
    'Position', [100, 140, 620, 470], 'Name', title_str);
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
