function task_si_capability_beta1e6_mc80(sic_error_db)
% Stress test for null-space precoding plus pilot-based digital SIC.
% beta_SI is an amplitude coefficient. beta_SI=1e6 is nominally 120 dB
% in power before channel and beamforming gains are included.

if nargin < 1
    sic_error_db = [];
end
if ~isempty(sic_error_db) && ...
        (~isscalar(sic_error_db) || ~isreal(sic_error_db) || ...
         isnan(sic_error_db) || sic_error_db > 0)
    error('sic_error_db must be empty, -Inf, or a real scalar <= 0 dB.');
end

close all; clc; warning('off', 'all');
t_all = tic;

output_stem = 'task_si_capability_beta1e6_mc80';
if ~isempty(sic_error_db)
    if isinf(sic_error_db)
        nmse_tag = 'neginf';
    else
        nmse_tag = strrep(sprintf('%g', abs(sic_error_db)), '.', 'p');
    end
    output_stem = sprintf('%s_nmse_m%s', output_stem, nmse_tag);
end
result_file = fullfile(pwd, [output_stem '.mat']);
checkpoint_file = fullfile(pwd, [output_stem '_checkpoint.mat']);
log_file = fullfile(pwd, [output_stem '.log']);
if isfile(log_file), delete(log_file); end
diary(log_file); diary on;

beta_SI = 1e6;
n_mc = 80;
n_methods = 2;
method_labels = {'Null-space', 'Null-space + digital SIC'};
SNR_dB = 0;
pilot_len = 128;

p0 = build_default_params();
p0.theta_true = [24.63, 15.94];
p0.phi_true = [30.99, 13.58];
p0.R_true = [200.6, 210.4];
p0.v_true = [15.1, -5.4];
p0.alpha = [1.0, 0.8];
p0.num_targets = 2;
p0.enable_SI = true;
p0.beta_SI = beta_SI;
p0.enable_SIC = false;
p0.sic_use_true_channel = false;
p0.SIC_pilot_len = pilot_len;
p0.sic_error_db = sic_error_db;
p0.SNR = SNR_dB;
p0.K = 256;
p0.K_stream = 2;
p0.user_theta_rad = deg2rad(p0.theta_true(:));
p0.user_phi_rad = deg2rad(p0.phi_true(:));
p0.Mx = 8;
p0.My = 8;
p0.joint_fft_3d.Na_x = p0.Mx;
p0.joint_fft_3d.Na_y = p0.My;
p0.fast_estimator.n_samp_l = 64;
p0.fast_estimator.R_max_gate = 600;

Nt = p0.Ntx * p0.Nty;
Nr = p0.Mx * p0.My;

rmse_R = NaN(n_methods, n_mc);
rmse_theta = NaN(n_methods, n_mc);
rmse_phi = NaN(n_methods, n_mc);
rmse_v = NaN(n_methods, n_mc);
detected_targets = zeros(n_methods, n_mc);

si_zf_before = NaN(1, n_mc);
si_ns_before = NaN(1, n_mc);
si_ns_after = NaN(1, n_mc);
target_power_ns = NaN(1, n_mc);
spatial_suppression_db = NaN(1, n_mc);
digital_suppression_db = NaN(1, n_mc);
total_suppression_db = NaN(1, n_mc);
si_to_target_before_db = NaN(1, n_mc);
residual_to_target_db = NaN(1, n_mc);
ls_channel_nmse_db = NaN(1, n_mc);
zf_comm_err = NaN(1, n_mc);
ns_comm_err = NaN(1, n_mc);
zf_si_leak = NaN(1, n_mc);
ns_si_leak = NaN(1, n_mc);
elapsed_per_mc_s = NaN(1, n_mc);

fprintf('=== SI capability stress test ===\n');
fprintf('beta_SI=%.0e amplitude, nominal power ratio=%.1f dB, MC=%d\n', ...
    beta_SI, 20 * log10(beta_SI), n_mc);
fprintf('Ns=%d, L=%d, Nt=%d, Nr=%d, SNR=%g dB, pilot=%d\n\n', ...
    p0.N, p0.K, Nt, Nr, SNR_dB, pilot_len);
if isempty(sic_error_db)
    fprintf(['SIC estimation mode: paper thermal-AWGN baseline. This mode ' ...
        'validates Eqs. (45)-(52) but does not impose a finite hardware ' ...
        'cancellation limit.\n\n']);
else
    fprintf('SIC estimation mode: controlled LS NMSE = %.1f dB.\n\n', ...
        sic_error_db);
end

for mc = 1:n_mc
    t_mc = tic;
    hsi_seed = 20261000 + mc;
    data_seed = 20262000 + mc;
    pilot_symbol_seed = 20263000 + mc;
    pilot_noise_seed = 20264000 + mc;
    data_noise_seed = 20265000 + mc;

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
    p_zf.enable_SIC = false;

    rng(data_seed);
    tx_zf = generate_mimo_ofdm_waveform(p_zf);
    si_zf_before(mc) = local_channel_output_power(beta_SI * H_SI, tx_zf.X);
    zf_comm_err(mc) = tx_zf.precoder_info.comm_err_avg;
    zf_si_leak(mc) = tx_zf.precoder_info.si_leak_avg;
    clear tx_zf;

    p_ns = p0;
    p_ns.precoder_type = 'nullspace';
    p_ns.H_SI = H_SI;
    p_ns.H_SI_matrix = H_SI;
    p_ns.enable_SIC = false;

    rng(data_seed);
    tx_ns = generate_mimo_ofdm_waveform(p_ns);
    X_ns = tx_ns.X;
    si_ns_before(mc) = local_channel_output_power(beta_SI * H_SI, X_ns);
    target_power_ns(mc) = local_target_power(X_ns, p_ns);
    ns_comm_err(mc) = tx_ns.precoder_info.comm_err_avg;
    ns_si_leak(mc) = tx_ns.precoder_info.si_leak_avg;

    rng(pilot_symbol_seed);
    X_pilot = local_unit_power_16qam(Nt, pilot_len);
    noise_std = sqrt((target_power_ns(mc) / 10^(SNR_dB / 10)) / 2);
    rng(pilot_noise_seed);
    G_true = beta_SI * H_SI;
    [G_hat, ~] = estimate_si_channel_ls( ...
        G_true, X_pilot, noise_std, sic_error_db);
    si_ns_after(mc) = local_channel_output_power(G_true - G_hat, X_ns);

    spatial_suppression_db(mc) = local_power_ratio_db(si_zf_before(mc), si_ns_before(mc));
    digital_suppression_db(mc) = local_power_ratio_db(si_ns_before(mc), si_ns_after(mc));
    total_suppression_db(mc) = local_power_ratio_db(si_zf_before(mc), si_ns_after(mc));
    si_to_target_before_db(mc) = local_power_ratio_db(si_ns_before(mc), target_power_ns(mc));
    residual_to_target_db(mc) = local_power_ratio_db(si_ns_after(mc), target_power_ns(mc));
    ls_channel_nmse_db(mc) = local_power_ratio_db( ...
        norm(G_true - G_hat, 'fro')^2, norm(G_true, 'fro')^2);

    rng(data_noise_seed);
    rx_ns = simulate_radar_channel_3d(X_ns, p_ns);
    [rmse_R(1, mc), rmse_theta(1, mc), rmse_phi(1, mc), rmse_v(1, mc), ...
        detected_targets(1, mc)] = local_estimation_metrics(rx_ns, X_ns, p_ns);
    clear rx_ns;

    p_sic = p_ns;
    p_sic.enable_SIC = true;
    p_sic.sic_use_true_channel = false;
    p_sic.SIC_pilot = X_pilot;
    rng(pilot_noise_seed);
    rx_sic = simulate_radar_channel_3d(X_ns, p_sic);
    [rmse_R(2, mc), rmse_theta(2, mc), rmse_phi(2, mc), rmse_v(2, mc), ...
        detected_targets(2, mc)] = local_estimation_metrics(rx_sic, X_ns, p_sic);
    clear rx_sic X_ns tx_ns G_true G_hat H_SI X_pilot;

    elapsed_per_mc_s(mc) = toc(t_mc);
    completed_mc = mc; %#ok<NASGU>
    save(checkpoint_file, 'beta_SI', 'n_mc', 'method_labels', 'completed_mc', ...
        'rmse_R', 'rmse_theta', 'rmse_phi', 'rmse_v', 'detected_targets', ...
        'si_zf_before', 'si_ns_before', 'si_ns_after', 'target_power_ns', ...
        'spatial_suppression_db', 'digital_suppression_db', ...
        'total_suppression_db', 'si_to_target_before_db', ...
        'residual_to_target_db', 'ls_channel_nmse_db', ...
        'zf_comm_err', 'ns_comm_err', 'zf_si_leak', 'ns_si_leak', ...
        'elapsed_per_mc_s');

    fprintf(['MC=%02d/%02d | spatial=%7.2f dB, digital=%7.2f dB, total=%7.2f dB, ' ...
        'res/target=%7.2f dB | NS+SIC R=%.4f m, th=%.4f deg, v=%.4f m/s, det=%d | %.1f s\n'], ...
        mc, n_mc, spatial_suppression_db(mc), digital_suppression_db(mc), ...
        total_suppression_db(mc), residual_to_target_db(mc), ...
        rmse_R(2, mc), rmse_theta(2, mc), rmse_v(2, mc), ...
        detected_targets(2, mc), elapsed_per_mc_s(mc));
end

rmse_R_rms = sqrt(mean(rmse_R.^2, 2, 'omitnan'));
rmse_theta_rms = sqrt(mean(rmse_theta.^2, 2, 'omitnan'));
rmse_phi_rms = sqrt(mean(rmse_phi.^2, 2, 'omitnan'));
rmse_v_rms = sqrt(mean(rmse_v.^2, 2, 'omitnan'));
detection_rate = mean(detected_targets == p0.num_targets, 2);
distance_acceptance_rate = mean( ...
    detected_targets == p0.num_targets & rmse_R <= 0.1, 2);

audit_notes = { ...
    'beta_SI is an amplitude coefficient; beta_SI=1e6 is nominally 120 dB in power.', ...
    'Each Monte Carlo trial uses a distinct Rician SI channel realization.', ...
    'ZF and null-space use the same communication data seed within each trial.', ...
    'Suppression is measured from actual receive SI sample power, not beta alone.', ...
    'The model is linear, static within a trial, and does not include ADC clipping or RF nonlinearities.', ...
    'Empty sic_error_db is the paper thermal-AWGN LS baseline and is not a finite hardware capability model.', ...
    'Finite sic_error_db is imposed through pilot noise Z_p before the unchanged LS estimator in Eqs. (46)-(47).'};

fprintf('\n=== MC=%d summary ===\n', n_mc);
fprintf('Null-space spatial suppression: mean %.2f dB, P05 %.2f dB, P95 %.2f dB\n', ...
    mean(spatial_suppression_db), local_percentile(spatial_suppression_db, 5), ...
    local_percentile(spatial_suppression_db, 95));
fprintf('Digital SIC suppression:        mean %.2f dB, P05 %.2f dB, P95 %.2f dB\n', ...
    mean(digital_suppression_db), local_percentile(digital_suppression_db, 5), ...
    local_percentile(digital_suppression_db, 95));
fprintf('Cascaded total suppression:      mean %.2f dB, P05 %.2f dB, P95 %.2f dB\n', ...
    mean(total_suppression_db), local_percentile(total_suppression_db, 5), ...
    local_percentile(total_suppression_db, 95));
fprintf('Residual SI / target:            mean %.2f dB, P05 %.2f dB, P95 %.2f dB\n', ...
    mean(residual_to_target_db), local_percentile(residual_to_target_db, 5), ...
    local_percentile(residual_to_target_db, 95));
fprintf('LS effective-channel NMSE:       mean %.2f dB\n\n', mean(ls_channel_nmse_db));

for mi = 1:n_methods
    fprintf(['%-26s R=%.4f m, theta=%.4f deg, phi=%.4f deg, v=%.4f m/s, ' ...
        'detection=%.1f%%, distance<=0.1m=%.1f%%\n'], ...
        method_labels{mi}, rmse_R_rms(mi), rmse_theta_rms(mi), ...
        rmse_phi_rms(mi), rmse_v_rms(mi), 100 * detection_rate(mi), ...
        100 * distance_acceptance_rate(mi));
end

total_elapsed_min = toc(t_all) / 60;
save(result_file, 'beta_SI', 'n_mc', 'method_labels', 'SNR_dB', 'pilot_len', ...
    'sic_error_db', ...
    'rmse_R', 'rmse_theta', 'rmse_phi', 'rmse_v', 'detected_targets', ...
    'rmse_R_rms', 'rmse_theta_rms', 'rmse_phi_rms', 'rmse_v_rms', ...
    'detection_rate', 'distance_acceptance_rate', ...
    'si_zf_before', 'si_ns_before', 'si_ns_after', 'target_power_ns', ...
    'spatial_suppression_db', 'digital_suppression_db', ...
    'total_suppression_db', 'si_to_target_before_db', ...
    'residual_to_target_db', 'ls_channel_nmse_db', ...
    'zf_comm_err', 'ns_comm_err', 'zf_si_leak', 'ns_si_leak', ...
    'elapsed_per_mc_s', 'total_elapsed_min', 'audit_notes');
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

function target_power = local_target_power(X, p)
Mx = p.Mx;
My = p.My;
Ns = p.N;
L = p.K;
delta_f = p.B / Ns;
kw = 2 * pi * p.d / p.lambda;
mx_vec = (0:Mx-1).';
my_vec = (0:My-1).';
nx_vec = (0:p.Ntx-1).';
ny_vec = (0:p.Nty-1).';

b_cell = cell(1, p.num_targets);
a_cell = cell(1, p.num_targets);
range_phase = cell(1, p.num_targets);
velocity_phase = cell(1, p.num_targets);
for q = 1:p.num_targets
    u = sind(p.theta_true(q)) * cosd(p.phi_true(q));
    v = sind(p.theta_true(q)) * sind(p.phi_true(q));
    b_cell{q} = exp(-1j * kw * mx_vec * u) * exp(-1j * kw * my_vec * v).';
    a_cell{q} = exp(1j * kw * nx_vec * u) * exp(1j * kw * ny_vec * v).';
    range_phase{q} = exp(1j * (0:Ns-1).' * (-4*pi*delta_f*p.R_true(q) / p.c));
    velocity_phase{q} = exp(1j * (0:L-1) * (4*pi*p.Ts*p.v_true(q)*p.fc / p.c));
end

power_sum = 0;
for l_idx = 1:L
    rx_l = zeros(Mx, My, Ns, 'like', X);
    x_l = X(:, :, :, l_idx);
    for q = 1:p.num_targets
        tx_eff = squeeze(sum(conj(a_cell{q}) .* x_l, [1 2]));
        echo_q = p.alpha(q) * tx_eff(:) .* range_phase{q} * velocity_phase{q}(l_idx);
        rx_l = rx_l + b_cell{q} .* reshape(echo_q, 1, 1, Ns);
    end
    power_sum = power_sum + sum(abs(rx_l(:)).^2);
end
target_power = power_sum / (Mx * My * Ns * L);
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
    value = samples(lower_idx) * (1 - fraction) + samples(upper_idx) * fraction;
end
end
