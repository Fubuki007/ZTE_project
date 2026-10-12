% check_si50_100_mc50.m — β_SI=50/100 角度维重跑 (MC=50, 门限 g600)
% 目的: 验证 MC=30 中"nullspace 角度比 ZF 差"是否真实
%       重点看角度误差的分布 (分位数/成功率), 而非只看中位数
clear; clc; warning('off','all');
fprintf('=== beta=50/100, 门限 g600, MC=50: ZF vs NS 角度分布 ===\n');

baseParams = build_default_params();
baseParams.theta_true = [24.63, 15.94];
baseParams.phi_true   = [30.99, 13.58];
baseParams.R_true     = [200.6, 210.4];
baseParams.v_true     = [15.1, -5.4];
baseParams.alpha      = [1.0, 0.8];
baseParams.enable_SI  = true;
baseParams.beta_SI    = 50;
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

beta_list = [50, 100];
method_list = {'zf', 'nullspace'};
method_labels = {'ZF', 'Null-space'};
n_mc = 50;
rng(20260803);
rng_seeds = randi(2^31-1, 2, numel(beta_list), n_mc);

all_tt = NaN(2, 2, n_mc);   % (method, beta, mc)
all_rr = NaN(2, 2, n_mc);
all_vv = NaN(2, 2, n_mc);
for mi = 1:2
    method = method_list{mi};
    p_tx = baseParams;
    p_tx.precoder_type = method;
    p_tx.H_SI = H_SI_common;
    p_tx.H_SI_matrix = H_SI_rx;
    fprintf('\n===== %s =====\n', method_labels{mi});
    tx = generate_mimo_ofdm_waveform(p_tx);
    X_tx = tx.X;
    for bi = 1:2
        beta_val = beta_list(bi);
        rr = NaN(1,n_mc); tt = NaN(1,n_mc); vv = NaN(1,n_mc);
        ok1 = 0; ok2 = 0;   % <1deg 和 <2deg 的成功率
        for mc_i = 1:n_mc
            rng(rng_seeds(mi, bi, mc_i));
            p = p_tx; p.beta_SI = beta_val;
            rxCube = simulate_radar_channel_3d(X_tx, p);
            [th, ph, R_est, v_est, ~] = joint_estimator_fast(rxCube, X_tx, p);
            cmp = evaluate_estimation(th, ph, R_est, v_est, p, false);
            rr(mc_i) = cmp.rmse_R; tt(mc_i) = cmp.rmse_theta; vv(mc_i) = cmp.rmse_v;
            if all(abs(sort(th) - sort(baseParams.theta_true)) < 1), ok1 = ok1 + 1; end
            if all(abs(sort(th) - sort(baseParams.theta_true)) < 2), ok2 = ok2 + 1; end
        end
        all_tt(mi,bi,:) = tt; all_rr(mi,bi,:) = rr; all_vv(mi,bi,:) = vv;
        q = prctile(tt, [25 50 75 90 95]);
        fprintf('  beta=%-3g: R med=%7.4f m | v med=%6.3f m/s\n', beta_val, median(rr), median(vv));
        fprintf('     th: med=%7.3f | P25=%6.3f P75=%6.3f P90=%6.3f P95=%6.3f max=%6.2f deg\n', ...
            median(tt), q(1), q(3), q(4), q(5), max(tt));
        fprintf('     成功率(<1deg)=%2d/50 (%3.0f%%)  (<2deg)=%2d/50 (%3.0f%%)\n', ...
            ok1, ok1/n_mc*100, ok2, ok2/n_mc*100);
        fprintf('     逐MC: [%s]\n', num2str(tt, '%.2f '));
    end
end

fprintf('\n===== 汇总 (MC=50) =====\n');
for bi = 1:2
    fprintf('β=%g:  ZF th med=%.3f (P90=%.2f) | NS th med=%.3f (P90=%.2f)\n', ...
        beta_list(bi), median(squeeze(all_tt(1,bi,:))), prctile(all_tt(1,bi,:),90), ...
        median(squeeze(all_tt(2,bi,:))), prctile(all_tt(2,bi,:),90));
end
save('check_si50_100_mc50.mat', 'all_tt', 'all_rr', 'all_vv', 'beta_list', 'method_labels');
fprintf('=== done ===\n');
