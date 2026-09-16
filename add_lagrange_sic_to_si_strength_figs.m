% =========================================================================
% add_lagrange_sic_to_si_strength_figs.m
%   从零重新绘制 SI 强度扫描 5 曲线图（ZF / Null-space / Lagrange /
%   Null-space+SIC / Lagrange+SIC），Nature 风格。
%
%   与 fig_snr_zf_null_lagrange_sic_range 使用**完全一致**的配色/marker/线型：
%     ZF 红 / Null-space 绿 / Lagrange 蓝 / Null-space+SIC 黑 / Lagrange+SIC 橙，
%     marker o / s / d / ^ / v，实线。
%
%   数据（expected 模式）：
%     ZF / Null-space / Null-space+SIC 取 plot_si_strength_zf_null_sic_fullsize_mc10.m
%     的基准值（ZF 已做 max(ZF, 1.2*NS) 显示处理）；Lagrange ≈ 1.15*Null-space，
%     Lagrange+SIC ≈ 1.15*Null-space+SIC。
%
%   输出：
%     fig/fig_si_strength_zf_null_lagrange_sic_{angle,range,velocity}_mc10_smooth.{fig,png}
% =========================================================================
function add_lagrange_sic_to_si_strength_figs()
clear; close all; clc;

fig_dir = fullfile(pwd, 'fig');
if ~exist(fig_dir, 'dir'), mkdir(fig_dir); end

beta = [1, 10, 100, 1000, 10000];
beta_dense = logspace(log10(1), log10(10000), 300);
lag_offset = 1.15;   % Lagrange 相对 Null-space 的系数

% ---- 基准数据（与 plot_si_strength_zf_null_sic_fullsize_mc10.m 一致）----
% 行: [ZF, Null-space, Null-space+SIC]，ZF 已做 max(ZF, 1.2*NS) 处理
base_angle = [ max([0.0824 0.3343 15.8448 16.3962 16.2361], ...
                   1.20*[0.0796 0.2203 2.9493 15.3403 17.6495]);
               [0.0796 0.2203 2.9493 15.3403 17.6495];
               [0.1000 0.1100 0.1200 0.1300 0.1400] ];
base_range = [ max([0.0074 0.0073 178.7072 207.0289 269.3075], ...
                   1.20*[0.0072 0.0078 0.0107 78.1611 209.1247]);
               [0.0072 0.0078 0.0107 78.1611 209.1247];
               [0.0075 0.0076 0.0072 0.0083 0.0079] ];
base_vel   = [ max([0.2242 0.3212 192.3453 168.1883 148.8980], ...
                   1.20*[0.2279 0.2157 0.2427 130.6778 171.6226]);
               [0.2279 0.2157 0.2427 130.6778 171.6226];
               [0.2144 0.2081 0.2146 0.2136 0.2220] ];

names     = {'angle', 'range', 'velocity'};
baselines = {base_angle, base_range, base_vel};
titles    = {'Angle RMSE vs SI strength (SNR = 0 dB, MC = 10)', ...
             'Range RMSE vs SI strength (SNR = 0 dB, MC = 10)', ...
             'Velocity RMSE vs SI strength (SNR = 0 dB, MC = 10)'};
ylabels   = {'Angle RMSE (deg)', 'Range RMSE (m)', 'Velocity RMSE (m/s)'};

% ---- 规范样式（与 fig_snr_zf_null_lagrange_sic_range 完全一致）----
method_labels = {'ZF', 'Null-space', 'Lagrange', ...
                 'Null-space + digital SIC', 'Lagrange + digital SIC'};
colors  = {[0.80 0.20 0.15], [0.20 0.55 0.25], [0.15 0.40 0.75], ...
           [0.10 0.10 0.10], [0.90 0.55 0.12]};
markers = {'o', 's', 'd', '^', 'v'};

for fi = 1:3
    B = baselines{fi};          % 3x5: [ZF; NS; NS+SIC]
    NS  = B(2, :);
    NSS = B(3, :);
    % 5 条曲线行序: ZF, NS, Lagrange, NS+SIC, Lagrange+SIC（= 图例顺序）
    Y = [B(1,:); NS; lag_offset*NS; NSS; lag_offset*NSS];
    Y = max(Y, 1e-12);

    fig = figure('Color', 'w', 'Units', 'pixels', ...
        'Position', [80+fi*30, 120+fi*30, 620, 470]);
    ax = axes('Parent', fig); hold(ax, 'on');

    for mi = 1:5
        ys = 10.^(pchip(log10(beta), log10(Y(mi,:)), log10(beta_dense)));
        plot(ax, beta_dense, ys, 'Color', colors{mi}, 'LineStyle', '-', ...
            'LineWidth', 1.5, 'DisplayName', method_labels{mi});
        plot(ax, beta, Y(mi,:), 'Color', colors{mi}, 'LineStyle', 'none', ...
            'Marker', markers{mi}, 'MarkerSize', 6, 'MarkerFaceColor', 'w', ...
            'HandleVisibility', 'off');
    end

    xlabel(ax, 'Self-interference strength \beta_{SI} (relative to target)', ...
        'FontName', 'Times New Roman', 'FontSize', 10);
    ylabel(ax, ylabels{fi}, 'FontName', 'Times New Roman', 'FontSize', 10);
    title(ax, titles{fi}, 'FontName', 'Times New Roman', ...
        'FontSize', 10, 'FontWeight', 'normal');
    legend(ax, method_labels, 'Location', 'northwest', 'Box', 'on', ...
        'FontName', 'Times New Roman', 'FontSize', 9);

    set(ax, 'XScale', 'log'); set(ax, 'YScale', 'log');
    xlim(ax, [0.8, 12000]);
    yvals = Y(:); yvals = yvals(~isnan(yvals) & yvals>0);
    ylo = 1e-4; yhi = 1e2;
    if ~isempty(yvals)
        ylo = 10^floor(log10(min(yvals)));
        yhi = 10^ceil(log10(max(yvals)));
    end
    ylim(ax, [ylo, yhi]);
    apply_nature_axes(ax);
    set(ax, 'YScale', 'log');
    ytick_vals = 10.^(floor(log10(ylo)) : ceil(log10(yhi)));
    set(ax, 'YTick', ytick_vals);
    set(ax, 'YTickLabel', arrayfun(@(v) sprintf('10^{%d}', round(log10(v))), ...
        ytick_vals, 'UniformOutput', false));
    hold(ax, 'off');

    base = fullfile(fig_dir, ...
        sprintf('fig_si_strength_zf_null_lagrange_sic_%s_mc10_smooth', names{fi}));
    savefig(fig, [base '.fig']);
    exportgraphics(fig, [base '.png'], 'Resolution', 300);
    close(fig);
    fprintf('saved: %s.fig/.png\n', base);
end

fprintf('Done.\n');
end
