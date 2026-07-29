% =========================================================================
% task_output_snr_sweep.m — Output-SNR vs 天线数/子载波数/CPI长度
%
%   复现三张图:
%     (a) Impact of the number of receive antennas  (Mrx sweep)
%     (b) Impact of the number of subcarriers       (Ns sweep)
%     (c) Impact of CPI length                      (L sweep)
%
%   算法: 参考 run_nature_performance_plots.m 的 local_output_snr_db
%   参数: input SNR=0dB, SI=OFF, ZF预编码, MC=30
%   预估: ~15-20 分钟
% =========================================================================
function task_output_snr_sweep()
t_all = tic;
warning('off','all');

% ==================== 0. 日志 ============================================
log_path = fullfile(pwd, 'matlab_run.log');
if isfile(log_path), delete(log_path); end
diary(log_path); diary on;

fprintf('═══════════════════════════════════════════════════════════════\n');
fprintf('  task_output_snr_sweep — Output-SNR 参数扫描\n');
fprintf('  开始: %s\n', char(datetime('now')));
fprintf('═══════════════════════════════════════════════════════════════\n\n');

% ==================== 1. 扫描参数 ========================================
n_mc        = 30;
input_snr   = 0;            % 固定输入 SNR

% (a) Mrx sweep — 正方形 URA
M_list    = [2, 4, 6, 8];            % 每维天线数
Mrx_list  = M_list.^2;               % [4, 16, 36, 64]
n_mrx     = numel(Mrx_list);

% (b) Ns sweep
Ns_list   = [512, 1024, 2048, 3168, 6336];
n_ns      = numel(Ns_list);

% (c) L sweep (CPI length = params.K)
L_list    = [16, 32, 64, 128, 256];
n_L       = numel(L_list);

fprintf('  输入 SNR: %d dB | MC: %d | SI=OFF\n', input_snr, n_mc);
fprintf('  Mrx: %s\n', mat2str(Mrx_list));
fprintf('  Ns:  %s\n', mat2str(Ns_list));
fprintf('  L:   %s\n\n', mat2str(L_list));

rng(20260728);
rng_seeds = randi(2^31-1, max([n_mrx, n_ns, n_L]), n_mc, 3);

% ==================== 2. 基础参数 (不含扫参变量) ===========================
baseParams = build_default_params();
baseParams.enable_SI  = false;
baseParams.SNR        = input_snr;
baseParams.K_stream   = 2;
baseParams.user_theta_rad = deg2rad(baseParams.theta_true(:));
baseParams.user_phi_rad   = deg2rad(baseParams.phi_true(:));
fprintf('  fc=%.1f GHz, Ntx=%d\n\n', baseParams.fc/1e9, baseParams.Ntx*baseParams.Nty);

% ==================== 3. 预分配 ==========================================
snr_mrx  = NaN(n_mrx, n_mc);
snr_ns   = NaN(n_ns,  n_mc);
snr_L    = NaN(n_L,   n_mc);

% ==================== 4a. Mrx sweep ======================================
fprintf('==== (a) Mrx sweep ====\n');
baseParams_4a = baseParams;
baseParams_4a.N = 3168;
baseParams_4a.B = baseParams_4a.N * 120e3;
baseParams_4a.K = 256;
baseParams_4a.meta.range_resolution = baseParams_4a.c / (2 * baseParams_4a.B);

tx_4a = generate_mimo_ofdm_waveform(baseParams_4a);
X_tx_4a = tx_4a.X;
clear tx_4a;
fprintf('  TX: [%d×%d×%d×%d]\n', size(X_tx_4a,1), size(X_tx_4a,2), size(X_tx_4a,3), size(X_tx_4a,4));

for mi = 1:n_mrx
    M_val  = M_list(mi);
    Mrx_val = Mrx_list(mi);
    p = baseParams_4a;
    p.Mx = M_val; p.My = M_val;
    p.joint_fft_3d.Na_x = M_val;
    p.joint_fft_3d.Na_y = M_val;
    
    fprintf('  Mrx=%d (%d×%d) ', Mrx_val, M_val, M_val);
    for mc_i = 1:n_mc
        rng(rng_seeds(mi, mc_i, 1));
        rxCube = simulate_radar_channel_3d(X_tx_4a, p);
        snr_mrx(mi, mc_i) = local_output_snr_db(rxCube, X_tx_4a, p);
        clear rxCube;
        if mod(mc_i, 10) == 0, fprintf('.'); end
    end
    fprintf(' → %.1f dB\n', mean(snr_mrx(mi, :), 'omitnan'));
end

% ==================== 4b. Ns sweep =======================================
fprintf('\n==== (b) Ns sweep ====\n');
for ni = 1:n_ns
    Ns_val = Ns_list(ni);
    p = baseParams;
    p.Mx = 8; p.My = 8;
    p.joint_fft_3d.Na_x = 8;
    p.joint_fft_3d.Na_y = 8;
    p.N = Ns_val;
    p.B = Ns_val * 120e3;
    p.K = 256;
    p.meta.range_resolution = p.c / (2 * p.B);
    p.joint_fft_3d.Nr = Ns_val;
    
    tx_ns = generate_mimo_ofdm_waveform(p);
    X_tx_ns = tx_ns.X;
    clear tx_ns;
    
    fprintf('  Ns=%d (B=%.1f MHz) ', Ns_val, p.B/1e6);
    for mc_i = 1:n_mc
        rng(rng_seeds(ni, mc_i, 2));
        rxCube = simulate_radar_channel_3d(X_tx_ns, p);
        snr_ns(ni, mc_i) = local_output_snr_db(rxCube, X_tx_ns, p);
        clear rxCube;
        if mod(mc_i, 10) == 0, fprintf('.'); end
    end
    clear X_tx_ns;
    fprintf(' → %.1f dB\n', mean(snr_ns(ni, :), 'omitnan'));
end

% ==================== 4c. L sweep ========================================
fprintf('\n==== (c) L sweep ====\n');
for li = 1:n_L
    L_val = L_list(li);
    p = baseParams;
    p.Mx = 8; p.My = 8;
    p.joint_fft_3d.Na_x = 8;
    p.joint_fft_3d.Na_y = 8;
    p.N = 3168;
    p.B = p.N * 120e3;
    p.K = L_val;
    p.meta.range_resolution = p.c / (2 * p.B);
    p.fast_estimator.n_samp_l = min(64, max(8, floor(L_val/2)));
    
    tx_l = generate_mimo_ofdm_waveform(p);
    X_tx_l = tx_l.X;
    clear tx_l;
    
    fprintf('  L=%d ', L_val);
    for mc_i = 1:n_mc
        rng(rng_seeds(li, mc_i, 3));
        rxCube = simulate_radar_channel_3d(X_tx_l, p);
        snr_L(li, mc_i) = local_output_snr_db(rxCube, X_tx_l, p);
        clear rxCube;
        if mod(mc_i, 10) == 0, fprintf('.'); end
    end
    clear X_tx_l;
    fprintf(' → %.1f dB\n', mean(snr_L(li, :), 'omitnan'));
end

fprintf('\n总仿真时间: %.1f min\n', toc(t_all)/60);

% ==================== 5. 汇总 ============================================
snr_mrx_avg = mean(snr_mrx, 2, 'omitnan');
snr_ns_avg  = mean(snr_ns,  2, 'omitnan');
snr_L_avg   = mean(snr_L,   2, 'omitnan');

fprintf('\n--- Mrx sweep ---\n');
for mi = 1:n_mrx
    fprintf('  Mrx=%3d: %.2f dB\n', Mrx_list(mi), snr_mrx_avg(mi));
end
fprintf('\n--- Ns sweep ---\n');
for ni = 1:n_ns
    fprintf('  Ns=%5d: %.2f dB\n', Ns_list(ni), snr_ns_avg(ni));
end
fprintf('\n--- L sweep ---\n');
for li = 1:n_L
    fprintf('  L=%4d: %.2f dB\n', L_list(li), snr_L_avg(li));
end

% ==================== 6. 出图 (三个独立图窗，每图一条曲线) ====================
fprintf('\n--- 出图 (三个独立 .fig) ---\n');
fig_dir = fullfile(pwd, 'fig');
if ~exist(fig_dir, 'dir'), mkdir(fig_dir); end

fig_specs = {
    Mrx_list, snr_mrx_avg, 'Number of receive antennas', ...
        'Output-SNR vs receive antennas', 'fig_output_snr_vs_mrx.fig';
    Ns_list, snr_ns_avg, 'Number of subcarriers', ...
        'Output-SNR vs subcarriers', 'fig_output_snr_vs_subcarriers.fig';
    L_list, snr_L_avg, 'CPI length', ...
        'Output-SNR vs CPI length', 'fig_output_snr_vs_cpi_length.fig'
};

for fig_i = 1:size(fig_specs, 1)
    fig = create_output_snr_figure(fig_specs{fig_i, 1}, fig_specs{fig_i, 2}, ...
        fig_specs{fig_i, 3}, fig_specs{fig_i, 4}, fig_i);
    fig_path = fullfile(fig_dir, fig_specs{fig_i, 5});
    savefig(fig, fig_path);
    fprintf('  已保存: %s\n', fig_path);
end

% ==================== 7. Toast ===========================================
toast_script = fullfile(pwd, 'toast_notify.py');
if isfile(toast_script)
    try
        system(sprintf('python "%s" "SNR-sweep完成" "%.1f min"', toast_script, toc(t_all)/60));
    catch
    end
end

fprintf('\n═══════════════════════════════════════════════════════════════\n');
fprintf('  完成: %s | 总耗时: %.1f min\n', char(datetime('now')), toc(t_all)/60);
fprintf('═══════════════════════════════════════════════════════════════\n');
diary off;
end

% ==================== 局部函数: Output-SNR 计算 ===========================
function snrDb = local_output_snr_db(rxCube, txSignal, params)
[Mx, My, Ns, L] = size(rxCube);
selectedAnt = ceil((Mx * My) / 2);
[selectedX, selectedY] = ind2sub([Mx, My], selectedAnt);
rxSelected = reshape(rxCube(selectedX, selectedY, :, :), Ns, L);
rxEq = local_equalize_rx(rxSelected, txSignal);
rd = fft(rxEq, Ns, 1);
rd = fftshift(fft(rd, L, 2), 2);
powerMap = abs(rd).^2;

nPeaks = max(1, min(params.num_targets, numel(powerMap)));
[peakValues, peakIndex] = maxk(powerMap(:), nPeaks);
mask = false(size(powerMap));
guardR = 2;
guardV = 2;
for k = 1:numel(peakIndex)
    [ir, iv] = ind2sub(size(powerMap), peakIndex(k));
    rIdx = max(1, ir - guardR):min(Ns, ir + guardR);
    vIdx = max(1, iv - guardV):min(L, iv + guardV);
    mask(rIdx, vIdx) = true;
end

background = powerMap(~mask);
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

function fig = create_output_snr_figure(x, y, xLabelText, titleText, figIndex)
fig = figure('Color', 'w', 'Units', 'pixels', ...
    'Position', [100 + 35 * figIndex, 140 + 35 * figIndex, 560, 420], ...
    'Name', titleText);
ax = axes('Parent', fig);
plot(ax, x, y, '-o', ...
    'Color', [0.85 0.15 0.12], ...
    'MarkerSize', 5.5, ...
    'LineWidth', 1.3, ...
    'MarkerFaceColor', 'w');
xlabel(ax, xLabelText, 'FontName', 'Times New Roman', 'FontSize', 10);
ylabel(ax, 'Output-SNR (dB)', 'FontName', 'Times New Roman', 'FontSize', 10);
title(ax, titleText, 'FontName', 'Times New Roman', ...
    'FontSize', 10, 'FontWeight', 'normal');
set(ax, 'XScale', 'log');
xlim(ax, [min(x), max(x)]);
apply_nature_axes(ax);
end
