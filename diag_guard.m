rng(42);
params = build_default_params();
params.K = 256; params.K_stream = 4;
params.comm_channel_type = 'random';
params.enable_SI = true; params.beta_SI = 0.02; params.SNR = 10;
params.fast_estimator.n_pad_v = 256;
params.precoder_type = 'lagrange';

Nt_total = params.Ntx * params.Nty; Nr_total = params.Mx * params.My;
hsi_cfg = struct('model','ura_rician','Nt_total',Nt_total,'Nr_total',Nr_total,...
    'kappa_SI',100,'Ntx',params.Ntx,'Nty',params.Nty,...
    'Mx',params.Mx,'My',params.My,'d_lambda',0.5,...
    'theta_tx_deg',params.theta_SI,'phi_tx_deg',params.phi_SI,...
    'theta_rx_deg',params.theta_SI,'phi_rx_deg',params.phi_SI,'seed',42);
H_SI = generate_HSI(hsi_cfg);
H_SI = H_SI / norm(H_SI,'fro') * sqrt(Nt_total*Nr_total);

tx_cfg = params; tx_cfg.H_SI = H_SI;
tx = generate_mimo_ofdm_waveform(tx_cfg);
tx_sig = tx.X;

fprintf('tx_signal ndims=%d, size=%s\n', ndims(tx_sig), mat2str(size(tx_sig)));

p3=params; p3.H_SI_matrix=H_SI;
rx3=simulate_radar_channel_3d(tx_sig,p3);

% Run estimator with debug prints
[th3,ph3,R3,v3,info3] = joint_estimator_fast(rx3,tx_sig,p3);

fprintf('Detected: %d\n', info3.detected_targets);
for i=1:info3.detected_targets
    d1=abs(v3(i)-params.v_true(1)); d2=abs(v3(i)-params.v_true(2));
    tv=params.v_true(1); if d1>d2, tv=params.v_true(2); end
    fprintf('P%d: R=%.2f v=%.3f th=%.3f | err_v=%.3f m/s\n',i,R3(i),v3(i),th3(i),v3(i)-tv);
end
