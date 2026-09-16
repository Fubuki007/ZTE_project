% =========================================================================
% plot_si_strength_lagrange_sic_fullsize_mc10.m
%   Nature 风格，平滑曲线（log-log 域 pchip），图例在图内
%   数据：task_si_strength_lagrange_sic_fullsize_mc10.mat（MC=10 完整尺寸）
%
%   默认画 2 条曲线：Lagrange / Lagrange + digital SIC
%   若 overlay_zf_ns = true 且 task_si_strength_zf_null_sic_fullsize_mc10.mat
%   存在，则同时叠加 ZF / Null-space / Null-space+SIC（共 5 条曲线），
%   输出文件名自动变为 fig_si_strength_all5_*_mc10_smooth。
%
%   输出：
%     fig/fig_si_strength_lagrange_sic_{angle,range,velocity}_mc10_smooth.fig/.png
%     或（叠加时）
%     fig/fig_si_strength_all5_{angle,range,velocity}_mc10_smooth.fig/.png
% =========================================================================
function plot_si_strength_lagrange_sic_fullsize_mc10()
clear; close all; clc;

fig_dir = fullfile(pwd, 'fig');
if ~exist(fig_dir, 'dir'), mkdir(fig_dir); end

% ---- 数据 ----
mat_path = fullfile(pwd, 'task_si_strength_lagrange_sic_fullsize_mc10.mat');
if ~isfile(mat_path)
    error('找不到 %s，请先在服务器运行 task_si_strength_lagrange_sic_fullsize_mc10 并把 .mat 拷回本目录', mat_path);
end
S = load(mat_path);
beta = S.beta_list(:).';

angle = median(S.rmse_theta, 3, 'omitnan');   % (n_methods, n_beta)
range = median(S.rmse_R,     3, 'omitnan');
vel   = median(S.rmse_v,     3, 'omitnan');

method_labels = {'Lagrange', 'Lagrange + digital SIC'};
colors    = {[0.494 0.184 0.556], [0.929 0.694 0.125]};
markers   = {'d', 'v'};
linestyles = {':', '-'};

% ---- 可选：叠加已有 ZF / Null-space / Null-space+SIC 数据 ----
overlay_zf_ns = true;
zf_mat = fullfile(pwd, 'task_si_strength_zf_null_sic_fullsize_mc10.mat');
has_overlay = overlay_zf_ns && isfile(zf_mat);
if has_overlay
    S2 = load(zf_mat);
    if isequal(S2.beta_list(:).', beta)
        angle = [median(S2.rmse_theta, 3, 'omitnan'); angle];
        range = [median(S2.rmse_R,     3, 'omitnan'); range];
        vel   = [median(S2.rmse_v,     3, 'omitnan'); vel];
        method_labels = [{'ZF', 'Null-space', 'Null-space + digital SIC'}, method_labels];
        colors    = [{[0.902 0.294 0.208], [0.302 0.733 0.835], [0.200 0.627 0.173]}, colors];
        markers   = [{'o', 's', '^'}, markers];
        linestyles = [{'-', '--', '-.'}, linestyles];
        fprintf('已叠加 ZF / Null-space / Null-space+SIC 数据\n');
    else
        has_overlay = false;
        fprintf('警告: %s 的 beta_list 与 Lagrange 结果不一致，跳过叠加\n', zf_mat);
    end
end

n_methods = numel(method_labels);

fprintf('\n--- 中位数结果表 (MC=%d 取中位数) ---\n', S.n_mc);
for mi = 1:n_methods
    fprintf('%-24s | Angle: %s | Range: %s | Vel: %s\n', method_labels{mi}, ...
        num2str(angle(mi,:), '%.4f '), num2str(range(mi,:), '%.4f '), num2str(vel(mi,:), '%.4f '));
end

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

    for mi = 1:n_methods
        y_row = y(mi,:);
        % NaN 防护：某个 beta 全部 MC 失败时，用该方法最差值填充，避免 pchip 崩溃
        if any(isnan(y_row))
            n_nan = sum(isnan(y_row));
            if n_nan == numel(y_row)
                fprintf('  [%s] 全部为 NaN，跳过该曲线\n', fnames{fi});
                continue;
            end
            y_row(isnan(y_row)) = max(y_row(~isnan(y_row)));
            fprintf('  [%s %s] %d 个 beta 点为 NaN，已用最差值填充\n', ...
                fnames{fi}, method_labels{mi}, n_nan);
        end
        y_smooth = 10.^(pchip(log10(beta), log10(max(y_row,1e-12)), log10(beta_dense)));
        plot(ax, beta_dense, y_smooth, ...
            'Color', colors{mi}, ...
            'LineStyle', linestyles{mi}, ...
            'LineWidth', 1.5, ...
            'DisplayName', method_labels{mi});
        plot(ax, beta, max(y_row,1e-12), ...
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
    ylo = 1e-4; yhi = 1e2;   % 兜底：全部为 NaN 时仍可生成坐标轴
    if ~isempty(yvals)
        ylo = 10^floor(log10(min(yvals)));
        yhi = 10^ceil(log10(max(yvals)));
    end
    ylim(ax,[ylo,yhi]);

    apply_nature_axes(ax);
    set(ax,'YScale','log');
    ytick_vals = 10.^(floor(log10(ylo)) : ceil(log10(yhi)));
    set(ax,'YTick', ytick_vals);
    set(ax,'YTickLabel', arrayfun(@(v) sprintf('10^{%d}', round(log10(v))), ...
        ytick_vals, 'UniformOutput', false));
    hold(ax,'off');

    if has_overlay
        base = fullfile(fig_dir, sprintf('fig_si_strength_all5_%s_mc10_smooth', fnames{fi}));
    else
        base = fullfile(fig_dir, sprintf('fig_si_strength_lagrange_sic_%s_mc10_smooth', fnames{fi}));
    end
    savefig(fig, [base '.fig']);
    exportgraphics(fig, [base '.png'], 'Resolution', 300);
    close(fig);
    fprintf('  saved: %s.fig/.png\n', base);
end

fprintf('Done.\n');
end
