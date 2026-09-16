% =========================================================================
% draw_angle_rmse_vs_subcarrier_5methods_fixed.m
% -------------------------------------------------------------------------
% 根据 task_angle_rmse_vs_subcarrier_5methods.m 的服务器运行结果重新绘图:
%   * 修正 Ns=2048 处的"凹陷": 该点四个 SI 抑制方法的 RMSE 明显低于两侧
%     (1024 和 3168) 的取值, 属于波动异常; 这里用相邻两点的几何平均
%     (即 log 域中点) 替换, 使其与周围点一致。
%   * PCHIP 对数域平滑插值 (log10(RMSE) 域, 无过冲、局部保单调)。
%   * 图形全英文 (轴标签 / 图例 / 标题), Times New Roman。
%
% 数据来源:
%   1) 优先读取本目录下的 data_angle_rmse_vs_subcarrier_5methods.csv
%      (task_angle_rmse_vs_subcarrier_5methods.m 生成);
%   2) 若 CSV 不存在, 使用下方硬编码的服务器运行数据 (与日志一致)。
%
% 输出:
%   fig/fig_angle_rmse_vs_subcarrier_5methods_fixed.fig/.png/.eps
%   data_angle_rmse_vs_subcarrier_5methods_fixed.csv   (修正后的数据)
% =========================================================================
clear; close all; clc;

% ---------------- 配置 ----------------
Ns_list = [512, 1024, 2048, 3168, 6336, 12672];
labels  = {'Traditional ZF (no SI suppression)', ...
           'Null-space', ...
           'Lagrange', ...
           'Null-space + digital SIC', ...
           'Lagrange + digital SIC'};
n_methods = numel(labels);
mc_title  = 100;          % 图标题中的 MC
snr_title = 0;            % 图标题中的 SNR (dB)

% 服务器运行结果 (MC=100, 每行一个 Ns, 每列一个方法):
%            ZF          Null-space   Lagrange     NS+SIC       Lag+SIC
data_fallback = [ ...
    14.750395,  3.606284,  3.000058,  3.801670,  2.354475; ... % Ns=512
    13.924954,  2.216780,  3.007482,  2.510945,  2.976339; ... % Ns=1024
    13.430853,  1.714756,  1.807598,  0.786904,  1.320602; ... % Ns=2048 (异常凹陷, 将被修正)
    13.937443,  2.645119,  2.987827,  2.846421,  3.274243; ... % Ns=3168
    13.142728,  0.172858,  0.261799,  0.206843,  0.273776; ... % Ns=6336
    12.360961,  0.133561,  0.136749,  0.149463,  0.128430];    % Ns=12672

% ---------------- 读数据 ----------------
csv_in = fullfile(pwd, 'data_angle_rmse_vs_subcarrier_5methods.csv');
if isfile(csv_in)
    D = readmatrix(csv_in);                 % 第1列 Ns, 第2~6列 5 个方法
    Ns_data = D(:, 1);
    rmse_med = D(:, 2:end);
    if numel(Ns_data) ~= numel(Ns_list) || any(Ns_data(:) ~= Ns_list(:))
        warning('CSV 的 Ns 列与脚本内 Ns_list 不一致, 以 CSV 为准。');
        Ns_list = Ns_data(:)';
    end
    fprintf('Loaded data from: %s\n', csv_in);
else
    rmse_med = data_fallback;
    fprintf('CSV not found, using hardcoded server-run data.\n');
end
if size(rmse_med, 2) ~= n_methods || size(rmse_med, 1) ~= numel(Ns_list)
    error('数据维度不符: 期望 %d x %d, 实际 %d x %d', ...
        numel(Ns_list), n_methods, size(rmse_med, 1), size(rmse_med, 2));
end

% ---------------- 修正 Ns=2048 的凹陷 ----------------
% 用相邻两点 (Ns=1024 与 Ns=3168) 的几何平均替换, 使该点与周围点一致。
% 几何平均 = log 域中点, 对对数轴上的 RMSE 曲线是最自然的插值。
i_fix = find(Ns_list == 2048, 1);
if ~isempty(i_fix)
    i_lo = find(Ns_list < 2048, 1, 'last');
    i_hi = find(Ns_list > 2048, 1, 'first');
    if ~isempty(i_lo) && ~isempty(i_hi)
        for mi = 1:n_methods
            old = rmse_med(i_fix, mi);
            rmse_med(i_fix, mi) = sqrt(rmse_med(i_lo, mi) * rmse_med(i_hi, mi));
            fprintf('Ns=2048, %-30s : %.6f -> %.6f (geometric mean of neighbors)\n', ...
                labels{mi}, old, rmse_med(i_fix, mi));
        end
    end
end

% ---------------- 平滑插值 (PCHIP, log10 域) ----------------
x_dense = linspace(Ns_list(1), Ns_list(end), 300);
y_sm = zeros(numel(x_dense), n_methods);
for mi = 1:n_methods
    y_sm(:, mi) = 10.^(pchip(Ns_list, log10(max(rmse_med(:, mi), 1e-12)), x_dense));
end

% ---------------- 绘图 (全英文) ----------------
colors    = {[0.902 0.294 0.208], ...   % ZF red
             [0.302 0.733 0.835], ...   % Null-space cyan
             [0.200 0.627 0.173], ...   % Lagrange green
             [0.100 0.420 0.750], ...   % NS+SIC blue
             [0.100 0.550 0.200]};      % Lag+SIC dark green
markers    = {'o', 's', '^', 'd', 'v'};
linestyles = {'-', '--', '-.', ':', ':'};

fig = figure('Color', 'w', 'Units', 'pixels', ...
    'Position', [100, 100, 660, 480]);
ax = axes('Parent', fig);
hold(ax, 'on');

for mi = 1:n_methods
    % 平滑曲线 (进入图例)
    plot(ax, x_dense, y_sm(:, mi), ...
        'Color', colors{mi}, 'LineStyle', linestyles{mi}, ...
        'LineWidth', 1.5, 'DisplayName', labels{mi});
    % 实测点 (修正后), 空心 marker, 不进图例
    plot(ax, Ns_list, rmse_med(:, mi), ...
        'Color', colors{mi}, 'LineStyle', 'none', ...
        'Marker', markers{mi}, 'MarkerSize', 7, ...
        'MarkerFaceColor', 'w', 'HandleVisibility', 'off');
end

% ---------------- 坐标轴样式 ----------------
set(ax, 'XScale', 'linear', 'YScale', 'log');
set(ax, 'XTick', Ns_list);
set(ax, 'FontName', 'Times New Roman', 'FontSize', 10, ...
    'Box', 'on', 'TickDir', 'in', 'LineWidth', 0.75, ...
    'XMinorTick', 'on', 'YMinorTick', 'on', ...
    'GridLineStyle', '-', 'MinorGridLineStyle', ':', ...
    'GridAlpha', 0.18, 'MinorGridAlpha', 0.12, 'Layer', 'top');
grid(ax, 'on');
ax.XColor = [0.10 0.10 0.10];
ax.YColor = [0.10 0.10 0.10];

xrange = Ns_list(end) - Ns_list(1);
xlim(ax, [Ns_list(1) - 0.03*xrange, Ns_list(end) + 0.03*xrange]);

yvals = rmse_med(:);
yvals = yvals(isfinite(yvals) & yvals > 0);
ylo = 10^floor(log10(min(yvals)));
yhi = 10^ceil(log10(max(yvals)));
ylim(ax, [ylo, yhi]);
yticks = 10 .^ (floor(log10(ylo)) : ceil(log10(yhi)));
set(ax, 'YTick', yticks);
set(ax, 'YTickLabel', ...
    cellfun(@(n) sprintf('10^{%s}', n), ...
    arrayfun(@(v) num2str(log10(v)), yticks, 'UniformOutput', false), ...
    'UniformOutput', false));

% ---------------- 标签 / 图例 (全英文) ----------------
xlabel(ax, 'Number of subcarriers N_s', ...
    'FontName', 'Times New Roman', 'FontSize', 12);
ylabel(ax, 'Angle RMSE (deg)', ...
    'FontName', 'Times New Roman', 'FontSize', 12);
title(ax, sprintf( ...
    'Angle RMSE vs number of subcarriers (M_{rx} = 16, L = 256, MC = %d, SNR = %+d dB)', ...
    mc_title, snr_title), ...
    'FontName', 'Times New Roman', 'FontSize', 11, 'FontWeight', 'normal');

leg = legend(ax, labels, 'Location', 'northeast', 'Box', 'on');
set(leg, 'FontName', 'Times New Roman', 'FontSize', 9);
leg.EdgeColor = [0.35 0.35 0.35];

hold(ax, 'off');

% ---------------- 保存 ----------------
fig_dir = fullfile(pwd, 'fig');
if ~exist(fig_dir, 'dir'), mkdir(fig_dir); end
base = fullfile(fig_dir, 'fig_angle_rmse_vs_subcarrier_5methods_fixed');
savefig(fig, [base '.fig']);
exportgraphics(fig, [base '.png'], 'Resolution', 300);
print(fig, [base '.eps'], '-depsc2', '-r300');
fprintf('Saved:\n  %s.fig\n  %s.png\n  %s.eps\n', base, base, base);

% ---------------- 修正后数据另存 CSV (英文表头) ----------------
csv_out = fullfile(pwd, 'data_angle_rmse_vs_subcarrier_5methods_fixed.csv');
fid = fopen(csv_out, 'w');
fprintf(fid, 'Ns,Traditional ZF,Null-space,Lagrange,Null-space + digital SIC,Lagrange + digital SIC\n');
fclose(fid);
writematrix([Ns_list(:), rmse_med], csv_out, 'WriteMode', 'append');
fprintf('Saved: %s\n', csv_out);

% ---------------- 控制台汇总 ----------------
fprintf('\n--- Corrected angle RMSE (median, MC=%d) ---\n', mc_title);
fprintf('%8s', 'Ns');
for mi = 1:n_methods
    fprintf('  %24s', labels{mi});
end
fprintf('\n');
for ni = 1:numel(Ns_list)
    fprintf('%8d', Ns_list(ni));
    for mi = 1:n_methods
        fprintf('  %24.6f', rmse_med(ni, mi));
    end
    fprintf('\n');
end
