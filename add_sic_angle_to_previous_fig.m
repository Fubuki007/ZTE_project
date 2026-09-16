% =========================================================================
% add_sic_angle_to_previous_fig.m
% -------------------------------------------------------------------------
% Add the two digital-SIC angle-RMSE curves produced by
% task_si_suppression_sic_angle.m to the previous polished figure
%   fig/angle_rmse_vs_snr_si_suppression.fig
% and save a new merged figure:
%   fig/angle_rmse_vs_snr_si_suppression_with_sic.fig/.png/.eps
%
% Usage:
%   add_sic_angle_to_previous_fig
%   add_sic_angle_to_previous_fig('data_si_suppression_sic_ns_lag_angle.csv')
% =========================================================================
function add_sic_angle_to_previous_fig(csv_path, old_fig_path)
    close all; clc;

    if nargin < 1 || isempty(csv_path)
        csv_path = fullfile(pwd, 'data_si_suppression_sic_ns_lag_angle.csv');
    end
    if nargin < 2 || isempty(old_fig_path)
        old_fig_path = fullfile(pwd, 'fig', ...
            'angle_rmse_vs_snr_si_suppression.fig');
    end

    if ~isfile(csv_path)
        error('CSV not found: %s\nRun task_si_suppression_sic_angle.m first.', ...
            csv_path);
    end
    if ~isfile(old_fig_path)
        error('Previous figure not found: %s', old_fig_path);
    end

    % ---- New data: snr, ns_sic_th, lag_sic_th ----
    D = readmatrix(csv_path);
    snr_sic     = D(:, 1);
    ns_sic_raw  = D(:, 2);
    lag_sic_raw = D(:, 3);

    % Same plotting convention as draw_angle_rmse_snr_si_fig.m:
    % cummin() monotone correction, then PCHIP on log10(RMSE).
    ns_sic  = cummin(ns_sic_raw);
    lag_sic = cummin(lag_sic_raw);

    snr_dense = linspace(min(snr_sic), max(snr_sic), 400);
    ns_sm  = 10.^(pchip(snr_sic, log10(max(ns_sic, 1e-12)),  snr_dense));
    lag_sm = 10.^(pchip(snr_sic, log10(max(lag_sic, 1e-12)), snr_dense));

    % ---- Open the previous figure and add curves to its axes ----
    fig = openfig(old_fig_path, 'invisible');
    ax = findobj(fig, 'Type', 'axes');
    if isempty(ax)
        error('No axes found in %s', old_fig_path);
    end
    ax = ax(1);
    hold(ax, 'on');

    c_ns_sic  = [0.10 0.42 0.75];
    c_lag_sic = [0.10 0.55 0.20];

    plot(ax, snr_dense, ns_sm, ...
        'Color', c_ns_sic, 'LineStyle', ':', 'LineWidth', 1.4, ...
        'DisplayName', '零空间法 + 数字SIC');
    plot(ax, snr_dense, lag_sm, ...
        'Color', c_lag_sic, 'LineStyle', ':', 'LineWidth', 1.4, ...
        'DisplayName', '拉格朗日法 + 数字SIC');

    % Hollow markers at the measured SNR points (not added to legend).
    plot(ax, snr_sic, ns_sic, ...
        'Color', c_ns_sic, 'LineStyle', 'none', ...
        'Marker', 'd', 'MarkerSize', 5, ...
        'MarkerFaceColor', 'w', 'HandleVisibility', 'off');
    plot(ax, snr_sic, lag_sic, ...
        'Color', c_lag_sic, 'LineStyle', 'none', ...
        'Marker', 'v', 'MarkerSize', 5, ...
        'MarkerFaceColor', 'w', 'HandleVisibility', 'off');

    % ---- Rebuild legend with old 3 + new 2 curves ----
    old_leg = findobj(fig, 'Type', 'legend');
    delete(old_leg);

    legend(ax, { ...
        '传统 ZF (不抑制)', ...
        '零空间法', ...
        '拉格朗日法', ...
        '零空间法 + 数字SIC (LS)', ...
        '拉格朗日法 + 数字SIC (LS)'}, ...
        'Location', 'northeast', 'Box', 'on', ...
        'FontName', 'Microsoft YaHei', 'FontSize', 8, ...
        'Interpreter', 'none');

    % Keep the original axes limits / ticks / log scale.
    set(ax, 'YScale', 'log');

    % ---- Save merged figure with a new name ----
    [fig_dir, fig_base] = fileparts(old_fig_path);
    out_base = fullfile(fig_dir, ...
        'angle_rmse_vs_snr_si_suppression_with_sic');

    savefig(fig, [out_base '.fig']);
    exportgraphics(fig, [out_base '.png'], 'Resolution', 300);
    print(fig, [out_base '.eps'], '-depsc2', '-r300');
    close(fig);

    fprintf('Merged figure saved:\n');
    fprintf('  %s.fig\n', out_base);
    fprintf('  %s.png\n', out_base);
    fprintf('  %s.eps\n', out_base);
end
