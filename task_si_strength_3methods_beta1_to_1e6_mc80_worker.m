function task_si_strength_3methods_beta1_to_1e6_mc80_worker(worker_id, quick_mode)
% One of four independent 20-MC workers for the beta_SI strength sweep.
% Methods: ZF, null-space, and null-space + paper LS-SIC (Eqs. 45-52).

if nargin < 2
    quick_mode = false;
end
if ~isscalar(worker_id) || ~ismember(worker_id, 1:4)
    error('worker_id must be an integer from 1 to 4.');
end
if ~isscalar(quick_mode) || ...
        (~islogical(quick_mode) && ~ismember(quick_mode, [0, 1]))
    error('quick_mode must be a logical scalar.');
end

close all; clc; warning('off', 'all');
maxNumCompThreads(2);
t_all = tic;

method_labels = {'ZF', 'Nullspace', 'Nullspace+SIC'};
n_methods = numel(method_labels);
beta_list = logspace(0, 6, 13);
SNR_dB = 0;
pilot_len = 128;

if quick_mode
    beta_list = [1, 1e3, 1e6];
    global_mc_indices = worker_id;
    output_stem = sprintf( ...
        'task_si_strength_3methods_beta1_to_1e6_smoke_part%02d', worker_id);
else
    mc_per_worker = 20;
    global_mc_indices = (worker_id - 1) * mc_per_worker + (1:mc_per_worker);
    output_stem = sprintf( ...
        'task_si_strength_3methods_beta1_to_1e6_mc80_part%02d', worker_id);
end

n_beta = numel(beta_list);
n_local_mc = numel(global_mc_indices);
result_file = fullfile(pwd, [output_stem '.mat']);
checkpoint_file = fullfile(pwd, [output_stem '_checkpoint.mat']);
log_file = fullfile(pwd, [output_stem '.log']);
if isfile(log_file), delete(log_file); end
diary(log_file); diary on;

p0 = build_default_params();
p0.theta_true = [24.63, 15.94];
p0.phi_true = [30.99, 13.58];
p0.R_true = [200.6, 210.4];
p0.v_true = [15.1, -5.4];
p0.alpha = [1.0, 0.8];
p0.num_targets = 2;
p0.enable_SI = true;
p0.enable_SIC = false;
p0.sic_use_true_channel = false;
p0.sic_error_db = [];
p0.SIC_pilot_len = pilot_len;
p0.SNR = SNR_dB;
p0.K_stream = 2;
p0.user_theta_rad = deg2rad(p0.theta_true(:));
p0.user_phi_rad = deg2rad(p0.phi_true(:));

if quick_mode
    p0.N = 256;
    p0.K = 32;
    p0.B = p0.N * 120e3;
    p0.Mx = 4;
    p0.My = 4;
    p0.fast_estimator.n_samp_r = min(128, p0.N);
    p0.fast_estimator.n_samp_l = 16;
    p0.fast_estimator.n_pad_v = p0.K;
    p0.joint_fft_3d.Na_x = p0.Mx;
    p0.joint_fft_3d.Na_y = p0.My;
    p0.joint_fft_3d.Nr = p0.N;
    p0.joint_fft_3d.Nv = p0.K;
else
    p0.K = 256;
    p0.Mx = 8;
    p0.My = 8;
    p0.joint_fft_3d.Na_x = p0.Mx;
    p0.joint_fft_3d.Na_y = p0.My;
    p0.fast_estimator.n_samp_l = 64;
    p0.fast_estimator.R_max_gate = 600;
end

Nt = p0.Ntx * p0.Nty;
Nr = p0.Mx * p0.My;

rmse_R = NaN(n_methods, n_beta, n_local_mc);
rmse_theta = NaN(n_methods, n_beta, n_local_mc);
rmse_phi = NaN(n_methods, n_beta, n_local_mc);
rmse_v = NaN(n_methods, n_beta, n_local_mc);
detected_targets = zeros(n_methods, n_beta, n_local_mc);
estimator_elapsed_s = NaN(n_methods, n_beta, n_local_mc);

spatial_suppression_db = NaN(1, n_local_mc);
actual_nmse_db = NaN(n_beta, n_local_mc);
digital_suppression_db = NaN(n_beta, n_local_mc);
total_suppression_db = NaN(n_beta, n_local_mc);
si_to_target_before_db = NaN(n_beta, n_local_mc);
residual_to_target_db = NaN(n_beta, n_local_mc);
elapsed_per_mc_s = NaN(1, n_local_mc);
full_path_relative_error = NaN(3, 1);

fprintf('=== SI-strength sweep worker %d/4 ===\n', worker_id);
fprintf('Global MC indices: %s\n', mat2str(global_mc_indices));
fprintf('beta_SI amplitude grid: %s\n', mat2str(beta_list, 5));
fprintf(['Methods: ZF / Nullspace / Nullspace+SIC; MC total=80; ' ...
    'SIC=paper thermal-AWGN LS baseline; SNR=%g dB\n'], SNR_dB);
fprintf('Ns=%d, L=%d, Nt=%d, Nr=%d, pilot=%d, MATLAB threads=2\n\n', ...
    p0.N, p0.K, Nt, Nr, pilot_len);

for local_mc = 1:n_local_mc
    t_mc = tic;
    global_mc = global_mc_indices(local_mc);
    hsi_seed = 20291000 + global_mc;
    data_seed = 20292000 + global_mc;
    data_noise_seed = 20293000 + global_mc;
    pilot_symbol_seed = 20294000 + global_mc;
    pilot_noise_seed = 20295000 + global_mc;

    hsi_cfg = struct( ...
        'model', 'ura_rician', 'Nt_total', Nt, 'Nr_total', Nr, ...
        'kappa_SI', 10, 'Ntx', p0.Ntx, 'Nty', p0.Nty, ...
        'Mx', p0.Mx, 'My', p0.My, 'd_lambda', 0.5, ...
        'theta_tx_deg', p0.theta_SI, 'phi_tx_deg', p0.phi_SI, ...
        'theta_rx_deg', p0.theta_SI, 'phi_rx_deg', p0.phi_SI, ...
        'seed', hsi_seed);
    H_SI = generate_HSI(hsi_cfg);

    % ---------------- ZF: Eq. (48), without transmit SI suppression -------
    p_zf = p0;
    p_zf.precoder_type = 'zf';
    p_zf.H_SI = H_SI;
    p_zf.H_SI_matrix = H_SI;
    rng(data_seed);
    tx_zf = generate_mimo_ofdm_waveform(p_zf);
    X_zf = tx_zf.X;
    clear tx_zf;
    [target_zf, target_info_zf] = local_target_cube(X_zf, p_zf);
    noise_std_zf = sqrt(target_info_zf.target_signal_power / ...
        10^(SNR_dB / 10) / 2);
    rng(data_noise_seed);
    base_zf = local_add_awgn(target_zf, noise_std_zf);
    clear target_zf;

    si_zf_unit_power = local_channel_output_power(H_SI, X_zf);
    for beta_idx = 1:n_beta
        rx_cube = local_add_channel_output( ...
            base_zf, beta_list(beta_idx) * H_SI, X_zf, p0.Mx, p0.My);
        t_est = tic;
        [rmse_R(1, beta_idx, local_mc), ...
            rmse_theta(1, beta_idx, local_mc), ...
            rmse_phi(1, beta_idx, local_mc), ...
            rmse_v(1, beta_idx, local_mc), ...
            detected_targets(1, beta_idx, local_mc)] = ...
            local_estimation_metrics(rx_cube, X_zf, p_zf);
        estimator_elapsed_s(1, beta_idx, local_mc) = toc(t_est);
        clear rx_cube;
    end

    if quick_mode
        full_path_relative_error(1) = local_validate_no_sic( ...
            base_zf, X_zf, p_zf, H_SI, beta_list(end), data_noise_seed);
    end
    clear base_zf X_zf;

    % ---------------- Null-space: Eq. (44) + Eq. (48) ---------------------
    p_ns = p0;
    p_ns.precoder_type = 'nullspace';
    p_ns.H_SI = H_SI;
    p_ns.H_SI_matrix = H_SI;
    rng(data_seed);
    tx_ns = generate_mimo_ofdm_waveform(p_ns);
    X_ns = tx_ns.X;
    clear tx_ns;
    [target_ns, target_info_ns] = local_target_cube(X_ns, p_ns);
    target_power_ns = target_info_ns.target_signal_power;
    noise_std_ns = sqrt(target_power_ns / 10^(SNR_dB / 10) / 2);
    rng(data_noise_seed);
    base_ns = local_add_awgn(target_ns, noise_std_ns);

    si_ns_unit_power = local_channel_output_power(H_SI, X_ns);
    spatial_suppression_db(local_mc) = local_power_ratio_db( ...
        si_zf_unit_power, si_ns_unit_power);

    for beta_idx = 1:n_beta
        rx_cube = local_add_channel_output( ...
            base_ns, beta_list(beta_idx) * H_SI, X_ns, p0.Mx, p0.My);
        t_est = tic;
        [rmse_R(2, beta_idx, local_mc), ...
            rmse_theta(2, beta_idx, local_mc), ...
            rmse_phi(2, beta_idx, local_mc), ...
            rmse_v(2, beta_idx, local_mc), ...
            detected_targets(2, beta_idx, local_mc)] = ...
            local_estimation_metrics(rx_cube, X_ns, p_ns);
        estimator_elapsed_s(2, beta_idx, local_mc) = toc(t_est);
        clear rx_cube;
    end

    if quick_mode
        full_path_relative_error(2) = local_validate_no_sic( ...
            base_ns, X_ns, p_ns, H_SI, beta_list(end), data_noise_seed);
    end

    % -------- Null-space + LS-SIC: Eqs. (45)-(52), thermal AWGN ----------
    rng(pilot_symbol_seed);
    X_pilot = local_unit_power_16qam(Nt, pilot_len);
    rng(pilot_noise_seed);
    [G_hat_beta1, ~] = estimate_si_channel_ls( ...
        H_SI, X_pilot, noise_std_ns, []);
    residual_channel = H_SI - G_hat_beta1;
    residual_power = local_channel_output_power(residual_channel, X_ns);

    rx_sic = local_add_channel_output( ...
        base_ns, residual_channel, X_ns, p0.Mx, p0.My);
    t_est = tic;
    [sic_R, sic_theta, sic_phi, sic_v, sic_detected] = ...
        local_estimation_metrics(rx_sic, X_ns, p_ns);
    sic_estimator_elapsed = toc(t_est);
    clear rx_sic;

    channel_error_energy = norm(residual_channel, 'fro')^2;
    hsi_energy = norm(H_SI, 'fro')^2;
    for beta_idx = 1:n_beta
        beta_value = beta_list(beta_idx);
        rmse_R(3, beta_idx, local_mc) = sic_R;
        rmse_theta(3, beta_idx, local_mc) = sic_theta;
        rmse_phi(3, beta_idx, local_mc) = sic_phi;
        rmse_v(3, beta_idx, local_mc) = sic_v;
        detected_targets(3, beta_idx, local_mc) = sic_detected;
        estimator_elapsed_s(3, beta_idx, local_mc) = sic_estimator_elapsed;

        si_before_power = beta_value^2 * si_ns_unit_power;
        zf_before_power = beta_value^2 * si_zf_unit_power;
        actual_nmse_db(beta_idx, local_mc) = 10 * log10( ...
            max(channel_error_energy, realmin) / ...
            max(beta_value^2 * hsi_energy, realmin));
        digital_suppression_db(beta_idx, local_mc) = ...
            local_power_ratio_db(si_before_power, residual_power);
        total_suppression_db(beta_idx, local_mc) = ...
            local_power_ratio_db(zf_before_power, residual_power);
        si_to_target_before_db(beta_idx, local_mc) = ...
            local_power_ratio_db(si_before_power, target_power_ns);
        residual_to_target_db(beta_idx, local_mc) = ...
            local_power_ratio_db(residual_power, target_power_ns);
    end

    if quick_mode
        full_path_relative_error(3) = local_validate_sic( ...
            target_ns, X_ns, p_ns, H_SI, X_pilot, ...
            beta_list(end), noise_std_ns, pilot_noise_seed);
        fprintf('Validation relative errors [ZF NS NS+SIC] = %s\n', ...
            mat2str(full_path_relative_error.', 4));
        if max(full_path_relative_error) > 1e-8
            error('Accelerated receive-cube assembly failed validation.');
        end
    end

    clear base_ns target_ns X_ns H_SI X_pilot residual_channel;
    elapsed_per_mc_s(local_mc) = toc(t_mc);
    completed_local_mc = local_mc;
    completed_global_mc = global_mc;

    save(checkpoint_file, 'worker_id', 'global_mc_indices', ...
        'completed_local_mc', 'completed_global_mc', 'beta_list', ...
        'method_labels', 'SNR_dB', 'pilot_len', 'rmse_R', ...
        'rmse_theta', 'rmse_phi', 'rmse_v', 'detected_targets', ...
        'estimator_elapsed_s', 'spatial_suppression_db', ...
        'actual_nmse_db', 'digital_suppression_db', ...
        'total_suppression_db', 'si_to_target_before_db', ...
        'residual_to_target_db', 'elapsed_per_mc_s', ...
        'full_path_relative_error');

    fprintf(['Completed global MC=%02d/80 (worker %d, local %02d/%02d) | ' ...
        'spatial=%.2f dB, SIC residual/target=%.2f dB | %.1f s\n'], ...
        completed_global_mc, worker_id, completed_local_mc, n_local_mc, ...
        spatial_suppression_db(local_mc), ...
        residual_to_target_db(end, local_mc), elapsed_per_mc_s(local_mc));
end

audit_notes = { ...
    'beta_SI is an amplitude coefficient and is sampled at half-decade intervals from 1 to 1e6.', ...
    'Every global MC uses a distinct Rician SI channel; all beta values and methods share that SI realization.', ...
    'ZF and null-space use the same communication-data seed and the same data-AWGN direction within each MC.', ...
    'Null-space precoding follows Eq. (44); LS-SIC follows Eqs. (45)-(52).', ...
    'SIC uses the paper thermal-AWGN pilot model (sic_error_db=[]), not a forced finite NMSE.', ...
    'With fixed thermal pilot noise, the LS channel-error term is independent of beta, so the SIC sensing curve is beta-invariant in this linear model.', ...
    'The model excludes ADC clipping, finite RF dynamic range, PA nonlinearity, phase noise, and time-varying SI channels.', ...
    'Plot smoothing is performed only after aggregation by PCHIP in log-log space; raw sampled points remain visible.'};

total_elapsed_min = toc(t_all) / 60;
save(result_file, 'worker_id', 'global_mc_indices', 'beta_list', ...
    'method_labels', 'SNR_dB', 'pilot_len', 'rmse_R', ...
    'rmse_theta', 'rmse_phi', 'rmse_v', 'detected_targets', ...
    'estimator_elapsed_s', 'spatial_suppression_db', ...
    'actual_nmse_db', 'digital_suppression_db', ...
    'total_suppression_db', 'si_to_target_before_db', ...
    'residual_to_target_db', 'elapsed_per_mc_s', ...
    'full_path_relative_error', 'audit_notes', 'total_elapsed_min');
fprintf('\nSaved %s. Worker time %.1f min.\n', result_file, total_elapsed_min);
diary off;
end

function [target_cube, info] = local_target_cube(X, p)
p_target = p;
p_target.enable_SI = false;
p_target.enable_SIC = false;
p_target.SNR = Inf;
[target_cube, info] = simulate_radar_channel_3d(X, p_target);
end

function power_value = local_channel_output_power(G, X)
Ns = size(X, 3);
L = size(X, 4);
Nt = size(G, 2);
Nr = size(G, 1);
power_sum = 0;
for l_idx = 1:L
    x_l = reshape(X(:, :, :, l_idx), Nt, Ns);
    y_l = G * x_l;
    power_sum = power_sum + sum(abs(y_l(:)).^2);
end
power_value = power_sum / (Nr * Ns * L);
end

function rx_cube = local_add_awgn(rx_cube, noise_std)
[Mx, My, Ns, L] = size(rx_cube);
for l_idx = 1:L
    rx_cube(:, :, :, l_idx) = rx_cube(:, :, :, l_idx) + ...
        noise_std * (randn(Mx, My, Ns, 'like', rx_cube) + ...
        1j * randn(Mx, My, Ns, 'like', rx_cube));
end
end

function rx_cube = local_add_channel_output(rx_cube, G, X, Mx, My)
Ns = size(X, 3);
L = size(X, 4);
Nt = size(G, 2);
for l_idx = 1:L
    x_l = reshape(X(:, :, :, l_idx), Nt, Ns);
    channel_l = G * x_l;
    rx_cube(:, :, :, l_idx) = rx_cube(:, :, :, l_idx) + ...
        reshape(channel_l, Mx, My, Ns);
end
end

function X_pilot = local_unit_power_16qam(Nt, Lp)
pilot_idx = randi([0, 15], Nt, Lp);
levels = [-3, -1, 1, 3] / sqrt(10);
i_idx = mod(pilot_idx, 4) + 1;
q_idx = floor(pilot_idx / 4) + 1;
X_pilot = levels(i_idx) + 1j * levels(q_idx);
end

function [rmse_R, rmse_theta, rmse_phi, rmse_v, detected] = ...
        local_estimation_metrics(rx_cube, X, p)
[theta_est, phi_est, range_est, velocity_est, info] = ...
    joint_estimator_fast(rx_cube, X, p);
comparison = evaluate_estimation( ...
    theta_est, phi_est, range_est, velocity_est, p, false);
rmse_R = comparison.rmse_R;
rmse_theta = comparison.rmse_theta;
rmse_phi = comparison.rmse_phi;
rmse_v = comparison.rmse_v;
detected = info.detected_targets;
end

function relative_error = local_validate_no_sic( ...
        base_cube, X, p, H_SI, beta_value, data_noise_seed)
p_full = p;
p_full.beta_SI = beta_value;
p_full.enable_SI = true;
p_full.enable_SIC = false;
rng(data_noise_seed);
rx_full = simulate_radar_channel_3d(X, p_full);
rx_fast = local_add_channel_output( ...
    base_cube, beta_value * H_SI, X, p.Mx, p.My);
relative_error = norm(rx_full(:) - rx_fast(:)) / ...
    max(norm(rx_full(:)), realmin);
end

function relative_error = local_validate_sic( ...
        target_cube, X, p, H_SI, X_pilot, beta_value, ...
        noise_std, pilot_noise_seed)
p_full = p;
p_full.beta_SI = beta_value;
p_full.enable_SI = true;
p_full.enable_SIC = true;
p_full.sic_use_true_channel = false;
p_full.sic_error_db = [];
p_full.SIC_pilot = X_pilot;
rng(pilot_noise_seed);
rx_full = simulate_radar_channel_3d(X, p_full);

rng(pilot_noise_seed);
[G_hat, ~] = estimate_si_channel_ls( ...
    beta_value * H_SI, X_pilot, noise_std, []);
residual_channel = beta_value * H_SI - G_hat;
rx_fast = local_add_channel_output( ...
    target_cube, residual_channel, X, p.Mx, p.My);
rx_fast = local_add_awgn(rx_fast, noise_std);
relative_error = norm(rx_full(:) - rx_fast(:)) / ...
    max(norm(rx_full(:)), realmin);
end

function ratio_db = local_power_ratio_db(numerator, denominator)
ratio_db = 10 * log10(max(real(numerator), realmin) / ...
    max(real(denominator), realmin));
end
