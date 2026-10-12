% check_si_power_diag.m - SI power calibration diagnosis
% Replicates task_si_strength_sweep params, answers:
%   why ZF vs Null-space RMSE look identical at beta_SI=0.1
%   1) target echo power vs injected SI power vs noise power
%   2) precoder SI leakage on design channel (H_SI_common) vs injection
%      channel (H_SI_rx)
%   3) how large beta must be for SI to matter vs noise
clear; clc; warning('off','all');
fprintf('=== SI power calibration diagnosis ===\n');

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
Nr_fixed = 4*4;
Ns = baseParams.N; L = baseParams.K;

% ---- H_SI: same two channels as task_si_strength_sweep ----
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

fprintf('||H_SI_common||_F^2 = %.1f  (theory Nt*64 = %d)\n', ...
    norm(H_SI_common,'fro')^2, Nt_total*64);
fprintf('||H_SI_rx||_F^2     = %.1f  (theory Nt*16 = %d)\n', ...
    norm(H_SI_rx,'fro')^2, Nt_total*Nr_fixed);

method_list = {'zf','nullspace'};
for mi = 1:2
    method = method_list{mi};
    p_tx = baseParams;
    p_tx.precoder_type = method;
    p_tx.H_SI = H_SI_common;
    p_tx.H_SI_matrix = H_SI_rx;
    tx = generate_mimo_ofdm_waveform(p_tx);
    X_tx = tx.X; W = tx.W;      % W: (Nt,K,Ns)

    % ---- target echo power (no SI) ----
    p1 = p_tx; p1.enable_SI = false;
    rx_echo = simulate_radar_channel_3d(X_tx, p1);
    target_pow = mean(abs(rx_echo(:)).^2);
    noise_pow  = target_pow / 10^(0/10);

    % ---- injected SI power: y_si = beta * H_SI_rx * x ----
    si_base = 0;                    % mean power at beta=1
    for l = 1:L
        x_l = reshape(X_tx(:,:,:,l), Nt_total, Ns);
        y_si = H_SI_rx * x_l;
        si_base = si_base + sum(abs(y_si(:)).^2);
    end
    si_base = si_base / (Nr_fixed*Ns*L);

    % ---- precoder SI leakage (design channel vs injection channel) ----
    leak_common = 0; leak_rx = 0;
    for i = 1:Ns
        leak_common = leak_common + norm(H_SI_common*W(:,:,i),'fro')^2;
        leak_rx     = leak_rx     + norm(H_SI_rx    *W(:,:,i),'fro')^2;
    end
    leak_common = leak_common / Ns;
    leak_rx     = leak_rx     / Ns;

    fprintf('\n================ method: %s ================\n', method);
    fprintf('target echo mean power : %.4g\n', target_pow);
    fprintf('noise power (SNR=0 dB) : %.4g\n', noise_pow);
    fprintf('SI mean power at beta=1: %.4g\n', si_base);
    fprintf('  beta=0.01 -> %.4g   (SI/noise = %+.1f dB)\n', ...
        1e-4*si_base, 10*log10(1e-4*si_base/noise_pow));
    fprintf('  beta=0.1  -> %.4g   (SI/noise = %+.1f dB)\n', ...
        1e-2*si_base, 10*log10(1e-2*si_base/noise_pow));
    fprintf('  beta=1    -> %.4g   (SI/noise = %+.1f dB)\n', ...
        si_base, 10*log10(si_base/noise_pow));
    fprintf('  beta=10   -> %.4g   (SI/noise = %+.1f dB)\n', ...
        100*si_base, 10*log10(100*si_base/noise_pow));
    fprintf('critical beta for SI==noise: %.3g\n', sqrt(noise_pow/si_base));
    fprintf('leak ||H_SI*W||^2: design(common) = %.4g | injection(rx) = %.4g\n', ...
        leak_common, leak_rx);
end

fprintf('\n=== diagnosis done ===\n');
