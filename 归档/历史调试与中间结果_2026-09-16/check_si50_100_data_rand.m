% check_si50_100_data_rand.m — β=50/100 严谨 MC: 通信符号逐 MC 随机
% 修复: 原版本波形(符号DATA)只生成一次, 整批 MC 共享同一 SI 符号序列,
%       导致角度偏置整批继承 (MC=30 批 NS 偏 25.7°, MC=50 批偏 0.7°)
% 本版: 预编码 W 固定 (确定性), 每 MC 重新随机 DATA → S → X
clear; clc; warning('off','all');
fprintf('=== beta=50/100, 门限 g600, MC=30, DATA逐MC随机 ===\n');

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
M_qam = 16;

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
n_mc = 30;
rng(20260803);
rng_seeds = randi(2^31-1, 2, numel(beta_list), n_mc);

all_tt = NaN(2, 2, n_mc); all_rr = NaN(2, 2, n_mc); all_vv = NaN(2, 2, n_mc);
for mi = 1:2
    method = method_list{mi};
    p_tx = baseParams;
    p_tx.precoder_type = method;
    p_tx.H_SI = H_SI_common;
    p_tx.H_SI_matrix = H_SI_rx;
    fprintf('\n===== %s =====\n', method_labels{mi});
    % 预编码 W 只算一次 (确定性), 符号逐 MC 随机
    tx = generate_mimo_ofdm_waveform(p_tx);
    W = tx.W;   % (Nt_total, K_stream, Ns)
    Ntx = tx.Ntx; Nty = tx.Nty; Ns = size(W,3); L = baseParams.K;
    fprintf('  W 固定: (%dx%dx%d), 每 MC 重随机 DATA\n', size(W,1), size(W,2), Ns);
    for bi = 1:2
        beta_val = beta_list(bi);
        rr = NaN(1,n_mc); tt = NaN(1,n_mc); vv = NaN(1,n_mc);
        ok1 = 0; ok2 = 0;
        for mc_i = 1:n_mc
            rng(rng_seeds(mi, bi, mc_i));
            % --- 逐 MC 重新生成通信符号 → 发射波形 ---
            DATA = randi([0, M_qam-1], baseParams.K_stream, L, Ns);
            S = qammod(DATA, M_qam, 'UnitAveragePower', true);
            X_flat = pagemtimes(W, S);                       % (Nt,L,Ns)
            X_tx = permute(reshape(X_flat, Ntx, Nty, L, Ns), [1 2 4 3]);
            % --- 仿真 + 估计 ---
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
        fprintf('     成功率(<1deg)=%2d/30 (%3.0f%%)  (<2deg)=%2d/30 (%3.0f%%)\n', ...
            ok1, ok1/n_mc*100, ok2, ok2/n_mc*100);
        fprintf('     逐MC: [%s]\n', num2str(tt, '%.2f '));
    end
end

fprintf('\n===== 汇总 (MC=30, DATA逐MC随机) =====\n');
for bi = 1:2
    fprintf('β=%g:  ZF th med=%.3f (P90=%.2f) | NS th med=%.3f (P90=%.2f)\n', ...
        beta_list(bi), median(squeeze(all_tt(1,bi,:))), prctile(all_tt(1,bi,:),90), ...
        median(squeeze(all_tt(2,bi,:))), prctile(all_tt(2,bi,:),90));
end
save('check_si50_100_data_rand.mat', 'all_tt', 'all_rr', 'all_vv', 'beta_list', 'method_labels');
fprintf('=== done ===\n');
