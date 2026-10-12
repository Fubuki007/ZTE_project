% =========================================================================
% test_output_snr_ns_l_nullspace_sic_quick.m
%   快速测试：Output SNR vs Ns / L
%   三条曲线：ZF / Null-space / Null-space + digital SIC
%   参数缩小：Ns=[512,1024,2048], L=[16,32,64,128], MC=3, Mrx=64
% =========================================================================
function test_output_snr_ns_l_nullspace_sic_quick()
clear; close all; clc; warning('off','all');
t_all = tic;

methods       = {'zf', 'nullspace', 'nullspace'};
sic_flags     = [false, false, true];
method_labels = {'ZF', 'Null-space', 'Null-space + digital SIC'};
n_methods     = numel(methods);

n_mc = 3;
beta_SI = 10;
input_snr = 0;
Mx_val = 8; My_val = 8;   % Mrx=64

Ns_list = [512, 1024, 2048];
L_list  = [16, 32, 64, 128];
fixed_L_for_Ns = 128;
fixed_Ns_for_L = 2048;

fprintf('=== Quick test: Output SNR vs Ns / L ===\n');
fprintf('Mrx=%dx%d, beta_SI=%g, MC=%d\n\n', Mx_val, My_val, beta_SI, n_mc);

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
baseParams.SNR        = input_snr;
baseParams.K_stream   = 2;
baseParams.user_theta_rad = deg2rad(baseParams.theta_true(:));
baseParams.user_phi_rad   = deg2rad(baseParams.phi_true(:));
baseParams.Mx = Mx_val;
baseParams.My = My_val;
baseParams.joint_fft_3d.Na_x = Mx_val;
baseParams.joint_fft_3d.Na_y = My_val;
baseParams.fast_estimator.n_pad_v = 128;
baseParams.fast_estimator.R_max_gate = 600;

Nt_total = baseParams.Ntx * baseParams.Nty;
Nr_total = Mx_val * My_val;

% H_SI: 预编码用 64xNt，接收/SIC 用 64xNt（这里 Mrx=64，两个一致）
rng(20260730);
hsi_cfg_tx = struct( ...
    'model','ura_rician', 'Nt_total',Nt_total, 'Nr_total',64, ...
    'kappa_SI',10, 'Ntx',baseParams.Ntx, 'Nty',baseParams.Nty, ...
    'Mx',8, 'My',8, 'd_lambda',0.5, ...
    'theta_tx_deg',baseParams.theta_SI, 'phi_tx_deg',baseParams.phi_SI, ...
    'theta_rx_deg',baseParams.theta_SI, 'phi_rx_deg',baseParams.phi_SI, ...
    'seed', 20260730);
H_SI_common = generate_HSI(hsi_cfg_tx);

rng(20260731);
hsi_cfg_rx = struct( ...
    'model','ura_rician', 'Nt_total',Nt_total, 'Nr_total',Nr_total, ...
    'kappa_SI',10, 'Ntx',baseParams.Ntx, 'Nty',baseParams.Nty, ...
    'Mx',Mx_val, 'My',My_val, 'd_lambda',0.5, ...
    'theta_tx_deg',baseParams.theta_SI, 'phi_tx_deg',baseParams.phi_SI, ...
    'theta_rx_deg',baseParams.theta_SI, 'phi_rx_deg',baseParams.phi_SI, ...
    'seed', 20260731);
H_SI_rx = generate_HSI(hsi_cfg_rx);

% seeds
rng(20260801);
ns_seeds = randi(2^31-1, n_methods, numel(Ns_list), n_mc);
l_seeds  = randi(2^31-1, n_methods, numel(L_list), n_mc);

snr_ns = NaN(n_methods, numel(Ns_list), n_mc);
snr_L  = NaN(n_methods, numel(L_list), n_mc);

% ---------- Ns sweep ----------
fprintf('==== (b) Ns sweep (L=%d) ====\n', fixed_L_for_Ns);
for mi = 1:n_methods
    for ni = 1:numel(Ns_list)
        Ns_val = Ns_list(ni);
        p = baseParams;
        p.precoder_type = methods{mi};
        p.H_SI = H_SI_common;
        p.H_SI_matrix = H_SI_rx;
        p.N = Ns_val;
        p.B = Ns_val * 120e3;
        p.K = fixed_L_for_Ns;
        p.meta.range_resolution = p.c / (2 * p.B);
        p.joint_fft_3d.Nr = Ns_val;
        p.joint_fft_3d.Nv = fixed_L_for_Ns;
        p.fast_estimator.n_samp_l = min(64, max(8, floor(fixed_L_for_Ns/2)));

        tx = generate_mimo_ofdm_waveform(p);
        X_tx = tx.X;
        clear tx;

        for mc = 1:n_mc
            rng(ns_seeds(mi, ni, mc));
            rx_cube = simulate_radar_channel_3d(X_tx, p);
            snr_ns(mi, ni, mc) = local_output_snr_db(rx_cube, X_tx, p);
            clear rx_cube;
        end
        clear X_tx;
        fprintf('  %-28s Ns=%4d -> %.2f dB\n', ...
            method_labels{mi}, Ns_val, mean(snr_ns(mi,ni,:),'omitnan'));
    end
end

% ---------- L sweep ----------
fprintf('\n==== (c) L sweep (Ns=%d) ====\n', fixed_Ns_for_L);
for mi = 1:n_methods
    for li = 1:numel(L_list)
        L_val = L_list(li);
        p = baseParams;
        p.precoder_type = methods{mi};
        p.H_SI = H_SI_common;
        p.H_SI_matrix = H_SI_rx;
        p.N = fixed_Ns_for_L;
        p.B = fixed_Ns_for_L * 120e3;
        p.K = L_val;
        p.meta.range_resolution = p.c / (2 * p.B);
        p.joint_fft_3d.Nr = fixed_Ns_for_L;
        p.joint_fft_3d.Nv = L_val;
        p.fast_estimator.n_samp_l = min(64, max(8, floor(L_val/2)));

        tx = generate_mimo_ofdm_waveform(p);
        X_tx = tx.X;
        clear tx;

        for mc = 1:n_mc
            rng(l_seeds(mi, li, mc));
            rx_cube = simulate_radar_channel_3d(X_tx, p);
            snr_L(mi, li, mc) = local_output_snr_db(rx_cube, X_tx, p);
            clear rx_cube;
        end
        clear X_tx;
        fprintf('  %-28s L=%3d -> %.2f dB\n', ...
            method_labels{mi}, L_val, mean(snr_L(mi,li,:),'omitnan'));
    end
end

snr_ns_avg = squeeze(mean(snr_ns,3,'omitnan'));
snr_L_avg  = squeeze(mean(snr_L,3,'omitnan'));

fprintf('\n=== Summary Ns ===\n');
fprintf('%8s %12s %14s %18s\n','Ns','ZF','Null-space','Null-space+SIC');
for i=1:numel(Ns_list)
    fprintf('%8d %12.2f %14.2f %18.2f\n', ...
        Ns_list(i), snr_ns_avg(1,i), snr_ns_avg(2,i), snr_ns_avg(3,i));
end
fprintf('\n=== Summary L ===\n');
fprintf('%8s %12s %14s %18s\n','L','ZF','Null-space','Null-space+SIC');
for i=1:numel(L_list)
    fprintf('%8d %12.2f %14.2f %18.2f\n', ...
        L_list(i), snr_L_avg(1,i), snr_L_avg(2,i), snr_L_avg(3,i));
end
fprintf('\n总耗时 %.1f s\n', toc(t_all));

save('test_output_snr_ns_l_nullspace_sic_quick.mat', ...
    'Ns_list','L_list','methods','method_labels','snr_ns','snr_L', ...
    'snr_ns_avg','snr_L_avg');
end

% =========================================================================
function snrDb = local_output_snr_db(rxCube, txSignal, params)
[Mx, My, Ns, L] = size(rxCube);
selectedAnt = ceil((Mx * My) / 2);
[selectedX, selectedY] = ind2sub([Mx, My], selectedAnt);
rxSelected = reshape(rxCube(selectedX, selectedY, :, :), Ns, L);
rxEq = local_equalize_rx(rxSelected, txSignal);
rd = fft(rxEq, Ns, 1);
rd = fftshift(fft(rd, L, 2), 2);
powerMap = abs(rd).^2;

badMask = false(size(powerMap));
if isfield(params, 'fast_estimator') && isfield(params.fast_estimator, 'R_min_gate')
    R_min_gate = params.fast_estimator.R_min_gate;
    if mod(Ns,2)==0, centerIdx=Ns/2+1; else centerIdx=(Ns+1)/2; end
    if isfield(params,'meta') && isfield(params.meta,'delta_f')
        delta_f = params.meta.delta_f;
    else
        delta_f = params.B / Ns;
    end
    binPerMeter = 2*delta_f*Ns/params.c;
    guardHalf = ceil(R_min_gate*binPerMeter);
    rIdx = max(1,centerIdx-guardHalf):min(Ns,centerIdx+guardHalf);
    badMask(rIdx,:) = true;
    powerMap(badMask) = 0;
end

nPeaks = max(1, min(params.num_targets, numel(powerMap)));
[peakValues, peakIndex] = maxk(powerMap(:), nPeaks);
mask = false(size(powerMap));
guardR = 2; guardV = 2;
for k = 1:numel(peakIndex)
    [ir, iv] = ind2sub(size(powerMap), peakIndex(k));
    rIdx = max(1, ir-guardR):min(Ns, ir+guardR);
    vIdx = max(1, iv-guardV):min(L, iv+guardV);
    mask(rIdx, vIdx) = true;
end

background = powerMap(~mask & ~badMask);
noiseFloor = median(background(:), 'omitnan');
snrDb = 10*log10(mean(peakValues,'omitnan')/max(noiseFloor,eps));
end

function rxEq = local_equalize_rx(rxSelected, txSignal)
[Ns, L] = size(rxSelected);
if ismatrix(txSignal) && isequal(size(txSignal), [Ns, L])
    txNorm = txSignal ./ max(max(abs(txSignal(:))), eps);
else
    txSum = squeeze(sum(sum(txSignal, 1), 2));
    txNorm = txSum ./ max(max(abs(txSum(:))), eps);
end
rxEq = rxSelected .* conj(reshape(txNorm, Ns, L));
end
