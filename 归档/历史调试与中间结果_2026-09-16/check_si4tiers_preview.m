% check_si4tiers_preview.m — β_SI=[1,5,10,50] 四档快速预览 (MC=8, 门限 g600)
% 目的: 验证新档位行为 + 给服务器正式跑提供预期参考
clear; clc; warning('off','all');
fprintf('=== Preview: beta=[1,5,10,50], 门限 g600, MC=8 ===\n');

baseParams = build_default_params();
baseParams.theta_true = [24.63, 15.94];
baseParams.phi_true   = [30.99, 13.58];
baseParams.R_true     = [200.6, 210.4];
baseParams.v_true     = [15.1, -5.4];
baseParams.alpha      = [1.0, 0.8];
baseParams.enable_SI  = true;
baseParams.beta_SI    = 1;
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

beta_list = [1, 5, 10, 50];
method_list = {'zf', 'nullspace'};
method_labels = {'ZF', 'Null-space'};
n_mc = 8;
rng(20260803);
rng_seeds = randi(2^31-1, 2, numel(beta_list), n_mc);

Rmed = NaN(2,4); Tmed = NaN(2,4); Vmed = NaN(2,4); OkR = NaN(2,4);
for mi = 1:2
    method = method_list{mi};
    p_tx = baseParams;
    p_tx.precoder_type = method;
    p_tx.H_SI = H_SI_common;
    p_tx.H_SI_matrix = H_SI_rx;
    fprintf('\n===== %s =====\n', method_labels{mi});
    tx = generate_mimo_ofdm_waveform(p_tx);
    X_tx = tx.X;
    for bi = 1:4
        beta_val = beta_list(bi);
        rr = NaN(1,n_mc); tt = NaN(1,n_mc); vv = NaN(1,n_mc);
        ok = 0;
        for mc_i = 1:n_mc
            rng(rng_seeds(mi, bi, mc_i));
            p = p_tx; p.beta_SI = beta_val;
            rxCube = simulate_radar_channel_3d(X_tx, p);
            [th, ph, R_est, v_est, ~] = joint_estimator_fast(rxCube, X_tx, p);
            cmp = evaluate_estimation(th, ph, R_est, v_est, p, false);
            rr(mc_i) = cmp.rmse_R; tt(mc_i) = cmp.rmse_theta; vv(mc_i) = cmp.rmse_v;
            if all(abs(sort(th) - sort(baseParams.theta_true)) < 1), ok = ok + 1; end
        end
        Rmed(mi,bi) = median(rr,'omitnan'); Tmed(mi,bi) = median(tt,'omitnan');
        Vmed(mi,bi) = median(vv,'omitnan'); OkR(mi,bi) = ok/n_mc*100;
        fprintf('  beta=%-3g: R=%8.4f m  th=%7.3f deg  v=%6.3f m/s  角度成功率=%3.0f%%\n', ...
            beta_val, Rmed(mi,bi), Tmed(mi,bi), Vmed(mi,bi), OkR(mi,bi));
    end
end

fprintf('\n===== 汇总 (MC=8, 门限 g600, 预览) =====\n');
for mi = 1:2
    fprintf('%s:\n', method_labels{mi});
    fprintf('  beta:      [%s]\n', num2str(beta_list, '%6g'));
    fprintf('  R(m):      [%s]\n', num2str(Rmed(mi,:), '%10.4f'));
    fprintf('  th(deg):   [%s]\n', num2str(Tmed(mi,:), '%10.3f'));
    fprintf('  v(m/s):    [%s]\n', num2str(Vmed(mi,:), '%10.3f'));
    fprintf('  成功率(%%): [%s]\n', num2str(OkR(mi,:), '%10.0f'));
end
save('check_si4tiers_preview.mat', 'beta_list', 'Rmed', 'Tmed', 'Vmed', 'OkR', 'method_labels');
fprintf('=== done ===\n');
