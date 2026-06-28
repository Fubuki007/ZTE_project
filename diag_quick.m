
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

dv = params.c/(2*params.fc*params.Ts*params.K);
fprintf('Delta_v=%.3f m/s, True bins: %.3f, %.3f\n',dv,params.v_true(1)/dv,params.v_true(2)/dv);

% TEST A: single target v=15.1
p1=params; p1.num_targets=1; p1.v_true=params.v_true(1);
p1.theta_true=params.theta_true(1); p1.phi_true=params.phi_true(1);
p1.R_true=params.R_true(1); p1.alpha=params.alpha(1);
p1.H_SI_matrix=H_SI;
rx1=simulate_radar_channel_3d(tx_sig,p1);
[~,~,~,v1,info1]=joint_estimator_fast(rx1,tx_sig,p1);
fprintf('SINGLE v=15.1: est=%.4f err=%.4f m/s (%.2f bins) det=%d\n',...
    v1(1),v1(1)-p1.v_true(1),(v1(1)-p1.v_true(1))/dv,info1.detected_targets);

% TEST B: single target v=-5.4
p2=params; p2.num_targets=1; p2.v_true=params.v_true(2);
p2.theta_true=params.theta_true(2); p2.phi_true=params.phi_true(2);
p2.R_true=params.R_true(2); p2.alpha=params.alpha(2);
p2.H_SI_matrix=H_SI;
rx2=simulate_radar_channel_3d(tx_sig,p2);
[~,~,~,v2,info2]=joint_estimator_fast(rx2,tx_sig,p2);
fprintf('SINGLE v=-5.4: est=%.4f err=%.4f m/s (%.2f bins) det=%d\n',...
    v2(1),v2(1)-p2.v_true(1),(v2(1)-p2.v_true(1))/dv,info2.detected_targets);

% TEST C: two targets
p3=params; p3.H_SI_matrix=H_SI;
rx3=simulate_radar_channel_3d(tx_sig,p3);
[th3,ph3,R3,v3,info3]=joint_estimator_fast(rx3,tx_sig,p3);
fprintf('TWO targets: det=%d\n',info3.detected_targets);
for i=1:info3.detected_targets
    d1=abs(v3(i)-params.v_true(1)); d2=abs(v3(i)-params.v_true(2));
    tv=params.v_true(1); if d1>d2, tv=params.v_true(2); end
    fprintf('  peak%d: v=%.4f true=%.1f err=%.4f m/s (%.2f bins)\n',...
        i,v3(i),tv,v3(i)-tv,(v3(i)-tv)/dv);
end
cmp=evaluate_estimation(th3,ph3,R3,v3,p3,false);
fprintf('  RMSE_v=%.4f m/s\n',cmp.rmse_v);

fprintf('\n=== CONCLUSION ===\n');
fprintf('Single-target errors: %.4f and %.4f m/s\n',v1(1)-p1.v_true(1),v2(1)-p2.v_true(1));
fprintf('Two-target RMSE: %.4f m/s\n',cmp.rmse_v);
fprintf('If single < 0.3 and two-target ~4 -> cross-target interference\n');
fprintf('If both ~4 -> fundamental interpolation limit on 256 pts\n');
