% =========================================================================
% test_output_snr_vs_mrx_lagrange_sic_quick.m
%   快速测试 Mrx vs Output SNR 的趋势
%   三条曲线：ZF / Lagrange / Lagrange + digital SIC
%   参数缩小：Ns=512, L=64, MC=5, beta_SI=10
%   仅用于本地判断趋势，不是最终画图脚本。
% =========================================================================
function test_output_snr_vs_mrx_lagrange_sic_quick()
clear; close all; clc; warning('off','all');
t_all = tic;

methods       = {'zf', 'lagrange', 'lagrange'};
sic_flags     = [false, false, true];
method_labels = {'ZF', 'Lagrange', 'Lagrange + digital SIC'};
n_methods     = numel(methods);

M_list    = [2, 4, 6, 8];
Mrx_list  = M_list.^2;
n_mrx     = numel(Mrx_list);

N_val = 512;
L_val = 64;
n_mc  = 5;
beta_SI = 10;
input_snr = 0;

fprintf('=== Quick test: Output SNR vs Mrx ===\n');
fprintf('Ns=%d, L=%d, MC=%d, beta_SI=%g\n\n', N_val, L_val, n_mc, beta_SI);

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
baseParams.N = N_val;
baseParams.B = N_val * 120e3;
baseParams.K = L_val;
baseParams.meta.range_resolution = baseParams.c / (2 * baseParams.B);
baseParams.fast_estimator.n_samp_l = min(32, max(8, floor(L_val/2)));
baseParams.fast_estimator.n_pad_v = L_val;

Nt_total = baseParams.Ntx * baseParams.Nty;

rng(20260730);
hsi_cfg_tx = struct( ...
    'model','ura_rician', 'Nt_total',Nt_total, 'Nr_total',64, ...
    'kappa_SI',10, 'Ntx',baseParams.Ntx, 'Nty',baseParams.Nty, ...
    'Mx',8, 'My',8, 'd_lambda',0.5, ...
    'theta_tx_deg',baseParams.theta_SI, 'phi_tx_deg',baseParams.phi_SI, ...
    'theta_rx_deg',baseParams.theta_SI, 'phi_rx_deg',baseParams.phi_SI, ...
    'seed', 20260730);
H_SI_common = generate_HSI(hsi_cfg_tx);

rng(20260801);
rng_seeds = randi(2^31-1, n_methods, n_mrx, n_mc);

snr_mrx = NaN(n_methods, n_mrx, n_mc);

for mi = 1:n_methods
    p_method = baseParams;
    p_method.precoder_type = methods{mi};
    p_method.H_SI = H_SI_common;

    tx = generate_mimo_ofdm_waveform(p_method);
    X_tx = tx.X;
    clear tx;

    for mi_mrx = 1:n_mrx
        M_val  = M_list(mi_mrx);
        Mrx_val = Mrx_list(mi_mrx);
        p = p_method;
        p.Mx = M_val; p.My = M_val;
        p.joint_fft_3d.Na_x = M_val;
        p.joint_fft_3d.Na_y = M_val;

        hsi_cfg_rx = struct( ...
            'model','ura_rician', 'Nt_total',Nt_total, 'Nr_total',Mrx_val, ...
            'kappa_SI',10, 'Ntx',baseParams.Ntx, 'Nty',baseParams.Nty, ...
            'Mx',M_val, 'My',M_val, 'd_lambda',0.5, ...
            'theta_tx_deg',baseParams.theta_SI, 'phi_tx_deg',baseParams.phi_SI, ...
            'theta_rx_deg',baseParams.theta_SI, 'phi_rx_deg',baseParams.phi_SI, ...
            'seed', 2026000 + mi_mrx);
        p.H_SI_matrix = generate_HSI(hsi_cfg_rx);

        for mc_i = 1:n_mc
            rng(rng_seeds(mi, mi_mrx, mc_i));
            rxCube = simulate_radar_channel_3d(X_tx, p);
            snr_mrx(mi, mi_mrx, mc_i) = local_output_snr_db(rxCube, X_tx, p);
            clear rxCube;
        end
        fprintf('  %-28s Mrx=%3d -> %.2f dB\n', ...
            method_labels{mi}, Mrx_val, mean(snr_mrx(mi, mi_mrx, :), 'omitnan'));
    end
    clear X_tx;
end

snr_avg = squeeze(mean(snr_mrx, 3, 'omitnan'));
fprintf('\n=== Summary ===\n');
fprintf('%8s  %12s  %12s  %16s\n', 'Mrx', 'ZF', 'Lagrange', 'Lagrange+SIC');
for i = 1:n_mrx
    fprintf('%8d  %12.2f  %12.2f  %16.2f\n', ...
        Mrx_list(i), snr_avg(1,i), snr_avg(2,i), snr_avg(3,i));
end
fprintf('\n总耗时 %.1f s\n', toc(t_all));

save('test_output_snr_vs_mrx_lagrange_sic_quick.mat', ...
    'Mrx_list', 'methods', 'method_labels', 'snr_mrx', 'snr_avg');
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
    if mod(Ns, 2) == 0
        centerIdx = Ns / 2 + 1;
    else
        centerIdx = (Ns + 1) / 2;
    end
    if isfield(params, 'meta') && isfield(params.meta, 'delta_f')
        delta_f = params.meta.delta_f;
    else
        delta_f = params.B / Ns;
    end
    binPerMeter = 2 * delta_f * Ns / params.c;
    guardHalf = ceil(R_min_gate * binPerMeter);
    rIdx = max(1, centerIdx - guardHalf):min(Ns, centerIdx + guardHalf);
    badMask(rIdx, :) = true;
    powerMap(badMask) = 0;
end

nPeaks = max(1, min(params.num_targets, numel(powerMap)));
[peakValues, peakIndex] = maxk(powerMap(:), nPeaks);
mask = false(size(powerMap));
guardR = 2; guardV = 2;
for k = 1:numel(peakIndex)
    [ir, iv] = ind2sub(size(powerMap), peakIndex(k));
    rIdx = max(1, ir - guardR):min(Ns, ir + guardR);
    vIdx = max(1, iv - guardV):min(L, iv + guardV);
    mask(rIdx, vIdx) = true;
end

background = powerMap(~mask & ~badMask);
noiseFloor = median(background(:), 'omitnan');
snrDb = 10 * log10(mean(peakValues, 'omitnan') / max(noiseFloor, eps));
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
