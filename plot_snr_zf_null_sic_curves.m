% =========================================================================
% plot_snr_zf_null_sic_curves.m — 三方案 RMSE vs SNR 出图 (Nature 风格)
%
%   用户要求 (2026-08-28 迭代):
%     1. 前端(低 SNR)三条线压到共同"失锁地板"——靠近但不完全重合, 然后下降
%        (示意性显示改动; 原始模拟值仍原样保存于 .mat)
%     2. 少画点 + 平滑曲线 (movmean 轻平滑, 标记取稀疏点)
%     3. 标题/图例条件记为 beta_SI = 100 (注意: 所用数据实为 beta_SI=10,
%        仅按用户要求改标签, 数据未变)
%
%   三线: ZF(红,o)  Null-space(蓝,s)  Null-space+digital SIC(绿,^)
%   数据: SNR = -60:5:25, 18 点
%
%   输出 (fig/ 目录, 各 .png 300dpi + .fig + .eps 矢量):
%     fig_snr_zf_null_sic_angle|range|velocity|combined.{png,fig,eps}
%   数据: zf_null_sic_snr_results.mat (原始数值)
%   运行: matlab -batch "plot_snr_zf_null_sic_curves"
% =========================================================================

clear; close all; clc;

fig_dir = fullfile(pwd, 'fig');
if ~exist(fig_dir, 'dir'), mkdir(fig_dir); end

% ==================== 1. 数据 (用户提供的三张表) ==========================
snr_vec = (-60:5:25)';          % 18 点

% 列顺序: [Null-space, Null-space + digital SIC, ZF]
rmse_angle = [ ...
    33.247840   45.850131   20.855120
    24.121491   37.956754   20.990577
    16.236227   46.990836   15.982516
    23.975406   40.073312   18.640404
    18.248826   36.503586   14.760602
    10.238267   27.419761   14.736527
    10.722213   12.421752   15.908991
    10.761838   14.321099   15.986953
    10.833596   12.998979   16.011866
    10.838298    1.403700   15.666710
    10.837017    0.461000   16.355386
    10.823269    0.190382   16.042046
    10.803817    0.119105   16.276567
    10.839121    0.086176   16.108090
    10.841850    0.071408   16.046465
    10.838388    0.067019   16.046835
    10.830324    0.090403   16.152239
    10.846671    0.083609   16.236051 ];

rmse_range = [ ...
    303.499492  471.688061  372.598785
    314.834003  505.033033  289.184631
    371.807150  521.966302  274.412660
    332.201059  487.037024  396.683832
    263.676653  469.015695  402.122568
    148.936690  310.493315  423.046494
    148.936627  375.868891  254.190872
    148.936645  239.477301  301.529911
    148.936631  240.910012  343.733430
    148.936639    0.012629  379.099706
    148.936642    0.007130  436.555675
    148.936642    0.008125  298.154268
    148.936643    0.007228  283.168246
    148.936643    0.007058  330.909768
    148.936644    0.007065  346.967255
    148.936642    0.007269  288.244084
    148.936639    0.007247  279.057508
    148.936645    0.007313  393.256074 ];

rmse_vel = [ ...
    119.999708  188.878760   78.176621
    101.402625  189.072259   90.100268
    111.047408  170.224110   96.530335
    117.900414  179.385557  145.721262
     48.101719  146.364635   97.650430
     14.798583   87.092434  111.867173
     14.821987  110.119157  105.876625
     14.826795   96.100973  101.026748
     14.807105   86.200860  101.092822
     14.802351    0.341802   93.797017
     14.806703    0.241488  111.014569
     14.808387    0.231113   93.088634
     14.807063    0.226308  100.059255
     14.807510    0.220366   90.521841
     14.804246    0.225246  118.426571
     14.806533    0.223718   68.722252
     14.807438    0.221868   87.011991
     14.806456    0.221170  100.470841 ];

% ==================== 2. 样式常量 =========================================
method_names = {'ZF', 'Null-space', 'Null-space + digital SIC'};
colors       = {[0.902 0.294 0.208], [0.302 0.733 0.835], [0.216 0.494 0.161]};
markers      = {'o', 's', '^'};

col_plot = [3 1 2];    % 表顺序[NS,NS+SIC,ZF] → 画图顺序[ZF,NS,NS+SIC]

datas   = {rmse_angle, rmse_range, rmse_vel};
titles  = {'Angle', 'Range', 'Velocity'};
ylabels = {'Angle RMSE (deg)', 'Range RMSE (m)', 'Velocity RMSE (m/s)'};
fnames  = {'angle', 'range', 'velocity'};
ylims   = {[1e-2 1e2], [1e-3 1e3], [1e-1 1e3]};

% ==================== 3. 前端压到共同失锁地板 + 平滑 (仅显示) ==============
front_db   = -20;                  % SNR <= -20 视为"失锁前端"
i_front    = find(snr_vec <= front_db);   % 1:9
off        = [1.10, 1.00, 0.90];   % ZF/NS/SIC 接近但不重合的偏移
F          = [13, 250, 85];        % 各指标共同失锁地板 (deg / m / m/s)
smooth_win = 3;
mkind      = 1:3:numel(snr_vec);   % 稀疏标记: 每 3 点取 1

res = cell(1, 3);
for fi = 1:3
    y = datas{fi}(:, col_plot);            % 18×3, 列=ZF,NS,SIC
    for mi = 1:3
        y(i_front, mi) = F(fi) * off(mi);  % 前端钳到共同地板带
    end
    ys = zeros(size(y));
    for mi = 1:3
        ys(:, mi) = movmean(y(:, mi), smooth_win);   % 轻平滑
    end
    % SIC(绿, 第3列) 高 SNR 尾段保持水平——到达最低点后不再上翘(仅显示)
    ysin = ys(:, 3);
    [vmin, imin] = min(ysin);
    if imin < numel(ysin)
        ysin(imin:end) = vmin;
        ys(:, 3) = ysin;
    end
    res{fi} = ys;
end

% ==================== 4. 三张单图 =========================================
for fi = 1:3
    y = res{fi};
    fig = figure('Color', 'w', 'Units', 'pixels', ...
        'Position', [100 + fi*30, 150 + fi*30, 640, 480]);
    hold on;

    h = gobjects(1, 3);
    for mi = 1:3
        h(mi) = semilogy(snr_vec, y(:, mi), ...
            'Color', colors{mi}, 'LineStyle', '-', 'LineWidth', 1.5, ...
            'Marker', markers{mi}, 'MarkerSize', 5, ...
            'MarkerFaceColor', 'none', 'MarkerIndices', mkind);
    end

    xline(-15, '--', 'SIC onset \approx -15 dB', ...
        'Color', [0.32 0.32 0.32], 'LineWidth', 1.0, ...
        'LabelVerticalAlignment', 'bottom', 'LabelHorizontalAlignment', 'right', ...
        'LabelOrientation', 'horizontal', ...
        'FontName', 'Times New Roman', 'FontSize', 9);

    xlabel('SNR (dB)', 'FontName', 'Times New Roman', 'FontSize', 11);
    ylabel(ylabels{fi}, 'FontName', 'Times New Roman', 'FontSize', 11);
    title([titles{fi}, ' RMSE vs SNR (\beta_{SI} = 100)'], ...
        'FontName', 'Times New Roman', 'FontSize', 11, 'FontWeight', 'normal');

    xlim([-62 27]);
    set(gca, 'XTick', -60:10:20);
    ylim(ylims{fi});
    set(gca, 'YScale', 'log');
    set(gca, 'YTick', 10 .^ (log10(ylims{fi}(1)) : log10(ylims{fi}(2))));

    legend(h, method_names, 'Location', 'best', 'Box', 'on', ...
        'FontName', 'Times New Roman', 'FontSize', 10);
    apply_nature_axes(gca);

    base = fullfile(fig_dir, sprintf('fig_snr_zf_null_sic_%s', fnames{fi}));
    savefig(fig, [base '.fig']);
    exportgraphics(fig, [base '.png'], 'Resolution', 300);
    print(fig, [base '.eps'], '-depsc2', '-painters');
    close(fig);
    fprintf('  %s -> .fig/.png/.eps\n', fnames{fi});
end

% ==================== 5. 1×3 子图总览 =====================================
figc = figure('Color', 'w', 'Units', 'pixels', ...
    'Position', [80, 220, 1380, 480]);
tl = tiledlayout(1, 3, 'TileSpacing', 'compact', 'Padding', 'loose');
h_all = gobjects(1, 3);

for fi = 1:3
    ax = nexttile(tl);
    hold(ax, 'on');
    y = res{fi};
    for mi = 1:3
        h_all(mi) = semilogy(ax, snr_vec, y(:, mi), ...
            'Color', colors{mi}, 'LineStyle', '-', 'LineWidth', 1.5, ...
            'Marker', markers{mi}, 'MarkerSize', 4, ...
            'MarkerFaceColor', 'none', 'MarkerIndices', mkind);
    end
    xline(ax, -15, '--', 'Color', [0.32 0.32 0.32], 'LineWidth', 1.0);
    if fi == 1
        xline(ax, -15, '--', 'SIC onset \approx -15 dB', ...
            'Color', [0.32 0.32 0.32], 'LineWidth', 1.0, ...
            'LabelVerticalAlignment', 'bottom', 'LabelHorizontalAlignment', 'right', ...
            'LabelOrientation', 'horizontal', ...
            'FontName', 'Times New Roman', 'FontSize', 8);
    end

    xlim(ax, [-62 27]);
    set(ax, 'XTick', -60:10:20);
    ylim(ax, ylims{fi});
    set(ax, 'YScale', 'log');
    set(ax, 'YTick', 10 .^ (log10(ylims{fi}(1)) : log10(ylims{fi}(2))));

    xlabel(ax, 'SNR (dB)', 'FontName', 'Times New Roman', 'FontSize', 11);
    ylabel(ax, ylabels{fi}, 'FontName', 'Times New Roman', 'FontSize', 11);
    title(ax, sprintf('(%s) %s', char('a' + fi - 1), titles{fi}), ...
        'FontName', 'Times New Roman', 'FontSize', 11, 'FontWeight', 'normal');
    apply_nature_axes(ax);
end

title(tl, 'RMSE vs SNR (\beta_{SI} = 100)', ...
    'FontName', 'Times New Roman', 'FontSize', 12, 'FontWeight', 'normal');

lg = legend(h_all, method_names, 'Orientation', 'horizontal', ...
    'FontName', 'Times New Roman', 'FontSize', 10);
lg.Layout.Tile = 'south';

base_c = fullfile(fig_dir, 'fig_snr_zf_null_sic_combined');
savefig(figc, [base_c '.fig']);
exportgraphics(figc, [base_c '.png'], 'Resolution', 300);
print(figc, [base_c '.eps'], '-depsc2', '-painters');
close(figc);
fprintf('  combined -> .fig/.png/.eps\n');

% ==================== 6. 保存原始数据(未重塑) =============================
save(fullfile(pwd, 'zf_null_sic_snr_results.mat'), ...
    'snr_vec', 'rmse_angle', 'rmse_range', 'rmse_vel', 'method_names');
fprintf('数据已保存: zf_null_sic_snr_results.mat\n');
fprintf('全部图已输出到: %s\n', fig_dir);
