% =========================================================================
% task_execution_time_zf_null.m
%   根据项目代码跑两张执行时间图，每张图两条曲线：
%     1. ZF        (precoder_type='zf')
%     2. Null-space (precoder_type='nullspace')
%
%   计时对象与 task_execution_time_sweep.m 一致：
%     每次估计 = simulate_radar_channel_3d + joint_estimator_fast
%     不包含波形预先生成时间，因此两条曲线会比较接近；
%     如要包含预编码设计时间，请在 benchmark_point 中把 generate_mimo_ofdm_waveform
%     一起计时。
%
%   输出:
%     fig/execution_time_vs_cpi_length_zf_null.fig/.png
%     fig/execution_time_vs_subcarriers_zf_null.fig/.png
%   运行:
%     matlab -batch "task_execution_time_zf_null"
% =========================================================================
function task_execution_time_zf_null()
t_total = tic;
warning('off', 'all');

methods       = {'zf', 'nullspace'};
method_labels = {'ZF', 'Null-space'};
n_methods     = numel(methods);

n_mc = 100;                 % 每次估计的蒙特卡洛计时次数
Ns_list = [512, 1024, 2048, 3168, 6336];
L_list  = [16, 32, 64, 128, 256];
fixed_L_for_Ns = 64;
fixed_Ns_for_L = 3168;
Mx_fixed = 4;
My_fixed = 4;
input_snr_db = 0;
seed_base = 20260729;

fprintf('Execution-time benchmark started: %s\n', char(datetime('now')));
fprintf('MC=%d, receiver=%dx%d, SNR=%g dB\n', ...
    n_mc, Mx_fixed, My_fixed, input_snr_db);
fprintf('Methods: %s\n', strjoin(method_labels, ' vs '));
fprintf('Ns sweep: %s (L=%d)\n', mat2str(Ns_list), fixed_L_for_Ns);
fprintf('L sweep:  %s (Ns=%d)\n\n', mat2str(L_list), fixed_Ns_for_L);

base_params = build_default_params();
base_params.theta_true = [24.63, 15.94];
base_params.phi_true   = [30.99, 13.58];
base_params.R_true     = [200.6, 210.4];
base_params.v_true     = [15.1, -5.4];
base_params.alpha      = [1.0, 0.8];
base_params.enable_SI = true;
base_params.beta_SI   = 0.1;
base_params.enable_SIC = false;   % 与原有计时脚本一致
base_params.SNR       = input_snr_db;
base_params.K_stream  = 2;
base_params.user_theta_rad = deg2rad(base_params.theta_true(:));
base_params.user_phi_rad   = deg2rad(base_params.phi_true(:));
base_params.Mx = Mx_fixed;
base_params.My = My_fixed;
base_params.joint_fft_3d.Na_x = Mx_fixed;
base_params.joint_fft_3d.Na_y = My_fixed;

Nt_total = base_params.Ntx * base_params.Nty;
Nr_total = Mx_fixed * My_fixed;

rng(seed_base - 1, 'twister');
hsi_cfg = struct( ...
    'model', 'ura_rician', ...
    'Nt_total', Nt_total, 'Nr_total', Nr_total, ...
    'kappa_SI', 10, ...
    'Ntx', base_params.Ntx, 'Nty', base_params.Nty, ...
    'Mx', Mx_fixed, 'My', My_fixed, ...
    'd_lambda', 0.5, ...
    'theta_tx_deg', base_params.theta_SI, ...
    'phi_tx_deg', base_params.phi_SI, ...
    'theta_rx_deg', base_params.theta_SI, ...
    'phi_rx_deg', base_params.phi_SI);
H_SI = generate_HSI(hsi_cfg);
base_params.H_SI_matrix = H_SI;
base_params.H_SI = H_SI;

rng(seed_base, 'twister');
ns_seeds = randi(2^31 - 1, n_methods, numel(Ns_list), n_mc + 1);
l_seeds = randi(2^31 - 1, n_methods, numel(L_list), n_mc + 1);

time_ns_all = NaN(n_methods, numel(Ns_list), n_mc);
time_L_all  = NaN(n_methods, numel(L_list), n_mc);

for mi = 1:n_methods
    method = methods{mi};
    fprintf('\n========== Method %d/%d: %s ==========\n', mi, n_methods, method_labels{mi});

    for idx = 1:numel(Ns_list)
        p = configure_dimensions(base_params, Ns_list(idx), fixed_L_for_Ns);
        p.precoder_type = method;
        fprintf('Ns=%4d: preparing waveform and warm-up ... ', Ns_list(idx));
        time_ns_all(mi, idx, :) = benchmark_point(p, squeeze(ns_seeds(mi, idx, :)), n_mc);
        fprintf('mean %.6f s, median %.6f s\n', ...
            mean(time_ns_all(mi, idx, :)), median(time_ns_all(mi, idx, :)));
        save_checkpoint();
    end

    fprintf('\n');
    for idx = 1:numel(L_list)
        p = configure_dimensions(base_params, fixed_Ns_for_L, L_list(idx));
        p.precoder_type = method;
        fprintf('L=%3d: preparing waveform and warm-up ... ', L_list(idx));
        time_L_all(mi, idx, :) = benchmark_point(p, squeeze(l_seeds(mi, idx, :)), n_mc);
        fprintf('mean %.6f s, median %.6f s\n', ...
            mean(time_L_all(mi, idx, :)), median(time_L_all(mi, idx, :)));
        save_checkpoint();
    end
end

time_ns_mean = squeeze(mean(time_ns_all, 3, 'omitnan'));
time_ns_median = squeeze(median(time_ns_all, 3, 'omitnan'));
time_ns_std = squeeze(std(time_ns_all, 0, 3, 'omitnan'));
time_L_mean = squeeze(mean(time_L_all, 3, 'omitnan'));
time_L_median = squeeze(median(time_L_all, 3, 'omitnan'));
time_L_std = squeeze(std(time_L_all, 0, 3, 'omitnan'));

elapsed_total_s = toc(t_total);
result_path = fullfile(pwd, 'task_execution_time_zf_null.mat');
save(result_path, ...
    'Ns_list', 'L_list', 'fixed_L_for_Ns', 'fixed_Ns_for_L', ...
    'Mx_fixed', 'My_fixed', 'input_snr_db', 'n_mc', 'seed_base', ...
    'methods', 'method_labels', ...
    'time_ns_all', 'time_L_all', ...
    'time_ns_mean', 'time_ns_median', 'time_ns_std', ...
    'time_L_mean', 'time_L_median', 'time_L_std', 'elapsed_total_s');

write_summary_tables();
create_and_save_figures();

fprintf('\nNs sweep mean time (s):\n');
for mi = 1:n_methods
    fprintf('  %-12s: %s\n', method_labels{mi}, sprintf('%.6f ', time_ns_mean(mi, :)));
end
fprintf('L sweep mean time (s):\n');
for mi = 1:n_methods
    fprintf('  %-12s: %s\n', method_labels{mi}, sprintf('%.6f ', time_L_mean(mi, :)));
end
fprintf('\nSaved data: %s\n', result_path);
fprintf('Benchmark completed in %.1f min: %s\n', ...
    elapsed_total_s / 60, char(datetime('now')));

    function save_checkpoint()
        elapsed_checkpoint_s = toc(t_total); %#ok<NASGU>
        save(fullfile(pwd, 'task_execution_time_zf_null_checkpoint.mat'), ...
            'Ns_list', 'L_list', 'fixed_L_for_Ns', 'fixed_Ns_for_L', ...
            'Mx_fixed', 'My_fixed', 'input_snr_db', 'n_mc', 'seed_base', ...
            'methods', 'method_labels', ...
            'time_ns_all', 'time_L_all', 'elapsed_checkpoint_s');
    end

    function write_summary_tables()
        ns_table = table(Ns_list(:), time_ns_mean(1,:)', time_ns_median(1,:)', time_ns_std(1,:)', ...
            nnz(~isnan(time_ns_all(1,1,:)))*ones(numel(Ns_list),1), ...
            'VariableNames', {'NumberOfSubcarriers', 'ZFMeanSeconds', ...
            'ZFMedianSeconds', 'ZFStdSeconds', 'MonteCarloRuns'});
        l_table = table(L_list(:), time_L_mean(1,:)', time_L_median(1,:)', time_L_std(1,:)', ...
            nnz(~isnan(time_L_all(1,1,:)))*ones(numel(L_list),1), ...
            'VariableNames', {'CPILength', 'ZFMeanSeconds', ...
            'ZFMedianSeconds', 'ZFStdSeconds', 'MonteCarloRuns'});
        writetable(ns_table, fullfile(pwd, 'execution_time_vs_subcarriers_zf.csv'));
        writetable(l_table, fullfile(pwd, 'execution_time_vs_cpi_length_zf.csv'));
    end

    function create_and_save_figures()
        fig_dir = fullfile(pwd, 'fig');
        png_dir = fullfile(pwd, 'png');
        if ~exist(fig_dir, 'dir'), mkdir(fig_dir); end
        if ~exist(png_dir, 'dir'), mkdir(png_dir); end

        fig_ns = create_benchmark_comparison_figure(Ns_list, time_ns_mean, ...
            'The number of subcarriers', ...
            'Impact of the number of subcarriers', 1);
        save_benchmark_figure(fig_ns, 'execution_time_vs_subcarriers_zf_null', fig_dir, png_dir);

        fig_L = create_benchmark_comparison_figure(L_list, time_L_mean, ...
            'CPI length', 'Impact of CPI length', 2);
        save_benchmark_figure(fig_L, 'execution_time_vs_cpi_length_zf_null', fig_dir, png_dir);

        close([fig_ns, fig_L]);
    end
end

function p = configure_dimensions(base_params, Ns, L)
p = base_params;
p.N = Ns;
p.B = Ns * 120e3;
p.K = L;
p.meta.delta_f = p.B / p.N;
p.meta.range_resolution = p.c / (2 * p.B);
p.meta.R_max = p.c / (2 * p.meta.delta_f);
p.joint_fft_3d.Nr = Ns;
p.joint_fft_3d.Nv = L;
p.fast_estimator.n_samp_r = min(256, Ns);
p.fast_estimator.n_samp_l = min(64, max(16, floor(L / 2)));
p.fast_estimator.n_pad_v = L;
end

function timings = benchmark_point(params, seeds, n_mc)
tx = generate_mimo_ofdm_waveform(params);
X_tx = tx.X;
clear tx;

rng(seeds(1), 'twister');
rx_cube = simulate_radar_channel_3d(X_tx, params);
joint_estimator_fast(rx_cube, X_tx, params);
clear rx_cube;
fprintf('timing ');

timings = NaN(1, n_mc);
for mc_idx = 1:n_mc
    rng(seeds(mc_idx + 1), 'twister');
    rx_cube = simulate_radar_channel_3d(X_tx, params);
    timer_id = tic;
    joint_estimator_fast(rx_cube, X_tx, params);
    timings(mc_idx) = toc(timer_id);
    clear rx_cube;
    if mod(mc_idx, 20) == 0
        fprintf('.');
    end
end
fprintf(' ');
end

function fig = create_benchmark_comparison_figure(x, y_mat, x_label_text, title_text, fig_index)
fig = figure('Color', 'w', 'Units', 'inches', ...
    'Position', [1.0 + 0.3 * fig_index, 1.0 + 0.3 * fig_index, 4.3, 3.35], ...
    'PaperPositionMode', 'auto', 'Visible', 'off', 'Name', title_text);
ax = axes('Parent', fig);
hold(ax, 'on');

colors    = {[0.08, 0.35, 0.52], [0.85, 0.15, 0.12]};
markers   = {'d', 's'};
linestyles = {'-', '--'};
labels    = {'ZF', 'Null-space'};

for k = 1:2
    loglog(ax, x, max(y_mat(k, :), 1e-12), ...
        'Color', colors{k}, ...
        'Marker', markers{k}, ...
        'LineStyle', linestyles{k}, ...
        'MarkerEdgeColor', colors{k}, ...
        'MarkerFaceColor', 'w', ...
        'MarkerSize', 5.2, ...
        'LineWidth', 1.35, ...
        'DisplayName', labels{k});
end

xlabel(ax, x_label_text, 'FontName', 'Times New Roman', 'FontSize', 10);
ylabel(ax, 'Execution time per estimation (s)', ...
    'FontName', 'Times New Roman', 'FontSize', 10);
title(ax, title_text, 'FontName', 'Times New Roman', ...
    'FontSize', 10, 'FontWeight', 'normal');
legend(ax, labels, 'Location', 'northwest', 'Box', 'on', ...
    'FontName', 'Times New Roman', 'FontSize', 8);
xticks(ax, x);
xticklabels(ax, compose('%g', x));
xlim(ax, [min(x) * 0.92, max(x) * 1.08]);
y_finite = y_mat(isfinite(y_mat));
if ~isempty(y_finite)
    ylim(ax, [min(y_finite) * 0.85, max(y_finite) * 1.15]);
end
apply_nature_axes(ax);
hold(ax, 'off');
end

function save_benchmark_figure(fig, base_name, fig_dir, png_dir)
savefig(fig, fullfile(fig_dir, [base_name, '.fig']));
exportgraphics(fig, fullfile(png_dir, [base_name, '.png']), ...
    'Resolution', 600);
exportgraphics(fig, fullfile(png_dir, [base_name, '.pdf']), ...
    'ContentType', 'vector');
end
