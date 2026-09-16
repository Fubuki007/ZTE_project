% =========================================================================
% plot_rmse_results_4methods.m
%   统一重画三张四方法对比图 (SNR / 子载波 / SI强度), 风格完全一致:
%     - 四条曲线带 marker (ZF圆周 / Tx-NS方块 / Rx-SIC菱形 / Dual三角)
%     - 图例放在坐标框内 (Location='best'), 不占用右边空白
%     - 横轴刻度用纯数字 (%d, 不用科学计数法; SI强度 1000/10000 即 1e+03 等)
%     - Times New Roman, 对数纵轴 10^n, 纵轴范围统一 1e-3~1e3
%     - SNR / 子载波图保留单调平滑 (isotonic+PCHIP), SI强度图为原始数据
%   数据来源: 用户提供的全量运行结果 (下方矩阵), SI强度取自服务器 fig 实测值。
%   smooth_curves 只控制 SNR / 子载波 (SI 图始终用原始数据)。
%   输出: fig/fig_rmse_vs_snr_4methods.fig/.png/.eps
%         fig/fig_rmse_vs_subcarrier_4methods.fig/.png/.eps
%         fig/fig_range_rmse_vs_si_strength_4methods_server.fig/.png/.eps
% =========================================================================
function plot_rmse_results_4methods()
close all; clc;

smooth_curves = true;   % true=SNR/子载波单调平滑; false=原始折线

script_dir = fileparts(mfilename('fullpath'));
if isempty(script_dir), script_dir = pwd; end
fig_dir = fullfile(script_dir, 'fig');
if ~exist(fig_dir, 'dir'), mkdir(fig_dir); end

labels = {'ZF-DFT (no SI suppression)', ...
          'Tx-NS-DFT (Tx null-space only)', ...
          'Rx-SIC-DFT (Rx digital SIC only)', ...
          'Dual-Domain-DFT (Tx NS + Rx SIC)'};
colors  = {[0.80 0.20 0.15], [0.20 0.55 0.25], [0.15 0.40 0.75], [0.10 0.10 0.10]};
markers = {'o', 's', 'd', '^'};

% ---- 数据 1: 子载波扫描 (median over 100 MC, SNR=0 dB, beta_SI=100) ----
Ns = [512, 1024, 2048, 3168, 6336, 12672];
R_ns = [128.9318   39.6849   0.1969   0.1844;
        114.5803   98.9638   0.1333   0.1514;
         32.0243   99.7294   0.0670   0.0714;
        217.0347    0.0895   0.0404   0.0428;
        216.2771    0.0095   0.0138   0.0132;
        291.1085    0.0205   0.0071   0.0068];

% ---- 数据 2: SNR 扫描 (beta_SI=100) ----
snr = (-45:5:20);
R_snr = [175.9233  183.6473  210.8272  156.6422;
         209.5822  122.4411  161.1158  152.3383;
         128.9550   90.0137   85.4355   89.9681;
         233.9921   98.4245   74.3858  106.8136;
         175.0274  109.7235    0.0123  118.3627;
          52.7437   87.6879    0.0063  106.7191;
          52.7431    0.0146    0.0079    0.0114;
          52.7431    0.0160    0.0069    0.0066;
          52.7431    0.0138    0.0075    0.0062;
          52.7431    0.0129    0.0075    0.0073;
          52.7431    0.0131    0.0074    0.0072;
          52.7431    0.0129    0.0073    0.0075;
          52.7431    0.0128    0.0074    0.0072;
          52.7431    0.0128    0.0074    0.0072];

% ---- 数据 3: SI 强度扫描 (SNR=0 dB, 原始数据, 取自服务器 fig) ----
beta = [1, 10, 100, 1000, 10000];
R_si = [0.00819849  0.00765606  0.0074412  0.0072718;
        0.017014    0.0081949   0.0073052 0.0068371;
       52.7431      0.0130411   0.007321  0.007271;
       52.7432     14.5281      0.0073472 0.0074071;
       52.7432     14.6783      0.0072844 0.0069602];

% ---- 图 1: 子载波扫描 ----
plot_one(Ns, R_ns, 'log', Ns, [Ns(1)*0.8, Ns(end)*1.25], ...
    'Number of subcarriers N_s', ...
    sprintf('Range RMSE vs Number of Subcarriers (\\beta_{SI} = 100, SNR = 0 dB)'), ...
    labels, colors, markers, fig_dir, 'fig_rmse_vs_subcarrier_4methods', smooth_curves);

% ---- 图 2: SNR 扫描 ----
plot_one(snr, R_snr, 'linear', -45:5:20, [snr(1)-2, snr(end)+2], ...
    'SNR (dB)', ...
    sprintf('Range RMSE vs SNR (\\beta_{SI} = 100)'), ...
    labels, colors, markers, fig_dir, 'fig_rmse_vs_snr_4methods', smooth_curves);

% ---- 图 3: SI 强度扫描 (原始数据, 不改平滑) ----
plot_one(beta, R_si, 'log', beta, [beta(1)*0.8, beta(end)*1.3], ...
    'Self-interference strength \beta_{SI} (relative to target)', ...
    sprintf('Range RMSE vs SI Strength (SNR = 0 dB, MC = 50)'), ...
    labels, colors, markers, fig_dir, 'fig_range_rmse_vs_si_strength_4methods_server', false);

fprintf('完成, 三张图已存到 %s (smooth=%d)\n', fig_dir, smooth_curves);
end

function plot_one(x, R, xscale, xticks, xlims, xlab, ttl, labels, colors, markers, fig_dir, base, smooth)
n = numel(labels);
if strcmp(xscale, 'log')
    xi = log10(x(:));
else
    xi = x(:);
end
xi_dense = linspace(xi(1), xi(end), 400);

fig = figure('Color', 'w', 'Units', 'pixels', 'Position', [120 160 700 500]);
set(gca, 'XScale', xscale);
hold on;
h = gobjects(n, 1);
for i = 1:n
    yl = log10(max(R(:,i), 1e-12));
    if smooth
        yl = isotonic_nonincreasing(yl);   % 单调非增 (去抖动)
    end
    ys_dense = 10.^pchip(xi, yl, xi_dense); % 保形插值 -> 平滑单调曲线
    if strcmp(xscale, 'log')
        h(i) = plot(10.^xi_dense, ys_dense, '-', 'Color', colors{i}, 'LineWidth', 1.5);
    else
        h(i) = plot(xi_dense, ys_dense, '-', 'Color', colors{i}, 'LineWidth', 1.5);
    end
    % marker 放在原始 x 位置 (取值在平滑曲线上, 避免 jitter)
    xx = x(:);
    yy = 10.^pchip(xi, yl, xi);
    plot(xx, yy, markers{i}, 'Color', colors{i}, 'MarkerSize', 6, ...
        'MarkerFaceColor', 'w', 'LineStyle', 'none');
end

xlabel(xlab, 'FontName', 'Times New Roman', 'FontSize', 11);
ylabel('Range RMSE (m)', 'FontName', 'Times New Roman', 'FontSize', 11);
title(ttl, 'FontName', 'Times New Roman', 'FontSize', 11, 'FontWeight', 'normal');
% 图例放坐标框内 (best), 不占右边空白
legend(h, labels, 'Location', 'best', 'Box', 'on', ...
    'FontName', 'Times New Roman', 'FontSize', 9, 'Interpreter', 'none');

set(gca, 'XTick', xticks);
set(gca, 'XTickLabel', cellstr(num2str(xticks(:), '%d')));   % 纯数字, 不用科学计数
xlim(xlims);

ylim([1e-3, 1e3]);
set(gca, 'YScale', 'log');
set(gca, 'YTick', 10.^(-3:3));
set(gca, 'YTickLabel', {'10^{-3}', '10^{-2}', '10^{-1}', '10^{0}', ...
                        '10^{1}', '10^{2}', '10^{3}'});
apply_nature_axes(gca);

savefig(fig, fullfile(fig_dir, [base '.fig']));
print(fig, fullfile(fig_dir, [base '.png']), '-dpng', '-r300');
print(fig, fullfile(fig_dir, [base '.eps']), '-depsc2', '-painters');
close(fig);
fprintf('saved: %s.fig/.png/.eps\n', base);
end

% PAVA 保序回归: 单调非增 (用于 log 域)
function yhat = isotonic_nonincreasing(y)
y = y(:);
n = numel(y);
val = zeros(n,1); cnt = zeros(n,1); strt = zeros(n,1);
k = 0;
for j = 1:n
    k = k + 1;
    strt(k) = j; val(k) = y(j); cnt(k) = 1;
    while k > 1 && val(k-1) < val(k)      % 违反"非增" -> 合并相邻块
        val(k-1) = (val(k-1)*cnt(k-1) + val(k)*cnt(k)) / (cnt(k-1)+cnt(k));
        cnt(k-1) = cnt(k-1) + cnt(k);
        k = k - 1;
    end
end
yhat = zeros(n,1);
for b = 1:k
    e = n; if b < k, e = strt(b+1) - 1; end
    yhat(strt(b):e) = val(b);
end
end

function apply_nature_axes(ax)
set(ax, 'FontName', 'Times New Roman', 'FontSize', 9, 'LineWidth', 0.75, ...
    'Box', 'on', 'TickDir', 'in', 'TickLength', [0.014 0.014], ...
    'XMinorTick', 'on', 'YMinorTick', 'on', 'Layer', 'top', ...
    'GridLineStyle', '-', 'MinorGridLineStyle', ':', ...
    'GridAlpha', 0.18, 'MinorGridAlpha', 0.12);
grid(ax, 'on');
ax.XColor = [0.10 0.10 0.10];
ax.YColor = [0.10 0.10 0.10];
end
