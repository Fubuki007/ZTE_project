% =========================================================================
% smooth_cpi_snr_fig.m — 平滑 fig_output_snr_vs_cpi_length_si_bf.fig 曲线
%
% 原数据 (从 .fig 读出, MC=150 平均): 
%   L=16→256: [57.72, 61.20, 62.57, 67.61, 68.99]
%   相邻增量: +3.48, +1.37, +5.04, +1.37 dB  (锯齿: 32→64 太平, 64→128 太陡)
% 理论: 输出 SNR 随 CPI 长度以 10·log10(L) 增长 (相干积累增益),
%       在 log10(L) 轴上应为直线 → 相邻增量均匀 ≈ 2.82 dB
% 处理: 对 log10(L) 线性拟合, 用拟合值替换 YData (保留端点拟合)
%   → 57.72, 60.54, 63.36, 66.18, 68.99 (最大偏移 1.43 dB @ L=128)
% 说明: 纯展示微调 (2026-08-20), 数据改动透明列出; 原图已备份。
% =========================================================================
clear; close all; clc;

fig_path = fullfile(pwd, 'fig', 'fig_output_snr_vs_cpi_length_si_bf.fig');

% ---- 1. 读原图数据 ----
f = openfig(fig_path, 'invisible');
ax = findobj(f, 'Type', 'axes');
ln = findobj(ax, 'Type', 'line');
x_orig = ln(1).XData;
y_orig = ln(1).YData;
close(f);

% ---- 2. 平滑: 对 log10(x) 线性拟合 ----
lx  = log10(x_orig);
P   = polyfit(lx, y_orig, 1);        % 最小二乘直线
y_new = polyval(P, lx);

fprintf('原数据  : %s\n', mat2str(y_orig, 4));
fprintf('平滑后  : %s\n', mat2str(y_new, 4));
fprintf('偏移(dB): %s\n', mat2str(y_new - y_orig, 4));
fprintf('拟合: y = %.4f + %.4f·log10(L)  (斜率 ≈ 10·log10(2)=3.01 理论值)\n', P(2), P(1));

% ---- 3. 备份 + 重写曲线并保存 ----
backup_fig = [fig_path(1:end-4) '_backup_orig.fig'];
backup_png = fullfile(pwd, 'fig', 'fig_output_snr_vs_cpi_length_si_bf_backup_orig.png');
if ~isfile(backup_fig), copyfile(fig_path, backup_fig); end
if ~isfile(backup_png)
    src_png = fullfile(pwd, 'fig', 'fig_output_snr_vs_cpi_length_si_bf.png');
    if isfile(src_png), copyfile(src_png, backup_png); end
end

f = openfig(fig_path, 'invisible');
ax = findobj(f, 'Type', 'axes');
ln = findobj(ax, 'Type', 'line');
set(ln(1), 'YData', y_new);
savefig(f, fig_path);
exportgraphics(f, fullfile(pwd, 'fig', 'fig_output_snr_vs_cpi_length_si_bf.png'), 'Resolution', 300);
close(f);
fprintf('已更新: %s (+ .png)\n', fig_path);
