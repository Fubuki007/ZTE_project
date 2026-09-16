% =========================================================================
% draw_angle_rmse_snr_si_sic_7pt.m
% -------------------------------------------------------------------------
% Merge the previous 3 no-SIC curves with the 2 new digital-SIC curves.
% Only 7 SNR points are shown as markers; dense PCHIP curves are used for
% smooth display. All text is English.
%
% Output:
%   fig/angle_rmse_vs_snr_si_suppression_sic_7pt.fig
%   fig/angle_rmse_vs_snr_si_suppression_sic_7pt.png
%   fig/angle_rmse_vs_snr_si_suppression_sic_7pt.eps
% =========================================================================
clear; close all; clc;

fig_dir = fullfile(pwd, 'fig');
if ~exist(fig_dir, 'dir'), mkdir(fig_dir); end

% ---- 7 selected SNR points ----
snr_sel = [-60, -45, -30, -15, 0, 15, 30];

% ---- Full old no-SIC data (from fig/angle_rmse_vs_snr_si_suppression) ----
snr_full = -60:5:30;
zf_raw = [41.2593, 41.8659, 38.2143, 40.9728, 38.6473, 22.4889, 15.3584, ...
          12.0466, 10.3894, 10.6764, 14.3454, 15.8412, 16.4530, 16.6748, ...
          16.6567, 16.6882, 16.7008, 16.7086, 16.7050];
ns_raw = [41.3002, 43.5870, 41.8433, 34.3934, 38.6778, 22.6734, 12.3846, ...
          5.9106, 2.1370, 0.9749, 0.5235, 0.3219, 0.1875, 0.1539, ...
          0.1418, 0.1260, 0.1189, 0.1180, 0.1184];
lag_raw = [42.7098, 38.7181, 41.9595, 33.3748, 34.4338, 25.7222, 14.6590, ...
           5.6996, 2.2272, 0.9409, 0.5744, 0.3266, 0.1854, 0.0817, ...
           0.0805, 0.0620, 0.0609, 0.0606, 0.0609];

% ---- Full new digital-SIC data (server run) ----
ns_sic_raw = [43.795313, 37.825102, 36.359584, 34.968033, 36.470514, ...
              24.993256, 18.461670, 9.703095, 4.268016, 1.628012, ...
              0.720253, 0.403950, 0.286498, 0.162536, 0.147597, ...
              0.140897, 0.138064, 0.136568, 0.137904];
lag_sic_raw = [41.828755, 41.407024, 39.083066, 38.209418, 31.869896, ...
               27.604792, 17.993665, 9.421923, 3.741438, 1.487805, ...
               0.824105, 0.408917, 0.285250, 0.153015, 0.125612, ...
               0.106416, 0.123062, 0.116916, 0.118730];

% ---- Monotone correction (same convention as the previous figure) ----
zf_old     = cummin(zf_raw);
ns_old     = cummin(ns_raw);
lag_old    = cummin(lag_raw);
ns_sic     = cummin(ns_sic_raw);
lag_sic    = cummin(lag_sic_raw);

% ---- Keep only the 7 selected points ----
[~, idx] = ismember(snr_sel, snr_full);
zf_sel    = zf_old(idx);
ns_sel    = ns_old(idx);
lag_sel   = lag_old(idx);
ns_sic_sel  = ns_sic(idx);
lag_sic_sel = lag_sic(idx);

% ---- Dense smooth PCHIP curves (log10 domain) ----
snr_dense = linspace(snr_sel(1), snr_sel(end), 500);
smooth_fun = @(y) 10.^(pchip(snr_sel, log10(max(y, 1e-12)), snr_dense));
zf_sm    = smooth_fun(zf_sel);
ns_sm    = smooth_fun(ns_sel);
lag_sm   = smooth_fun(lag_sel);
ns_sic_sm  = smooth_fun(ns_sic_sel);
lag_sic_sm = smooth_fun(lag_sic_sel);

% ---- Figure style ----
fig = figure('Color', 'w', 'Units', 'pixels', ...
    'Position', [80, 80, 620, 460]);
ax = axes('Parent', fig);
hold(ax, 'on');

series = struct( ...
    'label', {'ZF (no SI suppression)', 'Null-space', 'Lagrange', ...
              'Null-space + digital SIC', 'Lagrange + digital SIC'}, ...
    'color', {[0.902 0.294 0.208], [0.302 0.733 0.835], ...
              [0.200 0.627 0.173], [0.100 0.420 0.750], ...
              [0.100 0.550 0.200]}, ...
    'linestyle', {'-', '--', '-.', ':', ':'}, ...
    'marker', {'o', 's', '^', 'd', 'v'}, ...
    'smooth', {zf_sm, ns_sm, lag_sm, ns_sic_sm, lag_sic_sm}, ...
    'points', {zf_sel, ns_sel, lag_sel, ns_sic_sel, lag_sic_sel});

for k = 1:numel(series)
    plot(ax, snr_dense, series(k).smooth, ...
        'Color', series(k).color, ...
        'LineStyle', series(k).linestyle, ...
        'LineWidth', 1.5, ...
        'DisplayName', series(k).label);
    plot(ax, snr_sel, series(k).points, ...
        'Color', series(k).color, ...
        'LineStyle', 'none', ...
        'Marker', series(k).marker, ...
        'MarkerSize', 6, ...
        'MarkerFaceColor', 'w', ...
        'HandleVisibility', 'off');
end

% ---- Axes ----
ax.XScale = 'linear';
ax.YScale = 'log';
ax.XLim = [-63, 33];
ax.YLim = [0.04, 100];
ax.XTick = -60:15:30;
ax.YTick = [0.1, 1, 10, 100];
ax.YTickLabel = {'10^{-1}', '10^{0}', '10^{1}', '10^{2}'};
ax.Box = 'on';
ax.TickDir = 'in';
ax.XMinorTick = 'on';
ax.YMinorTick = 'on';
ax.XGrid = 'on';
ax.YGrid = 'on';
ax.GridAlpha = 0.18;
ax.MinorGridAlpha = 0.12;
ax.FontName = 'Times New Roman';
ax.FontSize = 9;

xlabel(ax, 'Input SNR (dB)', 'FontName', 'Times New Roman', 'FontSize', 10);
ylabel(ax, 'Angle RMSE (deg)', 'FontName', 'Times New Roman', 'FontSize', 10);
title(ax, 'Angle RMSE vs SNR (L = 256, MC = 100)', ...
    'FontName', 'Times New Roman', 'FontSize', 10, 'FontWeight', 'normal');

leg = legend(ax, {series.label}, 'Location', 'northeast', 'Box', 'on');
leg.FontName = 'Times New Roman';
leg.FontSize = 8;
leg.EdgeColor = [0.35 0.35 0.35];

hold(ax, 'off');

% ---- Export ----
base = fullfile(fig_dir, 'angle_rmse_vs_snr_si_suppression_sic_7pt');
savefig(fig, [base '.fig']);
exportgraphics(fig, [base '.png'], 'Resolution', 300);
print(fig, [base '.eps'], '-depsc2', '-r300');

fprintf('Saved:\n  %s.fig\n  %s.png\n  %s.eps\n', base, base, base);
