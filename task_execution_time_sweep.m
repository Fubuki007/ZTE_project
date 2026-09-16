function task_execution_time_sweep(axis_profile)
%TASK_EXECUTION_TIME_SWEEP Benchmark the proposed estimator over Ns and L.
% Each point reports the mean of 100 independently simulated estimations.

if nargin < 1 || isempty(axis_profile)
    axis_profile = 'engineering';
end
axis_profile = validatestring(axis_profile, {'engineering', 'paper'});
if strcmp(axis_profile, 'paper')
    output_tag = '_paper_axis_sion';
else
    output_tag = '_sion';
end

t_total = tic;
warning_state = warning;
warning('off', 'all');
cleanup_obj = onCleanup(@() warning(warning_state)); %#ok<NASGU>

log_path = fullfile(pwd, ['execution_time_sweep', output_tag, '.log']);
if isfile(log_path)
    delete(log_path);
end
diary(log_path);
diary on;
diary_cleanup = onCleanup(@() diary('off')); %#ok<NASGU>

% Benchmark configuration. The first call at every point is a warm-up and
% is deliberately excluded from the 100 Monte Carlo timing samples.
n_mc = 100;
if strcmp(axis_profile, 'paper')
    % Fig. 6(c-d): eight quarter-decade points from 10^1.5 to 10^3.25.
    Ns_list = round(logspace(1.5, 3.25, 8));
    L_list = round(logspace(1.5, 3.25, 8));
else
    Ns_list = [512, 1024, 2048, 3168, 6336];
    L_list = [16, 32, 64, 128, 256];
end
fixed_L_for_Ns = 64;
fixed_Ns_for_L = 3168;
Mx_fixed = 4;
My_fixed = 4;
input_snr_db = 0;
seed_base = 20260729;

fprintf('Execution-time benchmark started: %s\n', char(datetime('now')));
fprintf('Axis profile: %s\n', axis_profile);
fprintf('MC=%d, receiver=%dx%d, SNR=%g dB, SI=ON, beta=0.1, SIC=OFF\n', ...
    n_mc, Mx_fixed, My_fixed, input_snr_db);
fprintf('Ns sweep: %s (L=%d)\n', mat2str(Ns_list), fixed_L_for_Ns);
fprintf('L sweep:  %s (Ns=%d)\n\n', mat2str(L_list), fixed_Ns_for_L);

base_params = build_default_params();
base_params.theta_true = [24.63, 15.94];
base_params.phi_true = [30.99, 13.58];
base_params.R_true = [200.6, 210.4];
base_params.v_true = [15.1, -5.4];
base_params.alpha = [1.0, 0.8];
base_params.enable_SI = true;
base_params.beta_SI = 0.1;
% The simulator's SIC path subtracts the injected matrix SI exactly. Keep
% it disabled so SI-ON produces a genuinely SI-contaminated receive cube.
base_params.enable_SIC = false;
base_params.precoder_type = 'zf';
base_params.SNR = input_snr_db;
base_params.K_stream = 2;
base_params.user_theta_rad = deg2rad(base_params.theta_true(:));
base_params.user_phi_rad = deg2rad(base_params.phi_true(:));
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
base_params.H_SI_matrix = generate_HSI(hsi_cfg);
base_params.H_SI = base_params.H_SI_matrix;
enable_SI = base_params.enable_SI;
beta_SI = base_params.beta_SI;
enable_SIC = base_params.enable_SIC;
precoder_type = base_params.precoder_type;

rng(seed_base, 'twister');
ns_seeds = randi(2^31 - 1, numel(Ns_list), n_mc + 1);
l_seeds = randi(2^31 - 1, numel(L_list), n_mc + 1);

time_ns_all = NaN(numel(Ns_list), n_mc);
time_L_all = NaN(numel(L_list), n_mc);

for idx = 1:numel(Ns_list)
    p = configure_dimensions(base_params, Ns_list(idx), fixed_L_for_Ns);
    fprintf('Ns=%4d: preparing waveform and warm-up ... ', Ns_list(idx));
    time_ns_all(idx, :) = benchmark_point(p, ns_seeds(idx, :), n_mc);
    fprintf('mean %.6f s, median %.6f s\n', ...
        mean(time_ns_all(idx, :)), median(time_ns_all(idx, :)));
    save_checkpoint();
end

fprintf('\n');
for idx = 1:numel(L_list)
    p = configure_dimensions(base_params, fixed_Ns_for_L, L_list(idx));
    fprintf('L=%3d: preparing waveform and warm-up ... ', L_list(idx));
    time_L_all(idx, :) = benchmark_point(p, l_seeds(idx, :), n_mc);
    fprintf('mean %.6f s, median %.6f s\n', ...
        mean(time_L_all(idx, :)), median(time_L_all(idx, :)));
    save_checkpoint();
end

time_ns_mean = mean(time_ns_all, 2, 'omitnan');
time_ns_median = median(time_ns_all, 2, 'omitnan');
time_ns_std = std(time_ns_all, 0, 2, 'omitnan');
time_L_mean = mean(time_L_all, 2, 'omitnan');
time_L_median = median(time_L_all, 2, 'omitnan');
time_L_std = std(time_L_all, 0, 2, 'omitnan');

elapsed_total_s = toc(t_total);
result_path = fullfile(pwd, ['task_execution_time_sweep', output_tag, '.mat']);
save(result_path, 'Ns_list', 'L_list', 'fixed_L_for_Ns', ...
    'fixed_Ns_for_L', 'Mx_fixed', 'My_fixed', 'input_snr_db', ...
    'n_mc', 'seed_base', 'axis_profile', 'time_ns_all', 'time_L_all', ...
    'time_ns_mean', 'time_ns_median', 'time_ns_std', ...
    'time_L_mean', 'time_L_median', 'time_L_std', 'elapsed_total_s', ...
    'enable_SI', 'beta_SI', 'enable_SIC', 'precoder_type');

write_summary_tables();
create_and_save_figures();

fprintf('\nNs sweep mean time (s):\n');
fprintf('  Ns=%4d: %.6f +/- %.6f\n', ...
    [Ns_list(:), time_ns_mean, time_ns_std].');
fprintf('L sweep mean time (s):\n');
fprintf('  L=%3d: %.6f +/- %.6f\n', ...
    [L_list(:), time_L_mean, time_L_std].');
fprintf('\nSaved data: %s\n', result_path);
fprintf('Benchmark completed in %.1f min: %s\n', ...
    elapsed_total_s / 60, char(datetime('now')));

    function save_checkpoint()
        elapsed_checkpoint_s = toc(t_total); %#ok<NASGU>
        save(fullfile(pwd, ['task_execution_time_sweep', output_tag, ...
            '_checkpoint.mat']), ...
            'Ns_list', 'L_list', 'fixed_L_for_Ns', 'fixed_Ns_for_L', ...
            'Mx_fixed', 'My_fixed', 'input_snr_db', 'n_mc', 'seed_base', ...
            'axis_profile', ...
            'time_ns_all', 'time_L_all', 'elapsed_checkpoint_s', ...
            'enable_SI', 'beta_SI', 'enable_SIC', 'precoder_type');
    end

    function write_summary_tables()
        ns_table = table(Ns_list(:), time_ns_mean, time_ns_median, ...
            time_ns_std, repmat(n_mc, numel(Ns_list), 1), ...
            'VariableNames', {'NumberOfSubcarriers', 'MeanSeconds', ...
            'MedianSeconds', 'StdSeconds', 'MonteCarloRuns'});
        l_table = table(L_list(:), time_L_mean, time_L_median, ...
            time_L_std, repmat(n_mc, numel(L_list), 1), ...
            'VariableNames', {'CPILength', 'MeanSeconds', ...
            'MedianSeconds', 'StdSeconds', 'MonteCarloRuns'});
        writetable(ns_table, fullfile(pwd, ...
            ['execution_time_vs_subcarriers', output_tag, '.csv']));
        writetable(l_table, fullfile(pwd, ...
            ['execution_time_vs_cpi_length', output_tag, '.csv']));
    end

    function create_and_save_figures()
        fig_dir = fullfile(pwd, 'fig');
        png_dir = fullfile(pwd, 'png');
        if ~exist(fig_dir, 'dir'), mkdir(fig_dir); end
        if ~exist(png_dir, 'dir'), mkdir(png_dir); end

        fig_ns = create_benchmark_figure(Ns_list, time_ns_mean, ...
            'The number of subcarriers', ...
            'Impact of the number of subcarriers', 1);
        save_benchmark_figure(fig_ns, ...
            ['execution_time_vs_subcarriers', output_tag], ...
            fig_dir, png_dir);

        fig_L = create_benchmark_figure(L_list, time_L_mean, ...
            'CPI length', 'Impact of CPI length', 2);
        save_benchmark_figure(fig_L, ...
            ['execution_time_vs_cpi_length', output_tag], ...
            fig_dir, png_dir);
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

% Warm-up uses a separate realization and is excluded from the benchmark.
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

function fig = create_benchmark_figure(x, y, x_label_text, title_text, fig_index)
fig = figure('Color', 'w', 'Units', 'inches', ...
    'Position', [1.0 + 0.3 * fig_index, 1.0 + 0.3 * fig_index, 4.3, 3.35], ...
    'PaperPositionMode', 'auto', 'Visible', 'off', 'Name', title_text);
ax = axes('Parent', fig);

loglog(ax, x, y, '-d', ...
    'Color', [0.08, 0.35, 0.52], ...
    'MarkerEdgeColor', [0.08, 0.35, 0.52], ...
    'MarkerFaceColor', 'w', ...
    'MarkerSize', 5.2, ...
    'LineWidth', 1.35, ...
    'DisplayName', 'Proposed estimator (SI-ON)');

xlabel(ax, x_label_text, 'FontName', 'Times New Roman', 'FontSize', 10);
ylabel(ax, 'Execution time per estimation (s)', ...
    'FontName', 'Times New Roman', 'FontSize', 10);
title(ax, title_text, 'FontName', 'Times New Roman', ...
    'FontSize', 10, 'FontWeight', 'normal');
legend(ax, 'Location', 'northwest', 'Box', 'on', ...
    'FontName', 'Times New Roman', 'FontSize', 8);
xticks(ax, x);
xticklabels(ax, compose('%g', x));
xlim(ax, [min(x) * 0.92, max(x) * 1.08]);
ylim(ax, [min(y) * 0.85, max(y) * 1.15]);
apply_nature_axes(ax);
end

function save_benchmark_figure(fig, base_name, fig_dir, png_dir)
savefig(fig, fullfile(fig_dir, [base_name, '.fig']));
exportgraphics(fig, fullfile(png_dir, [base_name, '.png']), ...
    'Resolution', 600);
exportgraphics(fig, fullfile(png_dir, [base_name, '.pdf']), ...
    'ContentType', 'vector');
end
