
rng(42);
params = build_default_params();
params.SNR = 10;
params.enable_SI = true;
params.beta_SI = 0.02;
params.fast_estimator.n_pad_v = 256;
params.comm_channel_type = 'random';
params.K_stream = 4;
params.precoder_type = 'lagrange';

% Auto-construct H_SI if missing
if ~isfield(params, 'H_SI') || isempty(params.H_SI)
    Nt_total = params.Ntx * params.Nty;
    Nr_total = params.Mx * params.My;
    hsi_cfg = struct('model', 'ura_rician', 'Nt_total', Nt_total, 'Nr_total', Nr_total, ...
        'kappa_SI', 10, 'Ntx', params.Ntx, 'Nty', params.Nty, ...
        'Mx', params.Mx, 'My', params.My, 'd_lambda', 0.5, ...
        'theta_tx_deg', params.theta_SI, 'phi_tx_deg', params.phi_SI, ...
        'theta_rx_deg', params.theta_SI, 'phi_rx_deg', params.phi_SI);
    params.H_SI = generate_HSI(hsi_cfg);
end

tx_cfg = params;
tx_cfg.N = params.N;
tx_cfg.K = params.K;
tx_cfg.mod_order = params.mod_order;
tx_cfg.Ntx = params.Ntx;
tx_cfg.Nty = params.Nty;
tx_cfg.K_stream = params.K_stream;
tx = generate_mimo_ofdm_waveform(tx_cfg);
tx_signal = tx.X;

rx_cube = simulate_radar_channel_3d(tx_signal, params);
[theta_est, phi_est, R_est, v_est, info] = joint_estimator_fast(rx_cube, tx_signal, params);

fprintf('Detected targets: %d\n', info.detected_targets);
fprintf('True:  v1=%.2f, v2=%.2f m/s\n', params.v_true(1), params.v_true(2));
fprintf('True:  R1=%.2f, R2=%.2f m\n', params.R_true(1), params.R_true(2));
fprintf('True:  th1=%.2f, th2=%.2f deg\n', params.theta_true(1), params.theta_true(2));

fprintf('Est:   v=[');
for i=1:info.detected_targets, fprintf('%.3f ', v_est(i)); end
fprintf('] m/s\n');
fprintf('Est:   R=[');
for i=1:info.detected_targets, fprintf('%.3f ', R_est(i)); end
fprintf('] m\n');
fprintf('Est:   th=[');
for i=1:info.detected_targets, fprintf('%.4f ', theta_est(i)); end
fprintf('] deg\n');

delta_v = params.c / (2 * params.fc * params.Ts * params.K);
fprintf('Delta_v = %.3f m/s\n', delta_v);
fprintf('True Doppler bins: nv1=%.3f, nv2=%.3f\n', ...
    params.v_true(1)/delta_v, params.v_true(2)/delta_v);

if info.detected_targets >= 2
    % Simple greedy matching
    err_v1 = v_est(1) - params.v_true(1);
    err_v2 = v_est(2) - params.v_true(2);
    alt_err1 = v_est(2) - params.v_true(1);
    alt_err2 = v_est(1) - params.v_true(2);
    if err_v1^2 + err_v2^2 > alt_err1^2 + alt_err2^2
        err_v1 = alt_err1; err_v2 = alt_err2;
    end
    fprintf('Velocity errors: d1=%.4f, d2=%.4f m/s\n', err_v1, err_v2);
    fprintf('RMSE_v = %.4f m/s\n', sqrt(mean([err_v1^2, err_v2^2])));
    fprintf('Error in bins: dnv1=%.3f, dnv2=%.3f\n', err_v1/delta_v, err_v2/delta_v);
end

% Also test with ZF precoder for comparison
params.precoder_type = 'zf';
tx_zf = generate_mimo_ofdm_waveform(tx_cfg);
tx_signal_zf = tx_zf.X;
rx_cube_zf = simulate_radar_channel_3d(tx_signal_zf, params);
[~, ~, ~, v_est_zf, info_zf] = joint_estimator_fast(rx_cube_zf, tx_signal_zf, params);
fprintf('\n--- ZF precoder ---\n');
fprintf('Detected: %d, v=[');
for i=1:info_zf.detected_targets, fprintf('%.3f ', v_est_zf(i)); end
fprintf('] m/s\n');
