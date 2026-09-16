% =========================================================================
% task_output_snr_vs_mrx_lagrange_sic.m
%   横轴：接收天线数 Mrx
%   纵轴：Output SNR (dB)
%   三条曲线：
%     1. ZF
%     2. Lagrange
%     3. Lagrange + digital SIC (LS SIC)
%
%   完整 SI 注入版：使用 simulate_radar_channel_3d，不是 fast 跳过 SI 的版本。
%   参数：Ns=3168, L=256, beta_SI=10, input SNR=0 dB
%
%   运行：
%     matlab -batch "task_output_snr_vs_mrx_lagrange_sic"
%
%   输出：
%     fig/fig_output_snr_vs_mrx_lagrange_sic.fig/.png
% =========================================================================
function task_output_snr_vs_mrx_lagrange_sic()
t_all = tic;
warning('off','all');

% ==================== 0. Log ==============================================
log_path = fullfile(pwd, 'task_output_snr_vs_mrx_lagrange_sic.log');
if isfile(log_path), delete(log_path); end
diary(log_path); diary on;

% ==================== 1. 参数 =============================================
methods       = {'zf', 'lagrange', 'lagrange'};
sic_flags     = [false, false, true];
method_labels = {'ZF', 'Lagrange', 'Lagrange + digital SIC'};
n_methods     = numel(methods);

n_mc        = 30;      % 蒙特卡洛次数
input_snr   = 0;
beta_SI     = 10;

M_list    = [2, 4, 6, 8];
Mrx_list  = M_list.^2;
n_mrx     = numel(Mrx_list);

N_val = 3168;
L_val = 256;

fprintf('============================================================\n');
fprintf('  Output SNR vs Mrx  |  ZF / Lagrange / Lagrange+SIC\n');
fprintf('  Ns=%d, L=%d, beta_SI=%g, SNR=%d dB, MC=%d\n', ...
    N_val, L_val, beta_SI, input_snr, n_mc);
fprintf('  Mrx: %s\n', mat2str(Mrx_list));
fprintf('============================================================\n\n');

rng(20260801);
rng_seeds = randi(2^31-1, n_methods, n_mrx, n_mc);

% ==================== 2. 基础参数 =========================================
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
baseParams.fast_estimator.n_samp_l = min(64, max(8, floor(L_val/2)));
fprintf('  fc=%.1f GHz, Ntx=%d\n\n', baseParams.fc/1e9, baseParams.Ntx*baseParams.Nty);

Nt_total = baseParams.Ntx * baseParams.Nty;

% 预编码用 SI 信道（固定 64 行）
rng(20260730);
hsi_cfg_tx = struct( ...
    'model','ura_rician', 'Nt_total',Nt_total, 'Nr_total',64, ...
    'kappa_SI',10, 'Ntx',baseParams.Ntx, 'Nty',baseParams.Nty, ...
    'Mx',8, 'My',8, 'd_lambda',0.5, ...
    'theta_tx_deg',baseParams.theta_SI, 'phi_tx_deg',baseParams.phi_SI, ...
    'theta_rx_deg',baseParams.theta_SI, 'phi_rx_deg',baseParams.phi_SI, ...
    'seed', 20260730);
H_SI_common = generate_HSI(hsi_cfg_tx);
fprintf('  H_SI_common: %d×%d\n\n', size(H_SI_common));

% ==================== 2.5 并行 ============================================
use_par = license('test', 'Distrib_Computing_Toolbox') && exist('parpool', 'file') == 2;
if use_par
    try
        n_workers = min(8, max(2, feature('numcores')));
        if isempty(gcp('nocreate'))
            parpool('Processes', n_workers);
        end
        fprintf('  Parallel: parfor %d workers\n\n', n_workers);
    catch
        use_par = false;
        fprintf('  Parallel not available, use serial\n\n');
    end
else
    fprintf('  Parallel not available, use serial\n\n');
end

% ==================== 3. 预分配 ===========================================
snr_mrx = NaN(n_methods, n_mrx, n_mc);

% ==================== 4. Mrx sweep ========================================
for mi = 1:n_methods
    p_method = baseParams;
    p_method.precoder_type = methods{mi};
    p_method.H_SI = H_SI_common;

    tx = generate_mimo_ofdm_waveform(p_method);
    X_tx = tx.X;
    clear tx;
    fprintf('  [%s] TX: [%d×%d×%d×%d]\n', method_labels{mi}, ...
        size(X_tx,1), size(X_tx,2), size(X_tx,3), size(X_tx,4));

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

        fprintf('  %s Mrx=%d (%d×%d) ', method_labels{mi}, Mrx_val, M_val, M_val);
        if use_par
            parfor mc_i = 1:n_mc
                snr_mrx(mi, mi_mrx, mc_i) = local_mc_snr_full( ...
                    rng_seeds(mi, mi_mrx, mc_i), X_tx, p);
            end
        else
            for mc_i = 1:n_mc
                snr_mrx(mi, mi_mrx, mc_i) = local_mc_snr_full( ...
                    rng_seeds(mi, mi_mrx, mc_i), X_tx, p);
                if mod(mc_i, 5) == 0, fprintf('.'); end
            end
        end
        fprintf(' -> %.2f dB\n', mean(snr_mrx(mi, mi_mrx, :), 'omitnan'));
    end
    clear X_tx;
end

% ==================== 5. 汇总 =============================================
snr_mrx_avg = squeeze(mean(snr_mrx, 3, 'omitnan'));
fprintf('\n--- Output SNR vs Mrx (mean over MC) ---\n');
for mi = 1:n_methods
    fprintf('  %-28s: %s\n', method_labels{mi}, ...
        sprintf('%.2f ', snr_mrx_avg(mi, :)));
end

snr_mrx_all = snr_mrx;
save(fullfile(pwd, 'task_output_snr_vs_mrx_lagrange_sic.mat'), ...
    'Mrx_list', 'M_list', 'n_mc', 'input_snr', 'beta_SI', ...
    'N_val', 'L_val', 'methods', 'sic_flags', 'method_labels', ...
    'snr_mrx_all', 'snr_mrx_avg');

% ==================== 6. 出图 =============================================
fprintf('\n--- Save figure ---\n');
fig_dir = fullfile(pwd, 'fig');
if ~exist(fig_dir, 'dir'), mkdir(fig_dir); end

fig = create_output_snr_figure(Mrx_list, snr_mrx_avg, ...
    'The number of receive antennas', ...
    '(a) Impact of the number of receive antennas (beamforming, full SI)');
fig_path = fullfile(fig_dir, 'fig_output_snr_vs_mrx_lagrange_sic');
savefig(fig, [fig_path '.fig']);
exportgraphics(fig, [fig_path '.png'], 'Resolution', 300);
fprintf('  saved: %s.fig/.png\n', fig_path);
close(fig);

fprintf('\nDone. 总耗时 %.1f min\n', toc(t_all)/60);
diary off;
end

% =========================================================================
% parfor helper
% =========================================================================
function snrDb = local_mc_snr_full(seed, X_tx, p)
rng(seed);
rx_cube = simulate_radar_channel_3d(X_tx, p);
snrDb = local_output_snr_db(rx_cube, X_tx, p);
end

% =========================================================================
% Output-SNR 计算（带近距离门限，防止把 SI 峰当目标）
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

% =========================================================================
% 出图
% =========================================================================
function fig = create_output_snr_figure(x, y_mat, xLabel, titleText)
fig = figure('Color', 'w', 'Units', 'pixels', ...
    'Position', [100, 140, 620, 470], 'Name', titleText);
ax = axes('Parent', fig);
hold(ax, 'on');

colors    = {[0.85 0.15 0.12], [0.00 0.45 0.74], [0.10 0.60 0.20]};
markers   = {'o', 's', '^'};
linestyles = {'-', '--', '-.'};
labels    = {'ZF', 'Lagrange', 'Lagrange + digital SIC'};

for k = 1:size(y_mat, 1)
    plot(ax, x, y_mat(k, :), ...
        'Color', colors{k}, ...
        'Marker', markers{k}, ...
        'LineStyle', linestyles{k}, ...
        'MarkerSize', 6, ...
        'LineWidth', 1.4, ...
        'MarkerFaceColor', 'w', ...
        'DisplayName', labels{k});
end

xlabel(ax, xLabel, 'FontName', 'Times New Roman', 'FontSize', 10);
ylabel(ax, 'Output-SNR (dB)', 'FontName', 'Times New Roman', 'FontSize', 10);
title(ax, titleText, 'FontName', 'Times New Roman', ...
    'FontSize', 10, 'FontWeight', 'normal');
set(ax, 'XScale', 'log');
set(ax, 'XTick', [10, 100, 1000, 10000]);
xlim(ax, [min(x), max(x)]);
y_finite = y_mat(isfinite(y_mat));
if ~isempty(y_finite)
    ylo = floor(min(y_finite)/10)*10;
    yhi = ceil(max(y_finite)/10)*10;
    if yhi - ylo < 10, yhi = ylo + 10; end
    ylim(ax, [ylo, yhi]);
    set(ax, 'YTick', ylo:10:yhi);
end
legend(ax, labels, 'Location', 'southeast', 'Box', 'on');
apply_nature_axes(ax);
hold(ax, 'off');
end
