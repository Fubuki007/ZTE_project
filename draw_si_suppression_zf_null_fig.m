% =========================================================================
% draw_si_suppression_zf_null_fig.m — ZF vs 零空间 RMSE 对比 (Nature 风格)
%   数据: data_si_suppression_zf_null.csv
%         = median RMSE over MC=200 (来自运行日志, 13 SNR 点) *
%         zf_R/zf_th/zf_v = ZF 的距离/角度/速度 RMSE; ns_* 同理
%   风格: apply_nature_axes (完整方框/刻度向内/10^n 整数幂刻度)
%   输出: fig/fig_si_suppression_{angle,velocity,range}_zf_null.fig (+ .png)
% =========================================================================
clear; close all; clc;

D = readmatrix('data_si_suppression_zf_null.csv');   % 自动跳过表头
snr = D(:,1);
zf  = D(:,2:4);    % 列: R, th, v
ns  = D(:,5:7);

% 只保留 SNR >= -30 的数据
mask = snr >= -30;
snr = snr(mask);
zf  = zf(mask, :);
ns  = ns(mask, :);

colors    = {[0.902 0.294 0.208], [0.302 0.733 0.835]};
markers   = {'o', 's'};
linestyle = {'-', '--'};
leg_str   = {'ZF (no SI suppression)', 'Null-space'};

titles  = {'Angle', 'Velocity', 'Range'};
ylabels = {'Angle RMSE (deg)', 'Velocity RMSE (m/s)', 'Range RMSE (m)'};
datas   = {[zf(:,2) ns(:,2)], [zf(:,3) ns(:,3)], [zf(:,1) ns(:,1)]};
fnames  = {'angle', 'velocity', 'range'};

fig_dir = fullfile(pwd, 'fig');
if ~exist(fig_dir, 'dir'), mkdir(fig_dir); end

for fi = 1:3
    fig = figure('Color', 'w', 'Units', 'pixels', ...
        'Position', [120+fi*30, 160+fi*30, 620, 470]);
    hold on;

    for mi = 1:2
        semilogy(snr, max(datas{fi}(:,mi), 1e-12), ...
            'Color', colors{mi}, ...
            'Marker', markers{mi}, ...
            'LineStyle', linestyle{mi}, ...
            'LineWidth', 1.3, ...
            'MarkerSize', 5.5, ...
            'MarkerFaceColor', 'w');
    end

    xlabel('Input SNR (dB)', 'FontName', 'Times New Roman', 'FontSize', 10);
    ylabel(ylabels{fi}, 'FontName', 'Times New Roman', 'FontSize', 10);
    title(sprintf('%s RMSE vs SNR  --  SI Suppression (ZF vs Null-space, MC=200)', ...
        titles{fi}), 'FontName', 'Times New Roman', 'FontSize', 10, 'FontWeight', 'normal');
    legend(leg_str, 'Location', 'northeastoutside', 'Box', 'on', ...
        'FontName', 'Times New Roman', 'FontSize', 9, 'Interpreter', 'none');

    xlim([snr(1)-2, snr(end)+2]);

    % log-scale y limits spanning the data in integer powers of 10
    yvals = datas{fi}(:);
    yvals = yvals(~isnan(yvals) & yvals > 0);
    ylo = 10^floor(log10(min(yvals)));
    yhi = 10^ceil(log10(max(yvals)));
    ylim([ylo, yhi]);

    apply_nature_axes(gca);
    set(gca, 'YScale', 'log');

    % explicit 10^n tick labels
    ytick_vals = 10 .^ (floor(log10(ylo)) : ceil(log10(yhi)));
    set(gca, 'YTick', ytick_vals);
    set(gca, 'YTickLabel', ...
        cellfun(@(n) sprintf('10^{%s}', n), ...
        arrayfun(@(v) num2str(log10(v)), ytick_vals, 'UniformOutput', false), ...
        'UniformOutput', false));

    % export .fig and .png
    base_path = fullfile(fig_dir, sprintf('fig_si_suppression_%s_zf_null', fnames{fi}));
    savefig(fig, [base_path '.fig']);
    exportgraphics(fig, [base_path '.png'], 'Resolution', 300);
    close(fig);
    fprintf('  %s -> fig/\n', fnames{fi});
end

fprintf('Done: three Nature-style semilogy figures saved to fig/ (.fig + .png)\n');
