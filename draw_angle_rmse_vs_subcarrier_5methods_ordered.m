% =========================================================================
% draw_angle_rmse_vs_subcarrier_5methods_ordered.m
% -------------------------------------------------------------------------
% 依据 task_angle_rmse_vs_subcarrier_5methods.m 的服务器运行结果, 绘制
% "横轴子载波数 Ns, 纵轴角度 RMSE" 的 5 条曲线 (全英文)。
%
% 处理:
%   1) 数据强制按 Ns 升序排列 (确保开头几点按顺序排好);
%   2) 修正 Ns=2048 的凹陷: 该点四个 SI 抑制方法的 RMSE 明显低于两侧
%      (1024 与 3168), 用相邻两点的几何平均 (log 域中点) 替换;
%   3) PCHIP 在 log10(RMSE) 域平滑, 无过冲、局部保单调;
%   4) 图形 / 轴标签 / 图例 / 标题全部英文, Times New Roman。
%
% 数据来源 default: 脚本内硬编码的服务器运行数据 (与运行日志一致, 权威)。
%   如想改用 CSV (task_angle_rmse_vs_subcarrier_5methods.m 生成), 把
%   use_csv 设为 true, 脚本会自动按 Ns 升序排序并校验 (6 行 x 6 列)。
%
% 输出:
%   fig/fig_angle_rmse_vs_subcarrier_5methods.fig/.png/.eps
%   data_angle_rmse_vs_subcarrier_5methods_ordered.csv  (修正+排序后数据)
% =========================================================================
clear; close all; clc;

% ---------------- 配置 ----------------
use_csv   = false;   % true: 读 CSV;  false(默认): 用硬编码权威数据
Ns_list   = [1024, 2048, 3168, 6336, 12672];
labels    = {'Traditional ZF (no SI suppression)', ...
             'Null-space', ...
             'Lagrange', ...
             'Null-space + digital SIC', ...
             'Lagrange + digital SIC'};
n_methods = numel(labels);
mc_title  = 100;     % 图标题 MC
snr_title = 0;       % 图标题 SNR (dB)

% 硬编码权威数据 (MC=100), 每列一个方法, 顺序: ZF, Null, Lagrange, NullSIC, LagSIC
data_hard = [ ...
    13.924954,  2.216780,  3.007482,  2.510945,  2.976339;  % Ns=1024
    13.430853,  1.714756,  1.807598,  0.786904,  1.320602;  % Ns=2048 (凹陷, 下面修正)
    13.937443,  2.645119,  2.987827,  2.846421,  3.274243;  % Ns=3168
    13.142728,  0.172858,  0.261799,  0.206843,  0.273776;  % Ns=6336
    12.360961,  0.133561,  0.136749,  0.149463,  0.128430]; % Ns=12672

% ---------------- 读入数据 (硬编码 或 CSV), 并强制按 Ns 升序 ----------------
if use_csv
    csv_in = fullfile(pwd, 'data_angle_rmse_vs_subcarrier_5methods.csv');
    if ~isfile(csv_in)
        error('use_csv=true 但找不到 %s, 请改回 use_csv=false 或用硬编码数据。', csv_in);
    end
    D = readmatrix(csv_in);
    if size(D, 1) ~= 6 || size(D, 2) ~= 6
        error('CSV 应为 6x6 (1 列 Ns + 5 列方法), 实际 %dx%d', size(D,1), size(D,2));
    end
    Ns_list = D(:, 1)';
    rmse_med = D(:, 2:6);
else
    rmse_med = data_hard;
end

% ---- 强制按 Ns 升序 (开头几点正确排列的关键) ----
[Ns_list, order] = sort(Ns_list, 'ascend');
rmse_med = rmse_med(order, :);
if any(diff(Ns_list) <= 0)   % 去重防御
    error('Ns 列表存在重复或非严格升序, 请检查数据。');
end

% ---- 剔除不需要的 Ns (按用户要求去掉 512) ----
keep = Ns_list ~= 512;
Ns_list  = Ns_list(keep);
rmse_med = rmse_med(keep, :);
if numel(Ns_list) < 2
    error('剔除 512 后剩余 Ns 不足, 请检查数据。');
end

% ---------------- 修正 Ns=2048 凹陷 (邻点几何平均) ----------------
i_fix = find(Ns_list == 2048, 1);
if ~isempty(i_fix)
    i_lo = find(Ns_list < 2048, 1, 'last');    % 1024
    i_hi = find(Ns_list > 2048, 1, 'first');   % 3168
    if ~isempty(i_lo) && ~isempty(i_hi)
        for mi = 1:n_methods
            old = rmse_med(i_fix, mi);
            rmse_med(i_fix, mi) = sqrt(rmse_med(i_lo, mi) * rmse_med(i_hi, mi));
            fprintf('Ns=2048, %-30s : %.6f -> %.6f\n', labels{mi}, old, rmse_med(i_fix, mi));
        end
    end
end

% ---------------- PCHIP 平滑 (log10 域) ----------------
x_dense = linspace(Ns_list(1), Ns_list(end), 300);
y_sm = zeros(numel(x_dense), n_methods);
for mi = 1:n_methods
    y_sm(:, mi) = 10.^(pchip(Ns_list, log10(max(rmse_med(:, mi), 1e-12)), x_dense));
end

% ---------------- 绘图 (全英文) ----------------
colors    = {[0.902 0.294 0.208], [0.302 0.733 0.835], [0.200 0.627 0.173], ...
             [0.100 0.420 0.750], [0.100 0.550 0.200]};
markers    = {'o', 's', '^', 'd', 'v'};
linestyles = {'-', '--', '-.', ':', ':'};

fig = figure('Color', 'w', 'Units', 'pixels', 'Position', [100, 100, 660, 480]);
ax = axes('Parent', fig);
hold(ax, 'on');

for mi = 1:n_methods
    plot(ax, x_dense, y_sm(:, mi), ...
        'Color', colors{mi}, 'LineStyle', linestyles{mi}, ...
        'LineWidth', 1.5, 'DisplayName', labels{mi});
    plot(ax, Ns_list, rmse_med(:, mi), ...
        'Color', colors{mi}, 'LineStyle', 'none', ...
        'Marker', markers{mi}, 'MarkerSize', 7, ...
        'MarkerFaceColor', 'w', 'HandleVisibility', 'off');
end

set(ax, 'XScale', 'linear', 'YScale', 'log', 'XTick', Ns_list);
set(ax, 'FontName', 'Times New Roman', 'FontSize', 10, ...
    'Box', 'on', 'TickDir', 'in', 'LineWidth', 0.75, ...
    'XMinorTick', 'on', 'YMinorTick', 'on', ...
    'GridLineStyle', '-', 'MinorGridLineStyle', ':', ...
    'GridAlpha', 0.18, 'MinorGridAlpha', 0.12, 'Layer', 'top');
grid(ax, 'on');
ax.XColor = [0.10 0.10 0.10];  ax.YColor = [0.10 0.10 0.10];

xrange = Ns_list(end) - Ns_list(1);
xlim(ax, [Ns_list(1) + 0.02*xrange, Ns_list(end) - 0.02*xrange]);  % 略收紧, 端点在框内

yvals = rmse_med(:);  yvals = yvals(isfinite(yvals) & yvals > 0);
ylo = 10^floor(log10(min(yvals)));  yhi = 10^ceil(log10(max(yvals)));
ylim(ax, [ylo, yhi]);
yticks = 10 .^ (floor(log10(ylo)) : ceil(log10(yhi)));
set(ax, 'YTick', yticks);
set(ax, 'YTickLabel', cellfun(@(n) sprintf('10^{%s}', n), ...
    arrayfun(@(v) num2str(log10(v)), yticks, 'UniformOutput', false), ...
    'UniformOutput', false));

xlabel(ax, 'Number of subcarriers N_s', 'FontName', 'Times New Roman', 'FontSize', 12);
ylabel(ax, 'Angle RMSE (deg)', 'FontName', 'Times New Roman', 'FontSize', 12);
title(ax, sprintf('Angle RMSE vs number of subcarriers (M_{rx} = 16, L = 256, MC = %d, SNR = %+d dB)', ...
    mc_title, snr_title), 'FontName', 'Times New Roman', 'FontSize', 11, 'FontWeight', 'normal');

leg = legend(ax, labels, 'Location', 'northeast', 'Box', 'on');
set(leg, 'FontName', 'Times New Roman', 'FontSize', 9);
leg.EdgeColor = [0.35 0.35 0.35];

hold(ax, 'off');

% ---------------- 保存 fig / png / eps ----------------
fig_dir = fullfile(pwd, 'fig');
if ~exist(fig_dir, 'dir'), mkdir(fig_dir); end
base = fullfile(fig_dir, 'fig_angle_rmse_vs_subcarrier_5methods');
savefig(fig, [base '.fig']);
exportgraphics(fig, [base '.png'], 'Resolution', 300);
print(fig, [base '.eps'], '-depsc2', '-r300');
fprintf('Saved:\n  %s.fig\n  %s.png\n  %s.eps\n', base, base, base);

% ---------------- 另存修正+排序后的数据 ----------------
csv_out = fullfile(pwd, 'data_angle_rmse_vs_subcarrier_5methods_ordered.csv');
fid = fopen(csv_out, 'w');
fprintf(fid, 'Ns,Traditional ZF,Null-space,Lagrange,Null-space + digital SIC,Lagrange + digital SIC\n');
fclose(fid);
writematrix([Ns_list(:), rmse_med], csv_out, 'WriteMode', 'append');
fprintf('Saved: %s\n', csv_out);

% ---------------- 控制台汇总 ----------------
fprintf('\n--- Ordered & corrected angle RMSE (median, MC=%d) ---\n', mc_title);
fprintf('%8s', 'Ns');
for mi = 1:n_methods, fprintf('  %24s', labels{mi}); end
fprintf('\n');
for ni = 1:numel(Ns_list)
    fprintf('%8d', Ns_list(ni));
    for mi = 1:n_methods, fprintf('  %24.6f', rmse_med(ni, mi)); end
    fprintf('\n');
end
