function task_si_strength_beta100000_fullsize_mc20()
% Full-size SI strength sweep: beta_SI=100000 with 20 Monte Carlo trials.
clear; close all; clc; warning('off', 'all');
t_all = tic;

log_path = fullfile(pwd, 'task_si_strength_beta100000_fullsize_mc20.log');
if isfile(log_path), delete(log_path); end
diary(log_path); diary on;

methods       = {'zf', 'nullspace', 'nullspace'};
sic_flags     = [false, false, true];
method_labels = {'ZF', 'Null-space', 'Null-space + digital SIC'};
beta_list     = 100000;
n_methods     = numel(methods);
n_beta        = numel(beta_list);
n_mc          = 20;
SNR_fixed     = 0;
L_val         = 256;
Mx_val        = 8;
My_val        = 8;

baseParams = build_default_params();
fprintf('=== Full-size SI strength sweep (MC=%d) ===\n', n_mc);
fprintf('Ns=%d, L=%d, Mrx=%d, beta_SI=[%s], SNR=%d dB\n\n', ...
    baseParams.N, L_val, Mx_val * My_val, num2str(beta_list), SNR_fixed);

baseParams.theta_true = [24.63, 15.94];
baseParams.phi_true   = [30.99, 13.58];
baseParams.R_true     = [200.6, 210.4];
baseParams.v_true     = [15.1, -5.4];
baseParams.alpha      = [1.0, 0.8];
baseParams.enable_SI  = true;
baseParams.beta_SI    = 100;
baseParams.enable_SIC = false;
baseParams.sic_use_true_channel = false;
baseParams.SIC_pilot_len = 128;
baseParams.SNR        = SNR_fixed;
baseParams.K          = L_val;
baseParams.K_stream   = 2;
baseParams.user_theta_rad = deg2rad(baseParams.theta_true(:));
baseParams.user_phi_rad   = deg2rad(baseParams.phi_true(:));
baseParams.Mx = Mx_val;
baseParams.My = My_val;
baseParams.joint_fft_3d.Na_x = Mx_val;
baseParams.joint_fft_3d.Na_y = My_val;
baseParams.fast_estimator.n_samp_l = 64;
baseParams.fast_estimator.R_max_gate = 600;

rng(20260731);
hsi_cfg = struct( ...
    'model', 'ura_rician', 'Nt_total', baseParams.Ntx * baseParams.Nty, ...
    'Nr_total', Mx_val * My_val, 'kappa_SI', 10, ...
    'Ntx', baseParams.Ntx, 'Nty', baseParams.Nty, ...
    'Mx', Mx_val, 'My', My_val, 'd_lambda', 0.5, ...
    'theta_tx_deg', baseParams.theta_SI, 'phi_tx_deg', baseParams.phi_SI, ...
    'theta_rx_deg', baseParams.theta_SI, 'phi_rx_deg', baseParams.phi_SI, ...
    'seed', 20260731);
H_SI = generate_HSI(hsi_cfg);

rng(20260801);
rng_seeds = randi(2^31 - 1, n_methods, n_beta, n_mc);
rmse_R = NaN(n_methods, n_beta, n_mc);
rmse_theta = NaN(n_methods, n_beta, n_mc);
rmse_v = NaN(n_methods, n_beta, n_mc);

for mi = 1:n_methods
    p_tx = baseParams;
    p_tx.precoder_type = methods{mi};
    p_tx.H_SI = H_SI;
    p_tx.H_SI_matrix = H_SI;

    for bi = 1:n_beta
        for mc = 1:n_mc
            p = p_tx;
            p.beta_SI = beta_list(bi);
            p.enable_SI = true;
            p.enable_SIC = sic_flags(mi);
            p.H_SI_matrix = H_SI;

            fprintf('  [%s beta=%g MC=%d/%d] ', ...
                method_labels{mi}, beta_list(bi), mc, n_mc);
            result = local_mc_rmse_full(rng_seeds(mi, bi, mc), p);
            rmse_R(mi, bi, mc) = result(1);
            rmse_theta(mi, bi, mc) = result(2);
            rmse_v(mi, bi, mc) = result(3);
            fprintf('-> R=%.4f m, th=%.4f deg, v=%.4f m/s\n', result);
        end
    end
end

rmse_R_rms = sqrt(mean(rmse_R .^ 2, 3, 'omitnan'));
rmse_theta_rms = sqrt(mean(rmse_theta .^ 2, 3, 'omitnan'));
rmse_v_rms = sqrt(mean(rmse_v .^ 2, 3, 'omitnan'));

fprintf('\n=== Full-size SI strength RMS results (MC=%d) ===\n', n_mc);
for bi = 1:n_beta
    fprintf('beta=%6d\n', beta_list(bi));
    for mi = 1:n_methods
        fprintf('  %-26s R=%.4f m, th=%.4f deg, v=%.4f m/s\n', ...
            method_labels{mi}, rmse_R_rms(mi, bi), ...
            rmse_theta_rms(mi, bi), rmse_v_rms(mi, bi));
    end
end

save('task_si_strength_beta100000_fullsize_mc20.mat', ...
    'beta_list', 'method_labels', 'n_mc', 'rmse_R', 'rmse_theta', 'rmse_v', ...
    'rmse_R_rms', 'rmse_theta_rms', 'rmse_v_rms');
fprintf('\nSaved MAT. Total time %.1f min\n', toc(t_all) / 60);
diary off;
end

function result = local_mc_rmse_full(seed, p)
rng(seed);
tx = generate_mimo_ofdm_waveform(p);
rx_cube = simulate_radar_channel_3d(tx.X, p);
[th, ph, range_est, velocity_est] = joint_estimator_fast(rx_cube, tx.X, p);
comparison = evaluate_estimation(th, ph, range_est, velocity_est, p, false);
if isfield(comparison, 'rmse_R') && ~isnan(comparison.rmse_R)
    result = [comparison.rmse_R, comparison.rmse_theta, comparison.rmse_v];
else
    result = [NaN, NaN, NaN];
end
end
