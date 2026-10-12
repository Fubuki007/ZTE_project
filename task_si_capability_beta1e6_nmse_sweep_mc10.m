function task_si_capability_beta1e6_nmse_sweep_mc10(quick_mode)
% Find the beta_SI=1e6 sensing boundary versus LS SI-channel NMSE.
% The SI estimator and cancellation follow scheme Eqs. (45)-(52). A finite
% NMSE is imposed only through the pilot noise Z_p in Eqs. (46)-(47).

if nargin < 1
    quick_mode = false;
end
if ~isscalar(quick_mode) || (~islogical(quick_mode) && ~ismember(quick_mode, [0, 1]))
    error('quick_mode must be a logical scalar.');
end

close all; clc; warning('off', 'all');
t_all = tic;

beta_SI = 1e6;
SNR_dB = 0;
pilot_len = 128;
if quick_mode
    n_mc = 1;
    nmse_db_list = [-160, -120, -60];
    output_stem = 'task_si_capability_beta1e6_nmse_sweep_smoke';
else
    n_mc = 10;
    nmse_db_list = [-160, -150, -140, -130, -120, -110, -100, -80, -60];
    output_stem = 'task_si_capability_beta1e6_nmse_sweep_mc10';
end
n_levels = numel(nmse_db_list);

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
p0.beta_SI = beta_SI;
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

rmse_R = NaN(n_levels, n_mc);
rmse_theta = NaN(n_levels, n_mc);
rmse_phi = NaN(n_levels, n_mc);
rmse_v = NaN(n_levels, n_mc);
detected_targets = zeros(n_levels, n_mc);
actual_nmse_db = NaN(n_levels, n_mc);
digital_suppression_db = NaN(n_levels, n_mc);
si_to_target_before_db = NaN(n_levels, n_mc);
residual_to_target_db = NaN(n_levels, n_mc);
elapsed_case_s = NaN(n_levels, n_mc);

fprintf('=== Corrected SI capability: LS-NMSE sensitivity ===\n');
fprintf('beta_SI=%.0e amplitude, nominal power ratio=%.1f dB\n', ...
    beta_SI, 20 * log10(beta_SI));
fprintf('NMSE grid: %s dB\n', mat2str(nmse_db_list));
fprintf('MC=%d, Ns=%d, L=%d, Nt=%d, Nr=%d, SNR=%g dB, pilot=%d\n\n', ...
    n_mc, p0.N, p0.K, Nt, Nr, SNR_dB, pilot_len);

for mc = 1:n_mc
    hsi_seed = 20271000 + mc;
    data_seed = 20272000 + mc;
    pilot_symbol_seed = 20273000 + mc;
    pilot_noise_seed = 20274000 + mc;

    hsi_cfg = struct( ...
        'model', 'ura_rician', 'Nt_total', Nt, 'Nr_total', Nr, ...
        'kappa_SI', 10, 'Ntx', p0.Ntx, 'Nty', p0.Nty, ...
        'Mx', p0.Mx, 'My', p0.My, 'd_lambda', 0.5, ...
        'theta_tx_deg', p0.theta_SI, 'phi_tx_deg', p0.phi_SI, ...
        'theta_rx_deg', p0.theta_SI, 'phi_rx_deg', p0.phi_SI, ...
        'seed', hsi_seed);
    H_SI = generate_HSI(hsi_cfg);

    p_ns = p0;
    p_ns.precoder_type = 'nullspace';
    p_ns.H_SI = H_SI;
    p_ns.H_SI_matrix = H_SI;

    rng(data_seed);
    tx_ns = generate_mimo_ofdm_waveform(p_ns);
    X_ns = tx_ns.X;
    clear tx_ns;

    rng(pilot_symbol_seed);
    X_pilot = local_unit_power_16qam(Nt, pilot_len);

    for level_idx = 1:n_levels
        t_case = tic;
        p_case = p_ns;
        p_case.sic_error_db = nmse_db_list(level_idx);
        p_case.SIC_pilot = X_pilot;

        % Resetting the seed gives every NMSE level the same unit pilot
        % noise direction and the same data AWGN realization.
        rng(pilot_noise_seed);
        [rx_sic, sim_info] = simulate_radar_channel_3d(X_ns, p_case);
        [rmse_R(level_idx, mc), rmse_theta(level_idx, mc), ...
            rmse_phi(level_idx, mc), rmse_v(level_idx, mc), ...
            detected_targets(level_idx, mc)] = ...
            local_estimation_metrics(rx_sic, X_ns, p_case);

        actual_nmse_db(level_idx, mc) = sim_info.sic.achieved_nmse_db;
        digital_suppression_db(level_idx, mc) = sim_info.sic.suppression_db;
        si_to_target_before_db(level_idx, mc) = local_power_ratio_db( ...
            sim_info.sic.si_power_before, sim_info.target_signal_power);
        residual_to_target_db(level_idx, mc) = local_power_ratio_db( ...
            sim_info.sic.si_power_after, sim_info.target_signal_power);
        elapsed_case_s(level_idx, mc) = toc(t_case);

        completed_mc = mc;
        completed_level = level_idx;
        save(checkpoint_file, 'beta_SI', 'SNR_dB', 'pilot_len', ...
            'n_mc', 'nmse_db_list', 'completed_mc', 'completed_level', ...
            'rmse_R', 'rmse_theta', 'rmse_phi', 'rmse_v', ...
            'detected_targets', 'actual_nmse_db', ...
            'digital_suppression_db', 'si_to_target_before_db', ...
            'residual_to_target_db', 'elapsed_case_s');

        fprintf(['MC=%02d/%02d NMSE=%7.1f dB | actual=%7.2f dB, ' ...
            'SIC=%7.2f dB, pre/target=%7.2f dB, res/target=%7.2f dB | ' ...
            'R=%.4f m, th=%.4f deg, v=%.4f m/s, det=%d | %.1f s\n'], ...
            completed_mc, n_mc, nmse_db_list(completed_level), ...
            actual_nmse_db(completed_level, completed_mc), ...
            digital_suppression_db(level_idx, mc), ...
            si_to_target_before_db(level_idx, mc), ...
            residual_to_target_db(level_idx, mc), ...
            rmse_R(level_idx, mc), rmse_theta(level_idx, mc), ...
            rmse_v(level_idx, mc), detected_targets(level_idx, mc), ...
            elapsed_case_s(level_idx, mc));
        clear rx_sic sim_info;
    end
    clear X_ns H_SI X_pilot;
end

rmse_R_rms = sqrt(mean(rmse_R.^2, 2, 'omitnan'));
rmse_theta_rms = sqrt(mean(rmse_theta.^2, 2, 'omitnan'));
rmse_phi_rms = sqrt(mean(rmse_phi.^2, 2, 'omitnan'));
rmse_v_rms = sqrt(mean(rmse_v.^2, 2, 'omitnan'));
detection_rate = mean(detected_targets == p0.num_targets, 2);
distance_acceptance_rate = mean( ...
    detected_targets == p0.num_targets & rmse_R <= 0.1, 2);

fprintf('\n=== Corrected NMSE-sensitivity summary ===\n');
for level_idx = 1:n_levels
    fprintf(['NMSE=%7.1f dB | SIC=%7.2f dB, res/target=%7.2f dB | ' ...
        'R=%.4f m, theta=%.4f deg, phi=%.4f deg, v=%.4f m/s | ' ...
        'det=%.1f%%, R<=0.1m=%.1f%%\n'], ...
        nmse_db_list(level_idx), ...
        mean(digital_suppression_db(level_idx, :), 'omitnan'), ...
        mean(residual_to_target_db(level_idx, :), 'omitnan'), ...
        rmse_R_rms(level_idx), rmse_theta_rms(level_idx), ...
        rmse_phi_rms(level_idx), rmse_v_rms(level_idx), ...
        100 * detection_rate(level_idx), ...
        100 * distance_acceptance_rate(level_idx));
end

total_elapsed_min = toc(t_all) / 60;
save(result_file, 'beta_SI', 'SNR_dB', 'pilot_len', 'n_mc', ...
    'nmse_db_list', 'rmse_R', 'rmse_theta', 'rmse_phi', 'rmse_v', ...
    'detected_targets', 'actual_nmse_db', 'digital_suppression_db', ...
    'si_to_target_before_db', 'residual_to_target_db', 'elapsed_case_s', ...
    'rmse_R_rms', 'rmse_theta_rms', 'rmse_phi_rms', 'rmse_v_rms', ...
    'detection_rate', 'distance_acceptance_rate', 'total_elapsed_min');
fprintf('\nSaved %s. Total time %.1f min.\n', result_file, total_elapsed_min);
diary off;
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
