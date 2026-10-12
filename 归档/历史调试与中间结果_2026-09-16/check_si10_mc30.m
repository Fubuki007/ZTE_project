% check_si10_mc30.m — β_SI=10, MC=30, 门限 g600: ZF vs Null-space 角度对比
% 目的: 坐实 β=10 时 nullspace 在角度维的优势 (中位数 + 成功率 + P90)
clear; clc; warning('off','all');
fprintf('=== ZF vs NS @ beta_SI=10, 门限 g600, MC=30 ===\n');

baseParams = build_default_params();
baseParams.theta_true = [24.63, 15.94];
baseParams.phi_true   = [30.99, 13.58];
baseParams.R_true     = [200.6, 210.4];
baseParams.v_true     = [15.1, -5.4];
baseParams.alpha      = [1.0, 0.8];
baseParams.enable_SI  = true;
baseParams.beta_SI    = 10;
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

method_list = {'zf', 'nullspace'};
method_labels = {'ZF', 'Null-space'};
n_mc = 30;
rng(20260803);
rng_seeds = randi(2^31-1, 2, n_mc);

for mi = 1:2
    method = method_list{mi};
    p_tx = baseParams;
    p_tx.precoder_type = method;
    p_tx.H_SI = H_SI_common;
    p_tx.H_SI_matrix = H_SI_rx;
    fprintf('\n===== %s =====\n', method_labels{mi});
    tx = generate_mimo_ofdm_waveform(p_tx);
    X_tx = tx.X;
    rr = NaN(1,n_mc); tt = NaN(1,n_mc); vv = NaN(1,n_mc);
    thr_ok = 0;   % 角度成功率: 两个目标角度误差均 <1 deg
    per_mc_th = NaN(1,n_mc);
    for mc_i = 1:n_mc
        rng(rng_seeds(mi, mc_i));
        p = p_tx; p.beta_SI = 10;
        rxCube = simulate_radar_channel_3d(X_tx, p);
        [th, ph, R_est, v_est, ~] = joint_estimator_fast(rxCube, X_tx, p);
        cmp = evaluate_estimation(th, ph, R_est, v_est, p, false);
        rr(mc_i) = cmp.rmse_R; tt(mc_i) = cmp.rmse_theta; vv(mc_i) = cmp.rmse_v;
        per_mc_th(mc_i) = cmp.rmse_theta;
        if all(abs(th - sort(baseParams.theta_true)) < 1) || ...
           all(abs(sort(th) - sort(baseParams.theta_true)) < 1)
            thr_ok = thr_ok + 1;
        end
    end
    ok_ratio = thr_ok / n_mc * 100;
    fprintf('  R med=%.4f m | th med=%.3f deg | v med=%.3f m/s\n', ...
        median(rr,'omitnan'), median(tt,'omitnan'), median(vv,'omitnan'));
    fprintf('  角度成功率(<1deg)=%d/%d = %.0f%% | th P90=%.2f deg | th max=%.2f deg\n', ...
        thr_ok, n_mc, ok_ratio, prctile(tt,90), max(tt));
    fprintf('  逐MC th rmse: [%s]\n', num2str(per_mc_th, '%.2f '));
    Rmed(mi) = median(rr,'omitnan'); Vmed(mi) = median(vv,'omitnan');
    Tmed(mi) = median(tt,'omitnan');
    OkRatio(mi) = ok_ratio; TP90(mi) = prctile(tt,90);
end

fprintf('\n===== β_SI=10 汇总 (MC=30, 门限 g600) =====\n');
fprintf('%-12s %12s %12s %12s %10s %10s\n', 'Method','R(m)','th(deg)','v(m/s)','成功率','th P90');
for mi = 1:2
    fprintf('%-12s %12.4f %12.3f %12.3f %9.0f%% %10.2f\n', ...
        method_labels{mi}, Rmed(mi), Tmed(mi), Vmed(mi), OkRatio(mi), TP90(mi));
end
save('check_si10_mc30.mat', 'Rmed', 'Tmed', 'Vmed', 'OkRatio', 'TP90', 'method_labels');
fprintf('=== done ===\n');
