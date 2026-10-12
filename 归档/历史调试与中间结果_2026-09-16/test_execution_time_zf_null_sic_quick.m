% =========================================================================
% test_execution_time_zf_null_sic_quick.m
%   快速测试三曲线执行时间：
%     计时包含 generate_mimo_ofdm_waveform + simulate_radar_channel_3d +
%           joint_estimator_fast
%   三条方案：ZF / Null-space / Null-space + digital SIC
%   小规模：Ns=[512,1024,2048], L=[16,32,64], MC=3, Mrx=16
% =========================================================================
function test_execution_time_zf_null_sic_quick()
clear; close all; clc; warning('off','all');
t_all = tic;

methods       = {'zf', 'nullspace', 'nullspace'};
sic_flags     = [false, false, true];
method_labels = {'ZF', 'Null-space', 'Null-space + digital SIC'};
n_methods     = numel(methods);

Ns_list = [512, 1024, 2048];
L_list  = [16, 32, 64];
fixed_L_for_Ns = 64;
fixed_Ns_for_L = 2048;
Mx_val = 4; My_val = 4;   % Mrx=16
beta_SI = 0.1;
SNR_fixed = 0;
n_mc = 3;

fprintf('=== Execution time quick test (end-to-end) ===\n');
fprintf('Ns=%s, L=%s, MC=%d, Mrx=%d, beta_SI=%g\n\n', ...
    mat2str(Ns_list), mat2str(L_list), n_mc, Mx_val*My_val, beta_SI);

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
baseParams.SNR        = SNR_fixed;
baseParams.K_stream   = 2;
baseParams.user_theta_rad = deg2rad(baseParams.theta_true(:));
baseParams.user_phi_rad   = deg2rad(baseParams.phi_true(:));
baseParams.Mx = Mx_val;
baseParams.My = My_val;
baseParams.joint_fft_3d.Na_x = Mx_val;
baseParams.joint_fft_3d.Na_y = My_val;
baseParams.fast_estimator.R_max_gate = 600;

Nt_total = baseParams.Ntx * baseParams.Nty;
Nr_total = Mx_val * My_val;

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
ns_seeds = randi(2^31-1, n_methods, numel(Ns_list), n_mc);
l_seeds  = randi(2^31-1, n_methods, numel(L_list), n_mc);

time_ns = NaN(n_methods, numel(Ns_list), n_mc);
time_L  = NaN(n_methods, numel(L_list), n_mc);

% ---------- Ns sweep ----------
fprintf('==== Ns sweep (L=%d) ====\n', fixed_L_for_Ns);
for mi = 1:n_methods
    for ni = 1:numel(Ns_list)
        Ns_val = Ns_list(ni);
        p = baseParams;
        p.precoder_type = methods{mi};
        p.H_SI = H_SI;
        p.H_SI_matrix = H_SI;
        p.enable_SIC = sic_flags(mi);
        p.N = Ns_val;
        p.B = Ns_val * 120e3;
        p.K = fixed_L_for_Ns;
        p.meta.range_resolution = p.c / (2 * p.B);
        p.joint_fft_3d.Nr = Ns_val;
        p.joint_fft_3d.Nv = fixed_L_for_Ns;
        p.fast_estimator.n_samp_l = min(64, max(8, floor(fixed_L_for_Ns/2)));

        for mc = 1:n_mc
            rng(ns_seeds(mi, ni, mc));
            timer_id = tic;
            tx = generate_mimo_ofdm_waveform(p);
            X_tx = tx.X;
            clear tx;
            rx_cube = simulate_radar_channel_3d(X_tx, p);
            joint_estimator_fast(rx_cube, X_tx, p);
            time_ns(mi, ni, mc) = toc(timer_id);
            clear X_tx rx_cube;
        end
        fprintf('  %-28s Ns=%4d -> mean %.4f s\n', ...
            method_labels{mi}, Ns_val, mean(time_ns(mi,ni,:),'omitnan'));
    end
end

% ---------- L sweep ----------
fprintf('\n==== L sweep (Ns=%d) ====\n', fixed_Ns_for_L);
for mi = 1:n_methods
    for li = 1:numel(L_list)
        L_val = L_list(li);
        p = baseParams;
        p.precoder_type = methods{mi};
        p.H_SI = H_SI;
        p.H_SI_matrix = H_SI;
        p.enable_SIC = sic_flags(mi);
        p.N = fixed_Ns_for_L;
        p.B = fixed_Ns_for_L * 120e3;
        p.K = L_val;
        p.meta.range_resolution = p.c / (2 * p.B);
        p.joint_fft_3d.Nr = fixed_Ns_for_L;
        p.joint_fft_3d.Nv = L_val;
        p.fast_estimator.n_samp_l = min(64, max(8, floor(L_val/2)));

        for mc = 1:n_mc
            rng(l_seeds(mi, li, mc));
            timer_id = tic;
            tx = generate_mimo_ofdm_waveform(p);
            X_tx = tx.X;
            clear tx;
            rx_cube = simulate_radar_channel_3d(X_tx, p);
            joint_estimator_fast(rx_cube, X_tx, p);
            time_L(mi, li, mc) = toc(timer_id);
            clear X_tx rx_cube;
        end
        fprintf('  %-28s L=%3d -> mean %.4f s\n', ...
            method_labels{mi}, L_val, mean(time_L(mi,li,:),'omitnan'));
    end
end

time_ns_mean = squeeze(mean(time_ns, 3, 'omitnan'));
time_L_mean  = squeeze(mean(time_L, 3, 'omitnan'));

fprintf('\n=== Summary (mean over MC, end-to-end) ===\n');
fprintf('Ns sweep:\n');
for ni = 1:numel(Ns_list)
    fprintf('  Ns=%4d  ZF=%.4f  NS=%.4f  NS+SIC=%.4f\n', ...
        Ns_list(ni), time_ns_mean(1,ni), time_ns_mean(2,ni), time_ns_mean(3,ni));
end
fprintf('L sweep:\n');
for li = 1:numel(L_list)
    fprintf('  L=%3d  ZF=%.4f  NS=%.4f  NS+SIC=%.4f\n', ...
        L_list(li), time_L_mean(1,li), time_L_mean(2,li), time_L_mean(3,li));
end
fprintf('\n总耗时 %.1f s\n', toc(t_all));
save('test_execution_time_zf_null_sic_quick.mat', ...
    'Ns_list','L_list','method_labels','time_ns_mean','time_L_mean');
end
