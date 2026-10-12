function task_si_strength_3methods_beta1_to_1e6_mc80_aggregate(quick_mode)
% Merge the four 20-MC parts, compute RMS metrics, and create three plots.

if nargin < 1
    quick_mode = false;
end
if ~isscalar(quick_mode) || ...
        (~islogical(quick_mode) && ~ismember(quick_mode, [0, 1]))
    error('quick_mode must be a logical scalar.');
end

close all; clc;
if quick_mode
    n_parts = 1;
    n_mc = 1;
    part_pattern = 'task_si_strength_3methods_beta1_to_1e6_smoke_part%02d.mat';
    output_stem = 'task_si_strength_3methods_beta1_to_1e6_smoke';
else
    n_parts = 4;
    n_mc = 80;
    part_pattern = 'task_si_strength_3methods_beta1_to_1e6_mc80_part%02d.mat';
    output_stem = 'task_si_strength_3methods_beta1_to_1e6_mc80';
end

first_file = fullfile(pwd, sprintf(part_pattern, 1));
if ~isfile(first_file)
    error('Missing worker result: %s', first_file);
end
first = load(first_file);
beta_list = first.beta_list;
method_labels = first.method_labels;
SNR_dB = first.SNR_dB;
pilot_len = first.pilot_len;
n_methods = numel(method_labels);
n_beta = numel(beta_list);

rmse_R = NaN(n_methods, n_beta, n_mc);
rmse_theta = NaN(n_methods, n_beta, n_mc);
rmse_phi = NaN(n_methods, n_beta, n_mc);
rmse_v = NaN(n_methods, n_beta, n_mc);
detected_targets = zeros(n_methods, n_beta, n_mc);
estimator_elapsed_s = NaN(n_methods, n_beta, n_mc);
spatial_suppression_db = NaN(1, n_mc);
actual_nmse_db = NaN(n_beta, n_mc);
digital_suppression_db = NaN(n_beta, n_mc);
total_suppression_db = NaN(n_beta, n_mc);
si_to_target_before_db = NaN(n_beta, n_mc);
residual_to_target_db = NaN(n_beta, n_mc);
elapsed_per_mc_s = NaN(1, n_mc);
seen_mc = false(1, n_mc);
worker_elapsed_min = NaN(1, n_parts);

for part_idx = 1:n_parts
    part_file = fullfile(pwd, sprintf(part_pattern, part_idx));
    if ~isfile(part_file)
        error('Missing worker result: %s', part_file);
    end
    part = load(part_file);
    if ~isequal(part.beta_list, beta_list) || ...
            ~isequal(part.method_labels, method_labels)
        error('Worker %d configuration does not match worker 1.', part_idx);
    end
    idx = part.global_mc_indices;
    if any(idx < 1 | idx > n_mc) || any(seen_mc(idx))
        error('Worker %d contains invalid or duplicate MC indices.', part_idx);
    end
    seen_mc(idx) = true;
    rmse_R(:, :, idx) = part.rmse_R;
    rmse_theta(:, :, idx) = part.rmse_theta;
    rmse_phi(:, :, idx) = part.rmse_phi;
    rmse_v(:, :, idx) = part.rmse_v;
    detected_targets(:, :, idx) = part.detected_targets;
    estimator_elapsed_s(:, :, idx) = part.estimator_elapsed_s;
    spatial_suppression_db(idx) = part.spatial_suppression_db;
    actual_nmse_db(:, idx) = part.actual_nmse_db;
    digital_suppression_db(:, idx) = part.digital_suppression_db;
    total_suppression_db(:, idx) = part.total_suppression_db;
    si_to_target_before_db(:, idx) = part.si_to_target_before_db;
    residual_to_target_db(:, idx) = part.residual_to_target_db;
    elapsed_per_mc_s(idx) = part.elapsed_per_mc_s;
    worker_elapsed_min(part_idx) = part.total_elapsed_min;
end

if ~all(seen_mc) || any(isnan(rmse_R(:)))
    error('The merged result is incomplete. Completed MC=%d/%d, NaN=%d.', ...
        sum(seen_mc), n_mc, sum(isnan(rmse_R(:))));
end

rmse_R_rms = sqrt(mean(rmse_R.^2, 3));
rmse_theta_rms = sqrt(mean(rmse_theta.^2, 3));
rmse_phi_rms = sqrt(mean(rmse_phi.^2, 3));
rmse_v_rms = sqrt(mean(rmse_v.^2, 3));
detection_rate = mean(detected_targets == 2, 3);

fig_dir = fullfile(pwd, 'fig');
if ~isfolder(fig_dir), mkdir(fig_dir); end
local_plot_metric(beta_list, rmse_theta_rms, method_labels, ...
    'Angle RMSE (deg)', 'Angle RMSE versus self-interference strength', ...
    fullfile(fig_dir, [output_stem '_angle']));
local_plot_metric(beta_list, rmse_R_rms, method_labels, ...
    'Range RMSE (m)', 'Range RMSE versus self-interference strength', ...
    fullfile(fig_dir, [output_stem '_range']));
local_plot_metric(beta_list, rmse_v_rms, method_labels, ...
    'Velocity RMSE (m/s)', 'Velocity RMSE versus self-interference strength', ...
    fullfile(fig_dir, [output_stem '_velocity']));

method_col = strings(n_methods * n_beta, 1);
beta_col = NaN(n_methods * n_beta, 1);
angle_col = NaN(n_methods * n_beta, 1);
range_col = NaN(n_methods * n_beta, 1);
velocity_col = NaN(n_methods * n_beta, 1);
detection_col = NaN(n_methods * n_beta, 1);
row = 0;
for method_idx = 1:n_methods
    for beta_idx = 1:n_beta
        row = row + 1;
        method_col(row) = method_labels{method_idx};
        beta_col(row) = beta_list(beta_idx);
        angle_col(row) = rmse_theta_rms(method_idx, beta_idx);
        range_col(row) = rmse_R_rms(method_idx, beta_idx);
        velocity_col(row) = rmse_v_rms(method_idx, beta_idx);
        detection_col(row) = detection_rate(method_idx, beta_idx);
    end
end
summary_table = table(method_col, beta_col, angle_col, range_col, ...
    velocity_col, detection_col, 'VariableNames', ...
    {'Method', 'beta_SI', 'Angle_RMSE_deg', 'Range_RMSE_m', ...
    'Velocity_RMSE_mps', 'Detection_rate'});
writetable(summary_table, fullfile(pwd, [output_stem '.csv']));

audit_notes = first.audit_notes;
save(fullfile(pwd, [output_stem '.mat']), 'beta_list', ...
    'method_labels', 'SNR_dB', 'pilot_len', 'n_mc', 'rmse_R', ...
    'rmse_theta', 'rmse_phi', 'rmse_v', 'detected_targets', ...
    'estimator_elapsed_s', 'spatial_suppression_db', ...
    'actual_nmse_db', 'digital_suppression_db', ...
    'total_suppression_db', 'si_to_target_before_db', ...
    'residual_to_target_db', 'elapsed_per_mc_s', ...
    'worker_elapsed_min', 'rmse_R_rms', 'rmse_theta_rms', ...
    'rmse_phi_rms', 'rmse_v_rms', 'detection_rate', 'audit_notes');

fprintf('=== Aggregated SI-strength result ===\n');
fprintf('MC completeness: %d/%d; NaN count: %d\n', ...
    sum(seen_mc), n_mc, sum(isnan(rmse_R(:))));
fprintf('Worker elapsed times: %s min\n', mat2str(worker_elapsed_min, 4));
fprintf('Mean null-space spatial suppression: %.2f dB\n', ...
    mean(spatial_suppression_db));
fprintf('Estimator time: mean %.3f s, P95 %.3f s, max %.3f s\n', ...
    mean(estimator_elapsed_s(:)), ...
    local_percentile(estimator_elapsed_s(:), 95), ...
    max(estimator_elapsed_s(:)));
fprintf('Saved %s.mat/.csv and three FIG/PNG/EPS figures.\n', output_stem);
end

function local_plot_metric(beta, y, labels, y_label, plot_title, base_path)
colors = [0.894, 0.243, 0.188; ...
          0.275, 0.627, 0.314; ...
          0.208, 0.459, 0.741];
markers = {'o', 's', '^'};
beta_dense = logspace(log10(min(beta)), log10(max(beta)), 600);

fig = figure('Visible', 'off', 'Color', 'w', 'Units', 'pixels', ...
    'Position', [100, 100, 760, 540]);
ax = axes('Parent', fig);
hold(ax, 'on');
line_handles = gobjects(1, size(y, 1));
for method_idx = 1:size(y, 1)
    y_raw = max(y(method_idx, :), realmin);
    y_smooth = 10.^pchip(log10(beta), log10(y_raw), log10(beta_dense));
    line_handles(method_idx) = loglog(ax, beta_dense, y_smooth, '-', ...
        'Color', colors(method_idx, :), 'LineWidth', 1.8, ...
        'DisplayName', labels{method_idx});
    loglog(ax, beta, y_raw, 'LineStyle', 'none', ...
        'Color', colors(method_idx, :), 'Marker', markers{method_idx}, ...
        'MarkerSize', 6.5, 'MarkerFaceColor', 'w', 'LineWidth', 1.1, ...
        'HandleVisibility', 'off');
end

xlabel(ax, 'Self-interference strength \beta_{SI} (relative to target)', ...
    'FontName', 'Times New Roman', 'FontSize', 12);
ylabel(ax, y_label, 'FontName', 'Times New Roman', 'FontSize', 12);
title(ax, plot_title, 'FontName', 'Times New Roman', 'FontSize', 12, ...
    'FontWeight', 'normal');
legend(ax, line_handles, labels, 'Location', 'northwest', 'Box', 'on', ...
    'FontName', 'Times New Roman', 'FontSize', 10, ...
    'Interpreter', 'none');

set(ax, 'XScale', 'log', 'YScale', 'log', ...
    'XLim', [0.8, 1.25e6], 'XTick', 10.^(0:6), ...
    'FontName', 'Times New Roman', 'FontSize', 11, ...
    'LineWidth', 0.9, 'Box', 'on', 'TickDir', 'in', ...
    'XMinorGrid', 'on', 'YMinorGrid', 'on', ...
    'GridLineStyle', '-', 'MinorGridLineStyle', ':', ...
    'GridAlpha', 0.20, 'MinorGridAlpha', 0.08, ...
    'Color', 'w', 'Layer', 'top');
grid(ax, 'on');

positive_values = y(isfinite(y) & y > 0);
y_low = 10^floor(log10(min(positive_values)));
y_high = 10^ceil(log10(max(positive_values)));
if y_low == y_high
    y_low = y_low / 10;
    y_high = y_high * 10;
end
ylim(ax, [y_low, y_high]);
hold(ax, 'off');

savefig(fig, [base_path '.fig']);
exportgraphics(fig, [base_path '.png'], 'Resolution', 300);
exportgraphics(fig, [base_path '.eps'], 'ContentType', 'vector');
close(fig);
end

function value = local_percentile(samples, percentile)
samples = sort(samples(isfinite(samples)));
position = 1 + (numel(samples) - 1) * percentile / 100;
lower_idx = floor(position);
upper_idx = ceil(position);
if lower_idx == upper_idx
    value = samples(lower_idx);
else
    fraction = position - lower_idx;
    value = samples(lower_idx) * (1 - fraction) + ...
        samples(upper_idx) * fraction;
end
end
