% =========================================================================
% plot_si_suppression_nature.m  --  SI suppression RMSE vs SNR, Nature style
%
%   Loads task_si_suppression.mat and produces three semilogy figures
%   (angle / velocity / range), one curve per method:
%       1. ZF (no SI suppression)
%       2. Null-space precoder
%       3. Lagrange precoder
%
%   Y axis: RMSE, logarithmic (10^n ticks)
%       angle    -> deg
%       velocity -> m/s
%       range    -> m
%   Style: apply_nature_axes.m
%
%   Outputs (in fig/, .fig only):
%       fig_si_suppression_angle.fig
%       fig_si_suppression_velocity.fig
%       fig_si_suppression_range.fig
% =========================================================================

function plot_si_suppression_nature()

close all; clc;

% -------------------- 1. load data ---------------------------------------
mat_path = fullfile(pwd, 'task_si_suppression.mat');
assert(isfile(mat_path), 'Data file not found: %s', mat_path);
d = load(mat_path);

snr_list      = d.snr_list(:)';
method_labels = d.method_labels;
if iscell(method_labels)
    method_labels = method_labels(:)';
else
    method_labels = cellstr(method_labels)';
end
n_methods    = numel(method_labels);
n_mc         = d.n_mc;

rmse_theta_med = d.rmse_theta_med;   % [n_methods x n_snr], deg
rmse_v_med     = d.rmse_v_med;       % [n_methods x n_snr], m/s
rmse_R_med     = d.rmse_R_med;       % [n_methods x n_snr], m

fprintf('Loaded: %d methods x %d SNR x %d MC\n', n_methods, numel(snr_list), n_mc);
fprintf('SNR = [%s] dB\n', strjoin(arrayfun(@num2str, snr_list, 'UniformOutput', false), ' '));

% -------------------- 2. plotting config ----------------------------------
colors    = {[0.902 0.294 0.208], [0.302 0.733 0.835], [0.200 0.627 0.173]};
markers   = {'o', 's', '^'};
linestyle = {'-', '--', '-.'};

titles  = {'Angle', 'Velocity', 'Range'};
ylabels = {'Angle RMSE (deg)', 'Velocity RMSE (m/s)', 'Range RMSE (m)'};
datas   = {rmse_theta_med, rmse_v_med, rmse_R_med};
fnames  = {'angle', 'velocity', 'range'};

fig_dir = fullfile(pwd, 'fig');
if ~exist(fig_dir, 'dir'), mkdir(fig_dir); end

% -------------------- 3. draw figures -------------------------------------
for fi = 1:3
    fig = figure('Color', 'w', 'Units', 'pixels', ...
        'Position', [120+fi*30, 160+fi*30, 620, 470]);
    hold on;

    for mi = 1:n_methods
        y = max(datas{fi}(mi, :), 1e-12);
        semilogy(snr_list, y, ...
            'Color', colors{mi}, ...
            'Marker', markers{mi}, ...
            'LineStyle', linestyle{mi}, ...
            'LineWidth', 1.3, ...
            'MarkerSize', 5.5, ...
            'MarkerFaceColor', 'w');
    end

    xlabel('Input SNR (dB)', 'FontName', 'Times New Roman', 'FontSize', 10);
    ylabel(ylabels{fi}, 'FontName', 'Times New Roman', 'FontSize', 10);
    title(sprintf('%s RMSE vs SNR  --  SI Suppression (MC=%d)', ...
        titles{fi}, n_mc), ...
        'FontName', 'Times New Roman', 'FontSize', 10, 'FontWeight', 'normal');
    legend(method_labels, 'Location', 'northeastoutside', 'Box', 'on', ...
        'FontName', 'Microsoft YaHei', 'FontSize', 9, 'Interpreter', 'none');

    xlim([snr_list(1)-2, snr_list(end)+2]);

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
    base_path = fullfile(fig_dir, sprintf('fig_si_suppression_%s', fnames{fi}));
    savefig(fig, [base_path '.fig']);
    exportgraphics(fig, [base_path '.png'], 'Resolution', 300);
    close(fig);
    fprintf('  %s -> fig/\n', fnames{fi});
end

fprintf('Done: three Nature-style semilogy figures saved to fig/ (.fig + .png)\n');

end
