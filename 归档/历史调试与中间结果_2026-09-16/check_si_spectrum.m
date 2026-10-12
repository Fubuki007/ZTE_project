% check_si_spectrum.m - inspect SI peaks in the RD spectrum
% Answers: why does Null-space fail at beta=10 while bf.m nulls SI to ~0?
% Replicates estimator stage-1 (spatial sum + equalization + 2D-FFT) for
%   (a) target echo only   (b) SI only (manual injection, beta=10/0.1)
%   (c) full rx
% and prints the top-8 RD peaks with power for each component.
clear; clc; warning('off','all');
fprintf('=== RD spectrum: target peaks vs SI peaks ===\n');

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
Nr_fixed = 16; Ns = baseParams.N; L = baseParams.K;
delta_f = baseParams.B / Ns;

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

method_list = {'zf','nullspace'};
beta_list2  = [0.1, 10];

for mi = 1:2
    method = method_list{mi};
    p_tx = baseParams;
    p_tx.precoder_type = method;
    p_tx.H_SI = H_SI_common;
    p_tx.H_SI_matrix = H_SI_rx;
    tx = generate_mimo_ofdm_waveform(p_tx);
    X_tx = tx.X;

    % target echo only
    p1 = p_tx; p1.enable_SI = false;
    rx_echo = simulate_radar_channel_3d(X_tx, p1);

    % equalization reference (estimator stage-1)
    tx_ref = squeeze(sum(sum(X_tx,1),2));
    tx_ref_norm = tx_ref ./ max(abs(tx_ref), eps);
    win_r = hann(Ns,'periodic'); win_v = hann(L,'periodic');

    % ---- RD spectrum of echo only ----
    rx_sum = squeeze(sum(rx_echo,[1 2]));
    rx_eq = rx_sum .* conj(tx_ref_norm);
    rx_eq = rx_eq .* (win_r * win_v.');
    RD_e = fftshift(fft(fft(rx_eq,Ns,1),L,2),2);
    P_e  = abs(RD_e).^2;

    fprintf('\n================ %s ================\n', method);
    [peaks_e, idx_e] = maxk(P_e(:), 6);
    fprintf('--- target echo only: top peaks ---\n');
    for k = 1:6
        [ir,iv] = ind2sub([Ns L], idx_e(k));
        nr = ir-1; nv = iv-1-floor(L/2);
        Rk = baseParams.c*(Ns-nr)/(2*Ns*delta_f);
        vk = nv*baseParams.c/(2*baseParams.Ts*baseParams.fc*L);
        fprintf('  P=%9.4g  nr=%6d R=%8.2f m  nv=%5d v=%7.2f m/s\n', ...
            peaks_e(k), nr, Rk, nv, vk);
    end

    for bi = 1:2
        beta_val = beta_list2(bi);
        % ---- SI only (manual injection) ----
        rx_si = zeros(4,4,Ns,L);
        for l = 1:L
            x_l = reshape(X_tx(:,:,:,l), Nt_total, Ns);
            rx_si(:,:,:,l) = reshape(beta_val*H_SI_rx*x_l, 4,4,Ns);
        end
        rx_sum_si = squeeze(sum(rx_si,[1 2]));
        rx_eq_si = rx_sum_si .* conj(tx_ref_norm);
        rx_eq_si = rx_eq_si .* (win_r * win_v.');
        RD_s = fftshift(fft(fft(rx_eq_si,Ns,1),L,2),2);
        P_s  = abs(RD_s).^2;

        % ---- full rx (echo + SI + noise) ----
        p2 = p_tx; p2.beta_SI = beta_val;
        rx_full = simulate_radar_channel_3d(X_tx, p2);
        rx_sum_f = squeeze(sum(rx_full,[1 2]));
        rx_eq_f = rx_sum_f .* conj(tx_ref_norm);
        rx_eq_f = rx_eq_f .* (win_r * win_v.');
        RD_f = fftshift(fft(fft(rx_eq_f,Ns,1),L,2),2);
        P_f  = abs(RD_f).^2;

        fprintf('\n--- beta=%.1f ---\n', beta_val);
        [peaks_s, idx_s] = maxk(P_s(:), 3);
        for k = 1:3
            [ir,iv] = ind2sub([Ns L], idx_s(k));
            nr = ir-1; nv = iv-1-floor(L/2);
            Rk = baseParams.c*(Ns-nr)/(2*Ns*delta_f);
            vk = nv*baseParams.c/(2*baseParams.Ts*baseParams.fc*L);
            fprintf('  SI-only  peak: P=%9.4g  R=%8.2f m  v=%7.2f m/s\n', peaks_s(k), Rk, vk);
        end
        fprintf('  echo top peak power        : %.4g\n', peaks_e(1));
        fprintf('  SI-only top peak power     : %.4g  (%+.1f dB vs echo)\n', ...
            peaks_s(1), 10*log10(peaks_s(1)/peaks_e(1)));
        fprintf('  noise floor (full - echo - si est): median bin = %.4g\n', ...
            median(P_f(:)));
        [peaks_f, idx_f] = maxk(P_f(:), 4);
        fprintf('  full-rx top peaks:\n');
        for k = 1:4
            [ir,iv] = ind2sub([Ns L], idx_f(k));
            nr = ir-1; nv = iv-1-floor(L/2);
            Rk = baseParams.c*(Ns-nr)/(2*Ns*delta_f);
            vk = nv*baseParams.c/(2*baseParams.Ts*baseParams.fc*L);
            fprintf('    P=%9.4g  R=%8.2f m  v=%7.2f m/s\n', peaks_f(k), Rk, vk);
        end
    end
end

fprintf('\n=== spectrum diagnosis done ===\n');
