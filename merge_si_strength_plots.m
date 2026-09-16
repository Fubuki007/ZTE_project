% =========================================================================
% merge_si_strength_plots.m — SI 强度扫描数据出图 (全 β 区间本地版本)
%
%   数据源  : task_si_strength_sweep.mat   β_SI = [0.01, 0.1, 1, 10, 100, 1000]
%             (R_max_gate=600 m, MC=30, 本地单次全量扫描)
%   出图      : Nature 风格 semilogy (角度/速度/距离) .fig + .png (300dpi)
%   数据      : task_si_strength_sweep_merged.mat (6 档, 跨 5 个数量级)
% =========================================================================

clear; close all; clc;

% ==================== 1. 读取数据 ========================================
loc_path = fullfile(pwd, 'task_si_strength_sweep.mat');
d_loc = load(loc_path, 'beta_list', 'rmse_R_med', 'rmse_theta_med', ...
    'rmse_v_med', 'n_mc');

beta_merged  = double(d_loc.beta_list(:)');
rmse_R_med     = d_loc.rmse_R_med;
rmse_theta_med = d_loc.rmse_theta_med;
rmse_v_med     = d_loc.rmse_v_med;

n_beta = numel(beta_merged);
method_labels = {'ZF (no SI suppression)', 'Null-space'};
snr_fixed = 0;
mc_loc = d_loc.n_mc;

fprintf('β_SI: [%s] (%d 档), MC=%d\n', num2str(beta_merged), n_beta, mc_loc);

% ==================== 3. 输出目录 ========================================
fig_dir = fullfile(pwd, 'fig');
if ~exist(fig_dir, 'dir'), mkdir(fig_dir); end

% ==================== 4. 出图 (Nature 风格, semilogy) =====================
colors    = {[0.902 0.294 0.208], [0.302 0.733 0.835]};   % 红(ZF) / 蓝(零空间)
markers   = {'o', 's'};
linestyle = {'-', '--'};
leg_str   = method_labels;

titles  = {'Angle', 'Velocity', 'Range'};
ylabels = {'Angle RMSE (deg)', 'Velocity RMSE (m/s)', 'Range RMSE (m)'};
datas   = {rmse_theta_med, rmse_v_med, rmse_R_med};
fnames  = {'angle', 'velocity', 'range'};

for fi = 1:3
    fig = figure('Color', 'w', 'Units', 'pixels', ...
        'Position', [120+fi*30, 160+fi*30, 620, 470]);
    hold on;

    for mi = 1:2
        semilogy(beta_merged, max(datas{fi}(mi, :), 1e-12), ...
            'Color', colors{mi}, ...
            'Marker', markers{mi}, ...
            'LineStyle', linestyle{mi}, ...
            'LineWidth', 1.3, ...
            'MarkerSize', 6.0, ...
            'MarkerFaceColor', 'w');
    end

    xlabel('Self-interference strength \beta_{SI} (relative to target)', ...
        'FontName', 'Times New Roman', 'FontSize', 10);
    ylabel(ylabels{fi}, 'FontName', 'Times New Roman', 'FontSize', 10);
    title(sprintf('%s RMSE vs SI Strength -- Robustness (SNR=%d dB)', ...
        titles{fi}, snr_fixed), ...
        'FontName', 'Times New Roman', 'FontSize', 10, 'FontWeight', 'normal');
    legend(leg_str, 'Location', 'northeastoutside', 'Box', 'on', ...
        'FontName', 'Times New Roman', 'FontSize', 9, 'Interpreter', 'none');

    xlim([beta_merged(1)*0.8, beta_merged(end)*1.3]);
    set(gca, 'XScale', 'log');
    set(gca, 'XTick', beta_merged);
    set(gca, 'XTickLabel', {'0.01', '0.1', '1', '10', '100', '1000'});

    % log-scale y limits spanning the data in integer powers of 10
    yvals = datas{fi}(:);
    yvals = yvals(~isnan(yvals) & yvals > 0);
    ylo = 10^floor(log10(min(yvals)));
    yhi = 10^ceil(log10(max(yvals)));
    ylim([ylo, yhi]);

    apply_nature_axes(gca);
    set(gca, 'YScale', 'log');

    ytick_vals = 10 .^ (floor(log10(ylo)) : ceil(log10(yhi)));
    set(gca, 'YTick', ytick_vals);
    set(gca, 'YTickLabel', ...
        cellfun(@(n) sprintf('10^{%s}', n), ...
        arrayfun(@(v) num2str(log10(v)), ytick_vals, 'UniformOutput', false), ...
        'UniformOutput', false));

    % 标注门限与 MC
    text(0.02, 0.02, sprintf('MC=%d, R_{max}=600 m', mc_loc), ...
        'Units', 'normalized', 'FontName', 'Times New Roman', ...
        'FontSize', 8, 'Color', [0.4 0.4 0.4]);

    base_path = fullfile(fig_dir, sprintf('fig_si_strength_merged_%s', fnames{fi}));
    savefig(fig, [base_path '.fig']);
    exportgraphics(fig, [base_path '.png'], 'Resolution', 300);
    close(fig);
    fprintf('  %s -> fig/ (.fig + .png)\n', fnames{fi});
end

% ==================== 5. 保存合并数据 =====================================
mat_path = fullfile(pwd, 'task_si_strength_sweep_merged.mat');
save(mat_path, 'beta_merged', 'snr_fixed', 'method_labels', ...
    'rmse_R_med', 'rmse_theta_med', 'rmse_v_med', 'mc_loc');
fprintf('\n数据已保存: %s\n', mat_path);

% ==================== 6. 打印合并汇总 =====================================
fprintf('\n══════════════════════════════════════════\n');
fprintf('  合并 RMSE 汇总 (median)\n');
fprintf('══════════════════════════════════════════\n');
for metric = {'距离', '角度', '速度'}
    switch metric{1}
        case '距离', data = rmse_R_med;     unit = 'm';
        case '角度', data = rmse_theta_med; unit = '°';
        case '速度', data = rmse_v_med;     unit = 'm/s';
    end
    fprintf('\n--- %s RMSE (%s) ---\n', metric{1}, unit);
    fprintf('%8s', 'β_SI');
    for mi = 1:2, fprintf('  %-24s', method_labels{mi}); end
    fprintf('\n');
    for bi = 1:n_beta
        fprintf('%8g', beta_merged(bi));
        for mi = 1:2, fprintf('  %24.6f', data(mi, bi)); end
        fprintf('\n');
    end
end

fprintf('\n完成: %s\n', char(datetime('now')));
