% check_confirm_gate600.m - confirm R_max_gate=600 fixes ALL 6 beta tiers
% Same params as task_si_strength_sweep (MC=8 quick confirm):
%   2 methods x 6 beta x 8 MC, R_max_gate=600
% Prints median RMSE per (method, beta) and flags failures (R>1 m).
clear; clc; warning('off','all');
fprintf('=== Confirm R_max_gate=600 across all 6 beta tiers (MC=8) ===\n');

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

beta_list6 = [0.01, 0.1, 1, 10, 100, 1000];
method_list = {'zf','nullspace'};
n_mc = 8;

rng(20260803);
rng_seeds = randi(2^31-1, 2, 6, n_mc);

Rmed = NaN(2,6); Tmed = NaN(2,6); Vmed = NaN(2,6);
for mi = 1:2
    method = method_list{mi};
    p_tx = baseParams;
    p_tx.precoder_type = method;
    p_tx.H_SI = H_SI_common;
    p_tx.H_SI_matrix = H_SI_rx;
    tx = generate_mimo_ofdm_waveform(p_tx);
    X_tx = tx.X;
    for bi = 1:6
        beta_val = beta_list6(bi);
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
        Rmed(mi,bi) = median(rr,'omitnan');
        Tmed(mi,bi) = median(tt,'omitnan');
        Vmed(mi,bi) = median(vv,'omitnan');
        flag = '';
        if Rmed(mi,bi) > 1, flag = '  <-- FAIL'; end
        fprintf('%-9s beta=%-5g : R=%9.4f m  th=%7.3f deg  v=%7.3f m/s%s\n', ...
            method, beta_val, Rmed(mi,bi), Tmed(mi,bi), Vmed(mi,bi), flag);
    end
end

fprintf('\nSummary: any R>1m means gate=600 does NOT fix that tier.\n');
save('check_confirm_gate600.mat', 'Rmed', 'Tmed', 'Vmed', 'beta_list6', 'method_list');
fprintf('=== confirm done ===\n');
