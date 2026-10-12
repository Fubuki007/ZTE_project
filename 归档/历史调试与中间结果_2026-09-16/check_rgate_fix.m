% check_rgate_fix.m - verify R_max_gate=500 fixes beta=10 SI failure
% Small MC (8) comparison: zf vs nullspace, beta in {0.1, 1, 10}
% with and without R_max_gate=500 (DC SI peak at R=1250m is filtered).
clear; clc; warning('off','all');
fprintf('=== R_max_gate fix verification (MC=8, SNR=0dB) ===\n');

baseParams = build_default_params();
baseParams.theta_true = [24.63, 15.94];
baseParams.phi_true   = [30.99, 13.58];
baseParams.R_true     = [200.6, 210.4];
baseParams.v_true     = [15.1, -5.4];
baseParams.alpha      = [1.0, 0.8];
baseParams.enable_SI  = true;
baseParams.beta_SI    = 0.1;
baseParams.enable_SIC = false;
baseParams.K          = 256;
baseParams.K_stream   = 2;
baseParams.user_theta_rad = deg2rad(baseParams.theta_true(:));
baseParams.user_phi_rad   = deg2rad(baseParams.phi_true(:));
baseParams.Mx = 4; baseParams.My = 4;
baseParams.joint_fft_3d.Na_x = 4;
baseParams.joint_fft_3d.Na_y = 4;
baseParams.fast_estimator.n_samp_l = 64;
baseParams.SNR = 0;

Nt_total = baseParams.Ntx * baseParams.Nty;
Nr_fixed = 16;

rng(20260730);
hsi_cfg_tx = struct('model','ura_rician','Nt_total',Nt_total,'Nr_total',64, ...
    'kappa_SI',10,'Ntx',baseParams.Ntx,'Nty',baseParams.Nty, ...
    'Mx',8,'My',8,'d_lambda',0.5, ...
    'theta_tx_deg',baseParams.theta_SI,'phi_tx_deg',baseParams.phi_SI, ...
    'theta_rx_deg',baseParams.theta_SI,'phi_rx_deg',baseParams.phi_SI);
H_SI_common = generate_HSI(hsi_cfg_tx);
hsi_cfg_rx = struct('model','ura_rician','Nt_total',Nt_total,'Nr_total',Nr_fixed, ...
    'kappa_SI',10,'Ntx',baseParams.Ntx,'Nty',baseParams.Nty, ...
    'Mx',4,'My',4,'d_lambda',0.5, ...
    'theta_tx_deg',baseParams.theta_SI,'phi_tx_deg',baseParams.phi_SI, ...
    'theta_rx_deg',baseParams.theta_SI,'phi_rx_deg',baseParams.phi_SI);
H_SI_rx = generate_HSI(hsi_cfg_rx);

n_mc = 8;
rng(20260803);
rng_seeds = randi(2^31-1, 2, 3, n_mc);

method_list = {'zf','nullspace'};
beta_list3  = [0.1, 1, 10];

for gate = [0, 500]
    fprintf('\n######## R_max_gate = %d ########\n', gate);
    for mi = 1:2
        method = method_list{mi};
        p_tx = baseParams;
        p_tx.precoder_type = method;
        p_tx.H_SI = H_SI_common;
        p_tx.H_SI_matrix = H_SI_rx;
        if gate > 0
            p_tx.fast_estimator.R_max_gate = gate;
        end
        tx = generate_mimo_ofdm_waveform(p_tx);
        X_tx = tx.X;

        for bi = 1:3
            beta_val = beta_list3(bi);
            rr = NaN(1,n_mc); tt = NaN(1,n_mc); vv = NaN(1,n_mc);
            for mc_i = 1:n_mc
                rng(rng_seeds(mi,bi,mc_i));
                p = p_tx; p.beta_SI = beta_val;
                try
                    rxCube = simulate_radar_channel_3d(X_tx, p);
                    [th, ph, R_est, v_est, ~] = joint_estimator_fast(rxCube, X_tx, p);
                    cmp = evaluate_estimation(th, ph, R_est, v_est, p, false);
                    rr(mc_i) = cmp.rmse_R; tt(mc_i) = cmp.rmse_theta; vv(mc_i) = cmp.rmse_v;
                catch
                end
            end
            fprintf('%-9s beta=%-4g : R=%9.4f m  th=%7.3f deg  v=%7.3f m/s\n', ...
                method, beta_val, median(rr,'omitnan'), median(tt,'omitnan'), median(vv,'omitnan'));
        end
    end
end
fprintf('\n=== done ===\n');
