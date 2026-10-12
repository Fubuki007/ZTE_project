% check_ns_beta100.m - nullspace at beta=100 (and 1000) with R_max_gate=600
% Quick single-target check: 8 MC, print every estimate + RMSE.
clear; clc; warning('off','all');
fprintf('=== Null-space: beta=100 / 1000, R_max_gate=600, MC=8 ===\n');

baseParams = build_default_params();
baseParams.theta_true = [24.63, 15.94];
baseParams.phi_true   = [30.99, 13.58];
baseParams.R_true     = [200.6, 210.4];
baseParams.v_true     = [15.1, -5.4];
baseParams.alpha      = [1.0, 0.8];
baseParams.enable_SI  = true;
baseParams.beta_SI    = 100;
baseParams.enable_SIC = false;
baseParams.K          = 256;
baseParams.K_stream   = 2;
baseParams.user_theta_rad = deg2rad(baseParams.theta_true(:));
baseParams.user_phi_rad   = deg2rad(baseParams.phi_true(:));
baseParams.Mx = 4; baseParams.My = 4;
baseParams.joint_fft_3d.Na_x = 4;
baseParams.joint_fft_3d.Na_y = 4;
baseParams.fast_estimator.n_samp_l = 64;
baseParams.fast_estimator.R_max_gate = 600;
baseParams.SNR = 0;

Nt_total = baseParams.Ntx * baseParams.Nty;

rng(20260730);
hsi_cfg_tx = struct('model','ura_rician','Nt_total',Nt_total,'Nr_total',64, ...
    'kappa_SI',10,'Ntx',baseParams.Ntx,'Nty',baseParams.Nty, ...
    'Mx',8,'My',8,'d_lambda',0.5, ...
    'theta_tx_deg',baseParams.theta_SI,'phi_tx_deg',baseParams.phi_SI, ...
    'theta_rx_deg',baseParams.theta_SI,'phi_rx_deg',baseParams.phi_SI);
H_SI_common = generate_HSI(hsi_cfg_tx);
hsi_cfg_rx = struct('model','ura_rician','Nt_total',Nt_total,'Nr_total',16, ...
    'kappa_SI',10,'Ntx',baseParams.Ntx,'Nty',baseParams.Nty, ...
    'Mx',4,'My',4,'d_lambda',0.5, ...
    'theta_tx_deg',baseParams.theta_SI,'phi_tx_deg',baseParams.phi_SI, ...
    'theta_rx_deg',baseParams.theta_SI,'phi_rx_deg',baseParams.phi_SI);
H_SI_rx = generate_HSI(hsi_cfg_rx);

p_tx = baseParams;
p_tx.precoder_type = 'nullspace';
p_tx.H_SI = H_SI_common;
p_tx.H_SI_matrix = H_SI_rx;
tx = generate_mimo_ofdm_waveform(p_tx);
X_tx = tx.X;

n_mc = 8;
rng(20260803);
rng_seeds = randi(2^31-1, 2, 6, n_mc);

for beta_val = [100, 1000]
    fprintf('\n--- beta=%g ---\n', beta_val);
    rr = NaN(1,n_mc); tt = NaN(1,n_mc); vv = NaN(1,n_mc);
    for mc_i = 1:n_mc
        rng(rng_seeds(2, bi_idx(beta_val), mc_i));
        p = p_tx; p.beta_SI = beta_val;
        rxCube = simulate_radar_channel_3d(X_tx, p);
        [th, ph, R_est, v_est, ~] = joint_estimator_fast(rxCube, X_tx, p);
        cmp = evaluate_estimation(th, ph, R_est, v_est, p, false);
        rr(mc_i) = cmp.rmse_R; tt(mc_i) = cmp.rmse_theta; vv(mc_i) = cmp.rmse_v;
        fprintf('MC%2d: R=[%s] v=[%s] th=[%s] -> rmse_R=%.4f\n', mc_i, ...
            num2str(R_est,'%.2f '), num2str(v_est,'%.2f '), num2str(th,'%.2f '), cmp.rmse_R);
    end
    fprintf('beta=%g: R med=%.4f m, th med=%.4f deg, v med=%.4f m/s\n', ...
        beta_val, median(rr,'omitnan'), median(tt,'omitnan'), median(vv,'omitnan'));
end

function bi = bi_idx(beta_val)
    b6 = [0.01, 0.1, 1, 10, 100, 1000];
    bi = find(b6 == beta_val, 1);
end
fprintf('\n=== done ===\n');
