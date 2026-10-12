% =========================================================================
% test_nullspace_matched_main_quick.m
%   按 main 的配置做小规模快速验证：
%     Mrx=64 (8x8), H_SI=64x16, 预编码设计与 SI 注入用同一个 H_SI
%   三条曲线：ZF / Null-space / Null-space + digital SIC
%   小规模：Ns=1024, L=128, MC=3, SNR=-20/0/20
% =========================================================================
function test_nullspace_matched_main_beta100_quick()
clear; close all; clc; warning('off','all');
t_all = tic;

methods       = {'zf', 'nullspace', 'nullspace'};
sic_flags     = [false, false, true];
method_labels = {'ZF', 'Null-space', 'Null-space + digital SIC'};
n_methods     = numel(methods);

snr_list = [-20, 0, 20];
n_mc = 3;
beta_SI = 100;
N_val = 1024;
L_val = 128;
Mx_val = 8; My_val = 8;      % 与 main 一致：Mrx=64

fprintf('=== Quick main-matched test: beta_SI=100 ===\n');
fprintf('Mrx=%d (%dx%d), Ns=%d, L=%d, MC=%d, beta_SI=%g\n\n', ...
    Mx_val*My_val, Mx_val, My_val, N_val, L_val, n_mc, beta_SI);

baseParams = build_default_params();
baseParams.theta_true = [24.63, 15.94];
baseParams.phi_true   = [30.99, 13.58];
baseParams.R_true     = [200.6, 210.4];
baseParams.v_true     = [15.1, -5.4];
baseParams.alpha      = [1.0, 0.8];
baseParams.enable_SI  = true;
baseParams.beta_SI    = beta_SI;
baseParams.enable_SIC = false;
baseParams.sic_use_true_channel = false;
baseParams.SIC_pilot_len = 128;
baseParams.K          = L_val;
baseParams.K_stream   = 2;
baseParams.user_theta_rad = deg2rad(baseParams.theta_true(:));
baseParams.user_phi_rad   = deg2rad(baseParams.phi_true(:));
baseParams.Mx = Mx_val;
baseParams.My = My_val;
baseParams.N = N_val;
baseParams.B = N_val * 120e3;
baseParams.joint_fft_3d.Na_x = Mx_val;
baseParams.joint_fft_3d.Na_y = My_val;
baseParams.joint_fft_3d.Nr = N_val;
baseParams.joint_fft_3d.Nv = L_val;
baseParams.fast_estimator.n_samp_l = min(64, max(8, floor(L_val/2)));
baseParams.fast_estimator.n_pad_v = L_val;
baseParams.fast_estimator.R_max_gate = 600;

Nt_total = baseParams.Ntx * baseParams.Nty;
Nr_total = Mx_val * My_val;

% 64x16 H_SI，预编码设计和 SI 注入/SIC 全部用同一个
rng(20260731);
hsi_cfg = struct( ...
    'model','ura_rician', 'Nt_total',Nt_total, 'Nr_total',Nr_total, ...
    'kappa_SI',10, 'Ntx',baseParams.Ntx, 'Nty',baseParams.Nty, ...
    'Mx',Mx_val, 'My',My_val, 'd_lambda',0.5, ...
    'theta_tx_deg',baseParams.theta_SI, 'phi_tx_deg',baseParams.phi_SI, ...
    'theta_rx_deg',baseParams.theta_SI, 'phi_rx_deg',baseParams.phi_SI, ...
    'seed', 20260731);
H_SI = generate_HSI(hsi_cfg);

rng(20260801);
rng_seeds = randi(2^31-1, n_methods, numel(snr_list), n_mc);

rmse_R = NaN(n_methods, numel(snr_list), n_mc);
rmse_theta = NaN(n_methods, numel(snr_list), n_mc);
rmse_v = NaN(n_methods, numel(snr_list), n_mc);

for mi = 1:n_methods
    p_tx = baseParams;
    p_tx.precoder_type = methods{mi};
    p_tx.H_SI = H_SI;
    p_tx.H_SI_matrix = H_SI;

    tx = generate_mimo_ofdm_waveform(p_tx);
    X_tx = tx.X;
    fprintf('\n[%s] si_leak=%.4g, comm_err=%.4g\n', ...
        method_labels{mi}, tx.precoder_info.si_leak_avg, tx.precoder_info.comm_err_avg);
    clear tx;

    for si = 1:numel(snr_list)
        p = p_tx;
        p.SNR = snr_list(si);
        p.enable_SI = true;
        p.enable_SIC = sic_flags(mi);
        p.H_SI_matrix = H_SI;
        p.beta_SI = beta_SI;

        for mc = 1:n_mc
            rng(rng_seeds(mi, si, mc));
            rx_cube = simulate_radar_channel_3d(X_tx, p);
            [th, ph, R, v, ~] = joint_estimator_fast(rx_cube, X_tx, p);
            cmp = evaluate_estimation(th, ph, R, v, p, false);
            if isfield(cmp, 'rmse_R') && ~isnan(cmp.rmse_R)
                rmse_R(mi, si, mc) = cmp.rmse_R;
                rmse_theta(mi, si, mc) = cmp.rmse_theta;
                rmse_v(mi, si, mc) = cmp.rmse_v;
            end
            clear rx_cube th ph R v cmp;
        end
        fprintf('  SNR=%+3d dB: R=%.4f m, th=%.4f deg, v=%.4f m/s\n', ...
            snr_list(si), median(rmse_R(mi,si,:),'omitnan'), ...
            median(rmse_theta(mi,si,:),'omitnan'), ...
            median(rmse_v(mi,si,:),'omitnan'));
    end
    clear X_tx;
end

rmse_R_med = median(rmse_R, 3, 'omitnan');
rmse_theta_med = median(rmse_theta, 3, 'omitnan');
rmse_v_med = median(rmse_v, 3, 'omitnan');

fprintf('\n=== Summary ===\n');
fprintf('%8s %14s %14s %16s\n', 'SNR', 'ZF', 'Null-space', 'Null-space+SIC');
for si = 1:numel(snr_list)
    fprintf('Angle  %+4d %14.4f %14.4f %16.4f\n', snr_list(si), ...
        rmse_theta_med(1,si), rmse_theta_med(2,si), rmse_theta_med(3,si));
end
for si = 1:numel(snr_list)
    fprintf('Range  %+4d %14.4f %14.4f %16.4f\n', snr_list(si), ...
        rmse_R_med(1,si), rmse_R_med(2,si), rmse_R_med(3,si));
end
for si = 1:numel(snr_list)
    fprintf('Vel    %+4d %14.4f %14.4f %16.4f\n', snr_list(si), ...
        rmse_v_med(1,si), rmse_v_med(2,si), rmse_v_med(3,si));
end

fprintf('\n总耗时 %.1f s\n', toc(t_all));
save('test_nullspace_matched_main_beta100_quick.mat', ...
    'snr_list','methods','method_labels','rmse_R_med','rmse_theta_med','rmse_v_med', ...
    'rmse_R','rmse_theta','rmse_v');
end

