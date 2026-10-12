% check_si10_both.m — ZF vs Null-space 在 β_SI=10 (门限版 g600) 快速验证
% 与 task_si_strength_sweep 完全一致的参数: SNR=0 dB, MC=8, L=256,
% Mrx=16(4x4), R_max_gate=600, R_min_gate=20, enable_SIC=false
clear; clc; warning('off','all');
fprintf('=== ZF vs Null-space @ beta_SI=100, 门限 R_max_gate=600, MC=8 ===\n');

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
baseParams.fast_estimator.R_max_gate = 600;   % ★ 门限
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

method_list = {'zf', 'nullspace'};
method_labels = {'ZF', 'Null-space'};
n_mc = 8;
rng(20260803);
rng_seeds = randi(2^31-1, 2, n_mc);

Rmed = NaN(2,1); Tmed = NaN(2,1); Vmed = NaN(2,1);
for mi = 1:2
    method = method_list{mi};
    p_tx = baseParams;
    p_tx.precoder_type = method;
    p_tx.H_SI = H_SI_common;
    p_tx.H_SI_matrix = H_SI_rx;
    fprintf('\n===== %s (precoder=%s) =====\n', method_labels{mi}, method);
    tx = generate_mimo_ofdm_waveform(p_tx);
    X_tx = tx.X;
    rr = NaN(1,n_mc); tt = NaN(1,n_mc); vv = NaN(1,n_mc);
    for mc_i = 1:n_mc
        rng(rng_seeds(mi, mc_i));
        p = p_tx; p.beta_SI = 100;
        rxCube = simulate_radar_channel_3d(X_tx, p);
        [th, ph, R_est, v_est, ~] = joint_estimator_fast(rxCube, X_tx, p);
        cmp = evaluate_estimation(th, ph, R_est, v_est, p, false);
        rr(mc_i) = cmp.rmse_R; tt(mc_i) = cmp.rmse_theta; vv(mc_i) = cmp.rmse_v;
        fprintf('  MC%2d: R=[%s]m v=[%s]m/s th=[%s]deg -> rmse_R=%.4f rmse_th=%.3f rmse_v=%.3f\n', ...
            mc_i, num2str(R_est,'%.2f'), num2str(v_est,'%.2f'), ...
            num2str(th,'%.2f'), cmp.rmse_R, cmp.rmse_theta, cmp.rmse_v);
    end
    Rmed(mi) = median(rr,'omitnan'); Tmed(mi) = median(tt,'omitnan'); Vmed(mi) = median(vv,'omitnan');
    fprintf('  >> %s @ beta=10: R med=%.4f m, th med=%.3f deg, v med=%.3f m/s (NaN:%d/%d)\n', ...
        method_labels{mi}, Rmed(mi), Tmed(mi), Vmed(mi), sum(isnan(rr)), n_mc);
end

fprintf('\n===== 汇总对比 (β_SI=10, 门限 g600) =====\n');
fprintf('%-12s %12s %12s %12s\n', 'Method', 'R (m)', 'theta (deg)', 'v (m/s)');
for mi = 1:2
    fprintf('%-12s %12.4f %12.3f %12.3f\n', method_labels{mi}, Rmed(mi), Tmed(mi), Vmed(mi));
end
save('check_si10_both.mat', 'Rmed', 'Tmed', 'Vmed', 'method_labels');
fprintf('=== done ===\n');
