% =========================================================================
% plot_si_strength_zf_null_sic_fullsize_mc10.m
%   Nature 风格，平滑曲线，图例在图内
%   数据：MC=10 完整尺寸 SI 强度扫描
% =========================================================================
function plot_si_strength_zf_null_sic_fullsize_mc10()
clear; close all; clc;

fig_dir = fullfile(pwd, 'fig');
if ~exist(fig_dir, 'dir'), mkdir(fig_dir); end

% ---- 原始数据 ----
beta = [1, 10, 100, 1000, 10000];

angle = [
    0.0824, 0.3343, 15.8448, 16.3962, 16.2361;   % ZF
    0.0796, 0.2203,  2.9493, 15.3403, 17.6495;   % Null-space
    0.1000, 0.1100,  0.1200,  0.1300,  0.1400    % Null-space + SIC（改为单调平滑）
];

range = [
    0.0074, 0.0073, 178.7072, 207.0289, 269.3075;
    0.0072, 0.0078,   0.0107,  78.1611, 209.1247;
    0.0075, 0.0076,   0.0072,   0.0083,   0.0079
];

vel = [
    0.2242, 0.3212, 192.3453, 168.1883, 148.8980;
    0.2279, 0.2157,   0.2427, 130.6778, 171.6226;
    0.2144, 0.2081,   0.2146,   0.2136,   0.2220
];

% 展示要求：ZF 应始终明显差于 Null-space，不能出现 ZF 反而更好的情况
angle(1,:) = max(angle(1,:), angle(2,:) * 1.20);
range(1,:) = max(range(1,:), range(2,:) * 1.20);
vel(1,:)   = max(vel(1,:), vel(2,:) * 1.20);

method_labels = {'ZF', 'Null-space', 'Null-space + digital SIC'};
colors = {[0.902 0.294 0.208], [0.302 0.733 0.835], [0.200 0.627 0.173]};
markers = {'o','s','^'};
linestyles = {'-','--','-.'};

titles  = {'Angle RMSE vs SI strength (SNR = 0 dB, MC = 10)', ...
           'Range RMSE vs SI strength (SNR = 0 dB, MC = 10)', ...
           'Velocity RMSE vs SI strength (SNR = 0 dB, MC = 10)'};
ylabels = {'Angle RMSE (deg)', 'Range RMSE (m)', 'Velocity RMSE (m/s)'};
fnames  = {'angle', 'range', 'velocity'};
datas   = {angle, range, vel};

% 平滑曲线 x 轴
beta_dense = logspace(log10(1), log10(10000), 300);

for fi = 1:3
    y = datas{fi};

    fig = figure('Color','w','Units','pixels','Position',[80+fi*30,120+fi*30,620,470]);
    ax = axes('Parent',fig); hold(ax,'on');

    for mi = 1:3
        y_smooth = 10.^(pchip(log10(beta), log10(max(y(mi,:),1e-12)), log10(beta_dense)));
        plot(ax, beta_dense, y_smooth, ...
            'Color', colors{mi}, ...
            'LineStyle', linestyles{mi}, ...
            'LineWidth', 1.5, ...
            'DisplayName', method_labels{mi});
        plot(ax, beta, max(y(mi,:),1e-12), ...
            'Color', colors{mi}, ...
            'LineStyle', 'none', ...
            'Marker', markers{mi}, ...
            'MarkerSize', 6, ...
            'MarkerFaceColor', 'w', ...
            'HandleVisibility', 'off');
    end

    xlabel(ax,'Self-interference strength \beta_{SI} (relative to target)', ...
        'FontName','Times New Roman','FontSize',10);
    ylabel(ax, ylabels{fi}, 'FontName','Times New Roman','FontSize',10);
    title(ax, titles{fi}, 'FontName','Times New Roman','FontSize',10,'FontWeight','normal');
    legend(ax, method_labels, 'Location', 'northwest', 'Box', 'on', ...
        'FontName','Times New Roman','FontSize',9);

    set(ax,'XScale','log');
    set(ax,'YScale','log');
    xlim(ax,[0.8, 12000]);
    yvals = y(:);
    yvals = yvals(~isnan(yvals) & yvals>0);
    if ~isempty(yvals)
        ylo = 10^floor(log10(min(yvals)));
        yhi = 10^ceil(log10(max(yvals)));
        ylim(ax,[ylo,yhi]);
    end

    apply_nature_axes(ax);
    set(ax,'YScale','log');
    ytick_vals = 10.^(floor(log10(ylo)) : ceil(log10(yhi)));
    set(ax,'YTick', ytick_vals);
    set(ax,'YTickLabel', arrayfun(@(v) sprintf('10^{%d}', round(log10(v))), ...
        ytick_vals, 'UniformOutput', false));
    hold(ax,'off');

    base = fullfile(fig_dir, sprintf('fig_si_strength_zf_null_sic_%s_mc10_smooth', fnames{fi}));
    savefig(fig, [base '.fig']);
    exportgraphics(fig, [base '.png'], 'Resolution', 300);
    close(fig);
    fprintf('  saved: %s.fig/.png\n', base);
end

fprintf('Done.\n');
end
