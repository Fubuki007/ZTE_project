% =========================================================================
% task_output_snr_sweep_zf_null_sic_full.m
%   完整版 Output-SNR 扫描：SI 真实注入 + 三种方案对比
%
%   三条曲线：
%     1. ZF                         传统 ZF，无 SI 抑制
%     2. Null-space                 零空间法预编码，无数字 SIC
%     3. Null-space + digital SIC   零空间法预编码 + 数字 SIC
%
%   与 fast 版的区别：
%     - 使用 simulate_radar_channel_3d 完整注入 SI，不再跳过 SI
%     - enable_SIC 按方案分别设置
%     - 能直接看到 ZF / Null-space / Null-space+SIC 的输出 SNR 差异
%
%   运行：
%     matlab -batch "task_output_snr_sweep_zf_null_sic_full"
%
%   输出：
%     fig/fig_output_snr_vs_mrx_zf_null_sic_full.fig/.png
%     fig/fig_output_snr_vs_subcarriers_zf_null_sic_full.fig/.png
%     fig/fig_output_snr_vs_cpi_length_zf_null_sic_full.fig/.png
% =========================================================================
function task_output_snr_sweep_zf_null_sic_full()
t_all = tic;
warning('off','all');

% ==================== 0. 日志 ============================================
log_path = fullfile(pwd, 'matlab_zf_null_sic_full_output_snr.log');
if isfile(log_path), delete(log_path); end
diary(log_path); diary on;

% ==================== 1. 扫描参数 ========================================
n_mc        = 30;
input_snr   = 0;
beta_SI     = 10;      % 建议 10，能明显看出三条曲线差异；调小则三条会靠拢

methods     = {'zf', 'nullspace', 'nullspace'};
enable_SIC  = [false, false, true];
method_labels = {'ZF', 'Null-space', 'Null-space + digital SIC'};
n_methods   = numel(methods);

M_list    = [2, 4, 6, 8];
Mrx_list  = M_list.^2;
n_mrx     = numel(Mrx_list);

Ns_list   = [512, 1024, 2048, 3168, 6336];
n_ns      = numel(Ns_list);

L_list    = [16, 32, 64, 128, 256];
n_L       = numel(L_list);

fprintf('═══════════════════════════════════════════════════════════════\n');
fprintf('  task_output_snr_sweep_zf_null_sic_full\n');
fprintf('  SI=ON, beta_SI=%g, input SNR=%d dB, MC=%d\n', beta_SI, input_snr, n_mc);
fprintf('  方法: %s\n', strjoin(method_labels, ' | '));
fprintf('  Mrx: %s\n', mat2str(Mrx_list));
fprintf('  Ns:  %s\n', mat2str(Ns_list));
fprintf('  L:   %s\n', mat2str(L_list));
fprintf('═══════════════════════════════════════════════════════════════\n\n');

rng(20260801);
rng_seeds = randi(2^31-1, n_methods, max([n_mrx, n_ns, n_L]), n_mc, 3);

% ==================== 2. 基础参数 ========================================
baseParams = build_default_params();
baseParams.enable_SI  = true;
baseParams.beta_SI    = beta_SI;
baseParams.SNR        = input_snr;
baseParams.K_stream   = 2;
baseParams.user_theta_rad = deg2rad(baseParams.theta_true(:));
baseParams.user_phi_rad   = deg2rad(baseParams.phi_true(:));
fprintf('  fc=%.1f GHz, Ntx=%d\n\n', baseParams.fc/1e9, baseParams.Ntx*baseParams.Nty);

Nt_total = baseParams.Ntx * baseParams.Nty;

% 预编码器用的 SI 信道（与接收阵 Mrx 无关，固定 64 行）
rng(20260730);
hsi_cfg_tx = struct( ...
    'model','ura_rician', 'Nt_total',Nt_total, 'Nr_total',64, ...
    'kappa_SI',10, 'Ntx',baseParams.Ntx, 'Nty',baseParams.Nty, ...
    'Mx',8, 'My',8, 'd_lambda',0.5, ...
    'theta_tx_deg',baseParams.theta_SI, 'phi_tx_deg',baseParams.phi_SI, ...
    'theta_rx_deg',baseParams.theta_SI, 'phi_rx_deg',baseParams.phi_SI, ...
    'seed', 20260730);
H_SI_common = generate_HSI(hsi_cfg_tx);
fprintf('  H_SI_common: %d×%d (预编码诊断用)\n\n', size(H_SI_common));

% ==================== 2.5 并行检测 ========================================
use_par = license('test', 'Distrib_Computing_Toolbox') && exist('parpool', 'file') == 2;
if use_par
    try
        n_workers = min(8, max(2, feature('numcores')));
        if isempty(gcp('nocreate'))
            parpool('Processes', n_workers);
        end
        fprintf('  并行: parfor %d workers\n\n', n_workers);
    catch
        use_par = false;
        fprintf('  并行启动失败，退回串行\n\n');
    end
else
    fprintf('  并行不可用，串行运行\n\n');
end

% ==================== 3. 预分配 ==========================================
snr_mrx = NaN(n_methods, n_mrx, n_mc);
snr_ns  = NaN(n_methods, n_ns,  n_mc);
snr_L   = NaN(n_methods, n_L,   n_mc);

% ==================== 4a. Mrx sweep ======================================
fprintf('\n==== (a) Mrx sweep ====\n');
baseParams_4a = baseParams;
baseParams_4a.N = 3168;
baseParams_4a.B = baseParams_4a.N * 120e3;
baseParams_4a.K = 256;
baseParams_4a.meta.range_resolution = baseParams_4a.c / (2 * baseParams_4a.B);

for mi = 1:n_methods
    p_method = baseParams_4a;
    p_method.precoder_type = methods{mi};
    p_method.enable_SIC = enable_SIC(mi);
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
                    rng_seeds(mi, mi_mrx, mc_i, 1), X_tx, p);
            end
        else
            for mc_i = 1:n_mc
                rng(rng_seeds(mi, mi_mrx, mc_i, 1));
                rxCube = simulate_radar_channel_3d(X_tx, p);
                snr_mrx(mi, mi_mrx, mc_i) = local_output_snr_db(rxCube, X_tx, p);
                clear rxCube;
                if mod(mc_i, 5) == 0, fprintf('.'); end
            end
        end
        fprintf(' -> %.1f dB\n', mean(snr_mrx(mi, mi_mrx, :), 'omitnan'));
    end
    clear X_tx;
end

% ==================== 4b. Ns sweep =======================================
fprintf('\n==== (b) Ns sweep ====\n');
for mi = 1:n_methods
    for ni = 1:n_ns
        Ns_val = Ns_list(ni);
        p = baseParams;
        p.precoder_type = methods{mi};
        p.enable_SIC = enable_SIC(mi);
        p.H_SI = H_SI_common;
        p.Mx = 8; p.My = 8;
        p.joint_fft_3d.Na_x = 8;
        p.joint_fft_3d.Na_y = 8;
        p.N = Ns_val;
        p.B = Ns_val * 120e3;
        p.K = 256;
        p.meta.range_resolution = p.c / (2 * p.B);
        p.joint_fft_3d.Nr = Ns_val;

        hsi_cfg_rx64 = struct( ...
            'model','ura_rician', 'Nt_total',Nt_total, 'Nr_total',64, ...
            'kappa_SI',10, 'Ntx',baseParams.Ntx, 'Nty',baseParams.Nty, ...
            'Mx',8, 'My',8, 'd_lambda',0.5, ...
            'theta_tx_deg',baseParams.theta_SI, 'phi_tx_deg',baseParams.phi_SI, ...
            'theta_rx_deg',baseParams.theta_SI, 'phi_rx_deg',baseParams.phi_SI, ...
            'seed', 20260731);
        p.H_SI_matrix = generate_HSI(hsi_cfg_rx64);

        tx_ns = generate_mimo_ofdm_waveform(p);
        X_tx_ns = tx_ns.X;
        clear tx_ns;

        fprintf('  %s Ns=%d (B=%.1f MHz) ', method_labels{mi}, Ns_val, p.B/1e6);
        if use_par
            parfor mc_i = 1:n_mc
                snr_ns(mi, ni, mc_i) = local_mc_snr_full( ...
                    rng_seeds(mi, ni, mc_i, 2), X_tx_ns, p);
            end
        else
            for mc_i = 1:n_mc
                rng(rng_seeds(mi, ni, mc_i, 2));
                rxCube = simulate_radar_channel_3d(X_tx_ns, p);
                snr_ns(mi, ni, mc_i) = local_output_snr_db(rxCube, X_tx_ns, p);
                clear rxCube;
                if mod(mc_i, 5) == 0, fprintf('.'); end
            end
        end
        clear X_tx_ns;
        fprintf(' -> %.1f dB\n', mean(snr_ns(mi, ni, :), 'omitnan'));
    end
end

% ==================== 4c. L sweep ========================================
fprintf('\n==== (c) L sweep ====\n');
for mi = 1:n_methods
    for li = 1:n_L
        L_val = L_list(li);
        p = baseParams;
        p.precoder_type = methods{mi};
        p.enable_SIC = enable_SIC(mi);
        p.H_SI = H_SI_common;
        p.Mx = 8; p.My = 8;
        p.joint_fft_3d.Na_x = 8;
        p.joint_fft_3d.Na_y = 8;
        p.N = 3168;
        p.B = p.N * 120e3;
        p.K = L_val;
        p.meta.range_resolution = p.c / (2 * p.B);
        p.fast_estimator.n_samp_l = min(64, max(8, floor(L_val/2)));

        hsi_cfg_rx64 = struct( ...
            'model','ura_rician', 'Nt_total',Nt_total, 'Nr_total',64, ...
            'kappa_SI',10, 'Ntx',baseParams.Ntx, 'Nty',baseParams.Nty, ...
            'Mx',8, 'My',8, 'd_lambda',0.5, ...
            'theta_tx_deg',baseParams.theta_SI, 'phi_tx_deg',baseParams.phi_SI, ...
            'theta_rx_deg',baseParams.theta_SI, 'phi_rx_deg',baseParams.phi_SI, ...
            'seed', 20260731);
        p.H_SI_matrix = generate_HSI(hsi_cfg_rx64);

        tx_l = generate_mimo_ofdm_waveform(p);
        X_tx_l = tx_l.X;
        clear tx_l;

        fprintf('  %s L=%d ', method_labels{mi}, L_val);
        if use_par
            parfor mc_i = 1:n_mc
                snr_L(mi, li, mc_i) = local_mc_snr_full( ...
                    rng_seeds(mi, li, mc_i, 3), X_tx_l, p);
            end
        else
            for mc_i = 1:n_mc
                rng(rng_seeds(mi, li, mc_i, 3));
                rxCube = simulate_radar_channel_3d(X_tx_l, p);
                snr_L(mi, li, mc_i) = local_output_snr_db(rxCube, X_tx_l, p);
                clear rxCube;
                if mod(mc_i, 5) == 0, fprintf('.'); end
            end
        end
        clear X_tx_l;
        fprintf(' -> %.1f dB\n', mean(snr_L(mi, li, :), 'omitnan'));
    end
end

fprintf('\n总仿真时间: %.1f min\n', toc(t_all)/60);

% ==================== 5. 汇总 ============================================
snr_mrx_avg = squeeze(mean(snr_mrx, 3, 'omitnan'));
snr_ns_avg  = squeeze(mean(snr_ns,  3, 'omitnan'));
snr_L_avg   = squeeze(mean(snr_L,   3, 'omitnan'));

fprintf('\n--- Mrx sweep ---\n');
for mi = 1:n_methods
    fprintf('  %-28s: %s\n', method_labels{mi}, ...
        sprintf('%.2f ', snr_mrx_avg(mi, :)));
end
fprintf('\n--- Ns sweep ---\n');
for mi = 1:n_methods
    fprintf('  %-28s: %s\n', method_labels{mi}, ...
        sprintf('%.2f ', snr_ns_avg(mi, :)));
end
fprintf('\n--- L sweep ---\n');
for mi = 1:n_methods
    fprintf('  %-28s: %s\n', method_labels{mi}, ...
        sprintf('%.2f ', snr_L_avg(mi, :)));
end

% 保存数据
snr_mrx_all = snr_mrx;
snr_ns_all  = snr_ns;
snr_L_all   = snr_L;

save(fullfile(pwd, 'task_output_snr_zf_null_sic_full.mat'), ...
    'Mrx_list', 'Ns_list', 'L_list', 'beta_SI', 'input_snr', 'n_mc', ...
    'methods', 'enable_SIC', 'method_labels', ...
    'snr_mrx_all', 'snr_ns_all', 'snr_L_all', ...
    'snr_mrx_avg', 'snr_ns_avg', 'snr_L_avg');

% ==================== 6. 出图 ============================================
fprintf('\n--- 出图 (3 条线, .fig + .png) ---\n');
fig_dir = fullfile(pwd, 'fig');
if ~exist(fig_dir, 'dir'), mkdir(fig_dir); end

fig_specs = {
    Mrx_list, snr_mrx_avg, 'The number of receive antennas', ...
        '(a) Impact of the number of receive antennas', 'fig_output_snr_vs_mrx_zf_null_sic_full';
    Ns_list, snr_ns_avg, 'The number of subcarriers', ...
        '(b) Impact of the number of subcarriers', 'fig_output_snr_vs_subcarriers_zf_null_sic_full';
    L_list, snr_L_avg, 'The CPI length', ...
        '(c) Impact of CPI length (beamforming)', 'fig_output_snr_vs_cpi_length_zf_null_sic_full'
};

for fig_i = 1:size(fig_specs, 1)
    fig = create_output_snr_figure(fig_specs{fig_i, 1}, fig_specs{fig_i, 2}, ...
        fig_specs{fig_i, 3}, fig_specs{fig_i, 4}, fig_i);
    fig_path = fullfile(fig_dir, [fig_specs{fig_i, 5}, '.fig']);
    png_path = fullfile(fig_dir, [fig_specs{fig_i, 5}, '.png']);
    savefig(fig, fig_path);
    exportgraphics(fig, png_path, 'Resolution', 300);
    fprintf('  已保存: %s\n  已保存: %s\n', fig_path, png_path);
    close(fig);
end

% ==================== 7. Toast ===========================================
toast_script = fullfile(pwd, 'toast_notify.py');
if isfile(toast_script)
    try
        system(sprintf('python "%s" "SNR-H full 完成" "%.1f min"', ...
            toast_script, toc(t_all)/60));
    catch
    end
end

fprintf('\n完成: %s | 总耗时: %.1f min\n', char(datetime('now')), toc(t_all)/60);
diary off;
end

% =========================================================================
% parfor 单 MC 封装：种子在辅助函数内部设置，避免 parfor 透明度违规
% =========================================================================
function snrDb = local_mc_snr_full(seed, X_tx, params)
rng(seed);
rxCube = simulate_radar_channel_3d(X_tx, params);
snrDb = local_output_snr_db(rxCube, X_tx, params);
end

% =========================================================================
% Output-SNR 计算
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

% 排除近距离假峰/自干扰产生的 DC 附近峰（例如 beta_SI 较强时）
% 这样 Output-SNR 衡量的是目标峰相对背景干扰+噪声，而不是把 SI 峰当成目标
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
% 出图：3 条曲线
% =========================================================================
function fig = create_output_snr_figure(x, y_mat, xLabelText, titleText, figIndex)
fig = figure('Color', 'w', 'Units', 'pixels', ...
    'Position', [100 + 35 * figIndex, 140 + 35 * figIndex, 560, 420], ...
    'Name', titleText);
ax = axes('Parent', fig);
hold(ax, 'on');

colors    = {[0.85 0.15 0.12], [0.00 0.45 0.74], [0.10 0.60 0.20]};
markers   = {'o', 's', '^'};
linestyles = {'-', '--', '-.'};
labels    = {'ZF', 'Null-space', 'Null-space + digital SIC'};

for k = 1:size(y_mat, 1)
    plot(ax, x, y_mat(k, :), ...
        'Color', colors{k}, ...
        'Marker', markers{k}, ...
        'LineStyle', linestyles{k}, ...
        'MarkerSize', 5.5, ...
        'LineWidth', 1.3, ...
        'MarkerFaceColor', 'w', ...
        'DisplayName', labels{k});
end

xlabel(ax, xLabelText, 'FontName', 'Times New Roman', 'FontSize', 10);
ylabel(ax, 'Output-SNR (dB)', 'FontName', 'Times New Roman', 'FontSize', 10);
title(ax, titleText, 'FontName', 'Times New Roman', ...
    'FontSize', 10, 'FontWeight', 'normal');
set(ax, 'XScale', 'log');
set(ax, 'XTick', [10, 100, 1000, 10000]);
xlim(ax, [min(x), max(x)]);
y_finite = y_mat(isfinite(y_mat));
if ~isempty(y_finite)
    ylo = floor(min(y_finite) / 10) * 10;
    yhi = ceil(max(y_finite) / 10) * 10;
    if yhi - ylo < 10, yhi = ylo + 10; end
    ylim(ax, [ylo, yhi]);
    set(ax, 'YTick', ylo:10:yhi);
end
legend(ax, labels, 'Location', 'southeast', 'Box', 'on');
apply_nature_axes(ax);
hold(ax, 'off');
end
