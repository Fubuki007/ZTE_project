function task_si_capability_beta1e5_beta1e6_boundary_mc80(quick_mode)
% Compare beta_SI=1e5 and 1e6 near the null-space + LS-SIC boundary.
% The implementation preserves scheme Eqs. (45)-(52). Paired beta/NMSE
% points satisfy 20*log10(beta_SI)+NMSE = constant and therefore produce
% the same residual channel for a shared H_SI and pilot-noise direction.

if nargin < 1
    quick_mode = false;
end
if ~isscalar(quick_mode) || ...
        (~islogical(quick_mode) && ~ismember(quick_mode, [0, 1]))
    error('quick_mode must be a logical scalar.');
end

close all; clc; warning('off', 'all');
t_all = tic;

beta_values = [1e5, 1e6];
effective_residual_db = 10:2.5:25;
nmse_db_grid = effective_residual_db - ...
    20 * log10(beta_values(:));
SNR_dB = 0;
pilot_len = 128;
n_beta = numel(beta_values);
n_levels = numel(effective_residual_db);

if quick_mode
    n_mc = 1;
    effective_residual_db = [10, 17.5, 25];
    nmse_db_grid = effective_residual_db - ...
        20 * log10(beta_values(:));
    n_levels = numel(effective_residual_db);
    output_stem = 'task_si_capability_beta1e5_beta1e6_boundary_smoke';
else
    n_mc = 80;
    output_stem = 'task_si_capability_beta1e5_beta1e6_boundary_mc80';
end

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
p0.enable_SIC = true;
p0.sic_use_true_channel = false;
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

rmse_R = NaN(n_beta, n_levels, n_mc);
rmse_theta = NaN(n_beta, n_levels, n_mc);
rmse_phi = NaN(n_beta, n_levels, n_mc);
rmse_v = NaN(n_beta, n_levels, n_mc);
detected_targets = zeros(n_beta, n_levels, n_mc);
actual_nmse_db = NaN(n_beta, n_levels, n_mc);
digital_suppression_db = NaN(n_beta, n_levels, n_mc);
total_suppression_db = NaN(n_beta, n_levels, n_mc);
si_to_target_before_db = NaN(n_beta, n_levels, n_mc);
residual_to_target_db = NaN(n_beta, n_levels, n_mc);
spatial_suppression_db = NaN(1, n_mc);
paired_channel_error = NaN(n_levels, n_mc);
estimator_elapsed_s = NaN(n_levels, n_mc);
elapsed_per_mc_s = NaN(1, n_mc);
full_path_relative_error = NaN;

fprintf('=== beta_SI=1e5/1e6 boundary test: null-space + LS-SIC ===\n');
fprintf('beta amplitudes: %s; nominal power ratios: %s dB\n', ...
    mat2str(beta_values), mat2str(20 * log10(beta_values)));
fprintf('paired beta-power + NMSE levels: %s dB\n', ...
    mat2str(effective_residual_db));
for beta_idx = 1:n_beta
    fprintf('beta=%.0e NMSE grid: %s dB\n', beta_values(beta_idx), ...
        mat2str(nmse_db_grid(beta_idx, :)));
end
fprintf(['MC=%d, Ns=%d, L=%d, Nt=%d, Nr=%d, SNR=%g dB, pilot=%d. ' ...
    'Distance acceptance: detected Q=%d and RMSE<=0.1 m.\n\n'], ...
    n_mc, p0.N, p0.K, Nt, Nr, SNR_dB, pilot_len, p0.num_targets);

for mc = 1:n_mc
    t_mc = tic;
    hsi_seed = 20281000 + mc;
    data_seed = 20282000 + mc;
    pilot_symbol_seed = 20283000 + mc;
    pilot_noise_seed = 20284000 + mc;

    hsi_cfg = struct( ...
        'model', 'ura_rician', 'Nt_total', Nt, 'Nr_total', Nr, ...
        'kappa_SI', 10, 'Ntx', p0.Ntx, 'Nty', p0.Nty, ...
        'Mx', p0.Mx, 'My', p0.My, 'd_lambda', 0.5, ...
        'theta_tx_deg', p0.theta_SI, 'phi_tx_deg', p0.phi_SI, ...
        'theta_rx_deg', p0.theta_SI, 'phi_rx_deg', p0.phi_SI, ...
        'seed', hsi_seed);
    H_SI = generate_HSI(hsi_cfg);

    p_zf = p0;
    p_zf.precoder_type = 'zf';
    p_zf.H_SI = H_SI;
    p_zf.H_SI_matrix = H_SI;
    rng(data_seed);
    tx_zf = generate_mimo_ofdm_waveform(p_zf);
    si_zf_unit_power = local_channel_output_power(H_SI, tx_zf.X);
    clear tx_zf;

    p_ns = p0;
    p_ns.precoder_type = 'nullspace';
    p_ns.H_SI = H_SI;
    p_ns.H_SI_matrix = H_SI;
    rng(data_seed);
    tx_ns = generate_mimo_ofdm_waveform(p_ns);
    X_ns = tx_ns.X;
    clear tx_ns;
    si_ns_unit_power = local_channel_output_power(H_SI, X_ns);
    spatial_suppression_db(mc) = local_power_ratio_db( ...
        si_zf_unit_power, si_ns_unit_power);

    % Eqs. (48)-(51) can be assembled as target + AWGN + (G-G_hat)X.
    % The target and data AWGN are common to every paired beta/NMSE case.
    p_target = p_ns;
    p_target.enable_SI = false;
    p_target.enable_SIC = false;
    p_target.SNR = Inf;
    [base_cube, target_info] = simulate_radar_channel_3d(X_ns, p_target);
    target_power = target_info.target_signal_power;
    noise_std = sqrt((target_power / 10^(SNR_dB / 10)) / 2);

    rng(pilot_symbol_seed);
    X_pilot = local_unit_power_16qam(Nt, pilot_len);

    % Consume exactly the pilot-noise draws that precede data AWGN in the
    % original simulator. This makes the quick full-path comparison exact.
    rng(pilot_noise_seed);
    estimate_si_channel_ls(beta_values(1) * H_SI, X_pilot, noise_std, ...
        nmse_db_grid(1, 1));
    base_cube = local_add_awgn(base_cube, noise_std);

    for level_idx = 1:n_levels
        error_channels = cell(1, n_beta);
        for beta_idx = 1:n_beta
            G_true = beta_values(beta_idx) * H_SI;
            rng(pilot_noise_seed);
            [G_hat, sic_info] = estimate_si_channel_ls( ...
                G_true, X_pilot, noise_std, ...
                nmse_db_grid(beta_idx, level_idx));
            error_channels{beta_idx} = G_true - G_hat;

            si_before_power = beta_values(beta_idx)^2 * si_ns_unit_power;
            zf_before_power = beta_values(beta_idx)^2 * si_zf_unit_power;
            residual_power = local_channel_output_power( ...
                error_channels{beta_idx}, X_ns);
            actual_nmse_db(beta_idx, level_idx, mc) = ...
                sic_info.achieved_nmse_db;
            digital_suppression_db(beta_idx, level_idx, mc) = ...
                local_power_ratio_db(si_before_power, residual_power);
            total_suppression_db(beta_idx, level_idx, mc) = ...
                local_power_ratio_db(zf_before_power, residual_power);
            si_to_target_before_db(beta_idx, level_idx, mc) = ...
                local_power_ratio_db(si_before_power, target_power);
            residual_to_target_db(beta_idx, level_idx, mc) = ...
                local_power_ratio_db(residual_power, target_power);
        end

        paired_channel_error(level_idx, mc) = norm( ...
            error_channels{1} - error_channels{2}, 'fro') / ...
            max(norm(error_channels{2}, 'fro'), realmin);
        if paired_channel_error(level_idx, mc) > 1e-8
            error('Paired residual channels diverged: %.3e', ...
                paired_channel_error(level_idx, mc));
        end

        rx_cube = local_add_channel_output( ...
            base_cube, error_channels{2}, X_ns, p0.Mx, p0.My);

        if quick_mode && mc == 1 && level_idx == 1
            p_full = p_ns;
            p_full.beta_SI = beta_values(2);
            p_full.sic_error_db = nmse_db_grid(2, level_idx);
            p_full.SIC_pilot = X_pilot;
            rng(pilot_noise_seed);
            rx_full = simulate_radar_channel_3d(X_ns, p_full);
            full_path_relative_error = norm(rx_full(:) - rx_cube(:)) / ...
                max(norm(rx_full(:)), realmin);
            fprintf('Full/accelerated cube relative error: %.3e\n', ...
                full_path_relative_error);
            if full_path_relative_error > 1e-8
                error('Accelerated Eq. (51) assembly failed validation.');
            end
            clear rx_full;
        end

        t_estimator = tic;
        [case_R, case_theta, case_phi, case_v, case_detected] = ...
            local_estimation_metrics(rx_cube, X_ns, p_ns);
        estimator_elapsed_s(level_idx, mc) = toc(t_estimator);
        for beta_idx = 1:n_beta
            rmse_R(beta_idx, level_idx, mc) = case_R;
            rmse_theta(beta_idx, level_idx, mc) = case_theta;
            rmse_phi(beta_idx, level_idx, mc) = case_phi;
            rmse_v(beta_idx, level_idx, mc) = case_v;
            detected_targets(beta_idx, level_idx, mc) = case_detected;
        end
        clear rx_cube error_channels;

        completed_mc = mc;
        completed_level = level_idx;
        save(checkpoint_file, 'beta_values', 'effective_residual_db', ...
            'nmse_db_grid', 'n_mc', 'completed_mc', 'completed_level', ...
            'rmse_R', 'rmse_theta', 'rmse_phi', 'rmse_v', ...
            'detected_targets', 'actual_nmse_db', ...
            'spatial_suppression_db', 'digital_suppression_db', ...
            'total_suppression_db', 'si_to_target_before_db', ...
            'residual_to_target_db', 'paired_channel_error', ...
            'estimator_elapsed_s', 'elapsed_per_mc_s', ...
            'full_path_relative_error');

        fprintf(['MC=%02d/%02d level=%4.1f dB | NMSE=[%6.1f,%6.1f] dB, ' ...
            'res/target=[%6.2f,%6.2f] dB | R=%.4f m, theta=%.4f deg, ' ...
            'v=%.4f m/s, det=%d, estimator=%.3f s, pair=%.2e\n'], ...
            completed_mc, n_mc, effective_residual_db(completed_level), ...
            nmse_db_grid(1, completed_level), ...
            nmse_db_grid(2, completed_level), ...
            residual_to_target_db(1, completed_level, completed_mc), ...
            residual_to_target_db(2, completed_level, completed_mc), ...
            case_R, case_theta, case_v, case_detected, ...
            estimator_elapsed_s(completed_level, completed_mc), ...
            paired_channel_error(completed_level, completed_mc));
    end

    elapsed_per_mc_s(mc) = toc(t_mc);
    fprintf('Completed MC=%02d/%02d in %.1f s.\n\n', ...
        mc, n_mc, elapsed_per_mc_s(mc));
    clear base_cube X_ns H_SI X_pilot;
end

rmse_R_rms = sqrt(mean(rmse_R.^2, 3, 'omitnan'));
rmse_theta_rms = sqrt(mean(rmse_theta.^2, 3, 'omitnan'));
rmse_phi_rms = sqrt(mean(rmse_phi.^2, 3, 'omitnan'));
rmse_v_rms = sqrt(mean(rmse_v.^2, 3, 'omitnan'));
detection_rate = mean(detected_targets == p0.num_targets, 3);
distance_success = detected_targets == p0.num_targets & rmse_R <= 0.1;
distance_acceptance_rate = mean(distance_success, 3);
distance_acceptance_ci95 = NaN(n_beta, n_levels, 2);
for beta_idx = 1:n_beta
    for level_idx = 1:n_levels
        successes = sum(distance_success(beta_idx, level_idx, :));
        [ci_low, ci_high] = local_wilson_interval(successes, n_mc);
        distance_acceptance_ci95(beta_idx, level_idx, :) = ...
            [ci_low, ci_high];
    end
end

fprintf('\n=== MC=%d boundary summary ===\n', n_mc);
fprintf('Null-space spatial suppression: mean %.2f dB, P05 %.2f, P95 %.2f dB\n', ...
    mean(spatial_suppression_db, 'omitnan'), ...
    local_percentile(spatial_suppression_db, 5), ...
    local_percentile(spatial_suppression_db, 95));
fprintf('Max paired residual-channel mismatch: %.3e\n', ...
    max(paired_channel_error(:)));
fprintf('Estimator time: mean %.3f s, P95 %.3f s, max %.3f s\n', ...
    mean(estimator_elapsed_s(:), 'omitnan'), ...
    local_percentile(estimator_elapsed_s(:), 95), ...
    max(estimator_elapsed_s(:)));

for beta_idx = 1:n_beta
    fprintf('\n--- beta_SI=%.0e (nominal %.1f dB power) ---\n', ...
        beta_values(beta_idx), 20 * log10(beta_values(beta_idx)));
    for level_idx = 1:n_levels
        ci = 100 * squeeze(distance_acceptance_ci95( ...
            beta_idx, level_idx, :));
        fprintf(['NMSE=%6.1f dB | digital=%6.2f dB, total=%6.2f dB, ' ...
            'res/target=%6.2f dB | R=%.4f m, th=%.4f deg, ' ...
            'phi=%.4f deg, v=%.4f m/s | accept=%5.1f%% ' ...
            '(95%% CI %.1f-%.1f%%), det=%5.1f%%\n'], ...
            nmse_db_grid(beta_idx, level_idx), ...
            mean(digital_suppression_db(beta_idx, level_idx, :), 3), ...
            mean(total_suppression_db(beta_idx, level_idx, :), 3), ...
            mean(residual_to_target_db(beta_idx, level_idx, :), 3), ...
            rmse_R_rms(beta_idx, level_idx), ...
            rmse_theta_rms(beta_idx, level_idx), ...
            rmse_phi_rms(beta_idx, level_idx), ...
            rmse_v_rms(beta_idx, level_idx), ...
            100 * distance_acceptance_rate(beta_idx, level_idx), ...
            ci(1), ci(2), 100 * detection_rate(beta_idx, level_idx));
    end
end

audit_notes = { ...
    'beta_SI is an amplitude coefficient: 1e5 and 1e6 equal nominal 100 and 120 dB power ratios.', ...
    'Null-space precoding follows Eq. (44); digital LS-SIC follows Eqs. (45)-(52).', ...
    'Controlled NMSE is imposed only by scaling pilot noise Z_p before the unchanged Eq. (47) LS estimator.', ...
    'Within each MC, both beta values share H_SI, communication symbols, pilot symbols, pilot-noise direction, target echo, and data AWGN.', ...
    'Paired points keep 20log10(beta_SI)+NMSE constant, so Eq. (51) gives the same residual channel; numerical mismatch is recorded and checked.', ...
    'The model is linear and does not include ADC clipping, RF dynamic-range limits, phase noise, PA nonlinearity, or time-varying SI channels.', ...
    'Distance acceptance requires exactly Q detections and per-trial distance RMSE <= 0.1 m.', ...
    'A 95% Wilson interval is reported because 80/80 successes do not prove a 100% population success rate.'};

total_elapsed_min = toc(t_all) / 60;
save(result_file, 'beta_values', 'effective_residual_db', 'nmse_db_grid', ...
    'SNR_dB', 'pilot_len', 'n_mc', 'rmse_R', 'rmse_theta', ...
    'rmse_phi', 'rmse_v', 'detected_targets', 'actual_nmse_db', ...
    'spatial_suppression_db', 'digital_suppression_db', ...
    'total_suppression_db', 'si_to_target_before_db', ...
    'residual_to_target_db', 'paired_channel_error', ...
    'estimator_elapsed_s', 'elapsed_per_mc_s', ...
    'full_path_relative_error', 'rmse_R_rms', 'rmse_theta_rms', ...
    'rmse_phi_rms', 'rmse_v_rms', 'detection_rate', ...
    'distance_acceptance_rate', 'distance_acceptance_ci95', ...
    'total_elapsed_min', 'audit_notes');
fprintf('\nSaved %s. Total time %.1f min.\n', result_file, total_elapsed_min);
diary off;
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
    residual_l = G * x_l;
    rx_cube(:, :, :, l_idx) = rx_cube(:, :, :, l_idx) + ...
        reshape(residual_l, Mx, My, Ns);
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

function ratio_db = local_power_ratio_db(numerator, denominator)
ratio_db = 10 * log10(max(real(numerator), realmin) / ...
    max(real(denominator), realmin));
end

function [lower, upper] = local_wilson_interval(successes, trials)
z = 1.95996398454005;
phat = successes / trials;
denominator = 1 + z^2 / trials;
center = (phat + z^2 / (2 * trials)) / denominator;
half_width = z * sqrt(phat * (1 - phat) / trials + ...
    z^2 / (4 * trials^2)) / denominator;
lower = max(0, center - half_width);
upper = min(1, center + half_width);
end

function value = local_percentile(samples, percentile)
samples = sort(samples(isfinite(samples)));
if isempty(samples)
    value = NaN;
    return;
end
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
