% =========================================================================
% task_output_snr_zf_null.m
%   根据项目代码跑三张 Output-SNR 曲线图，每张图两条曲线：
%     1. ZF        (传统 ZF 预编码, 不抑制自干扰)
%     2. Null-space (零空间法预编码, 抑制自干扰)
%
%   基于 task_output_snr_sweep_si_fast.m 的高速版流程修改：
%     - 单天线等效仿真，速度远快于完整 4D 立方体模拟
%     - SI 注入/SIC 相互抵消，与 fast 版相同；保留 precoder 差异
%     - 输出图保存到 fig/ 目录
%
%   运行:
%     matlab -batch "task_output_snr_zf_null"
% =========================================================================
function task_output_snr_zf_null()
t_all = tic;
warning('off','all');

% ==================== 0. 日志 ============================================
log_path = fullfile(pwd, 'matlab_zf_null_output_snr.log');
if isfile(log_path), delete(log_path); end
diary(log_path); diary on;

% ==================== 1. 扫描参数 ========================================
n_mc        = 30;           % 蒙特卡洛次数，可自行调大
input_snr   = 0;            % 固定输入 SNR

methods      = {'zf', 'nullspace'};
method_labels = {'ZF', 'Null-space'};
n_methods    = numel(methods);

% (a) Mrx sweep — 正方形 URA
M_list    = [2, 4, 6, 8];
Mrx_list  = M_list.^2;               % [4, 16, 36, 64]
n_mrx     = numel(Mrx_list);

% (b) Ns sweep
Ns_list   = [512, 1024, 2048, 3168, 6336];
n_ns      = numel(Ns_list);

% (c) L sweep (CPI length = params.K)
L_list    = [16, 32, 64, 128, 256];
n_L       = numel(L_list);

fprintf('输入 SNR: %d dB | MC: %d | SI=ON (beta_SI=0.1, SIC=ON)\n', input_snr, n_mc);
fprintf('方法: %s\n', strjoin(method_labels, ' vs '));
fprintf('Mrx: %s\n', mat2str(Mrx_list));
fprintf('Ns:  %s\n', mat2str(Ns_list));
fprintf('L:   %s\n\n', mat2str(L_list));

rng(20260801);
rng_seeds = randi(2^31-1, n_methods, max([n_mrx, n_ns, n_L]), n_mc, 3);

% ==================== 2. 基础参数 ========================================
baseParams = build_default_params();
baseParams.enable_SI  = true;
baseParams.beta_SI    = 0.1;
baseParams.enable_SIC = true;
baseParams.SNR        = input_snr;
baseParams.K_stream   = 2;
baseParams.user_theta_rad = deg2rad(baseParams.theta_true(:));
baseParams.user_phi_rad   = deg2rad(baseParams.phi_true(:));
fprintf('fc=%.1f GHz, Ntx=%d\n\n', baseParams.fc/1e9, baseParams.Ntx*baseParams.Nty);

% --- SI 信道 H_SI (预编码器使用) ---
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
fprintf('H_SI: %d×%d (Rician κ=10, seed 固定)\n\n', size(H_SI_common));

% ==================== 2.5 并行检测 ========================================
use_par = license('test', 'Distrib_Computing_Toolbox') && exist('parpool', 'file') == 2;
if use_par
    try
        n_workers = min(8, max(2, feature('numcores')));
        if isempty(gcp('nocreate'))
            parpool('Processes', n_workers);
        end
        fprintf('并行: parfor %d workers\n\n', n_workers);
    catch
        use_par = false;
        fprintf('并行: 启动失败, 退回串行\n\n');
    end
else
    fprintf('并行: 不可用, 串行运行\n\n');
end

% ==================== 3. 预分配 ==========================================
snr_mrx  = NaN(n_methods, n_mrx, n_mc);
snr_ns   = NaN(n_methods, n_ns,  n_mc);
snr_L    = NaN(n_methods, n_L,   n_mc);

% ==================== 4a. Mrx sweep ======================================
fprintf('==== (a) Mrx sweep ====\n');
baseParams_4a = baseParams;
baseParams_4a.N = 3168;
baseParams_4a.B = baseParams_4a.N * 120e3;
baseParams_4a.K = 256;
baseParams_4a.meta.range_resolution = baseParams_4a.c / (2 * baseParams_4a.B);

for mi = 1:n_methods
    method = methods{mi};
    p_method = baseParams_4a;
    p_method.precoder_type = method;
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

        [job, txNorm] = local_build_job(X_tx, p);

        fprintf('  %s Mrx=%d (%d×%d) ', method_labels{mi}, Mrx_val, M_val, M_val);
        if use_par
            parfor mc_i = 1:n_mc
                snr_mrx(mi, mi_mrx, mc_i) = local_mc_snr(rng_seeds(mi, mi_mrx, mc_i, 1), job, txNorm);
            end
        else
            for mc_i = 1:n_mc
                snr_mrx(mi, mi_mrx, mc_i) = local_mc_snr(rng_seeds(mi, mi_mrx, mc_i, 1), job, txNorm);
                if mod(mc_i, 10) == 0, fprintf('.'); end
            end
        end
        fprintf(' -> %.1f dB\n', mean(snr_mrx(mi, mi_mrx, :), 'omitnan'));
    end
    clear X_tx;
end

% ==================== 4b. Ns sweep =======================================
fprintf('\n==== (b) Ns sweep ====\n');
for mi = 1:n_methods
    method = methods{mi};
    for ni = 1:n_ns
        Ns_val = Ns_list(ni);
        p = baseParams;
        p.precoder_type = method;
        p.H_SI = H_SI_common;
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
        [job, txNorm] = local_build_job(X_tx_ns, p);

        fprintf('  %s Ns=%d (B=%.1f MHz) ', method_labels{mi}, Ns_val, p.B/1e6);
        if use_par
            parfor mc_i = 1:n_mc
                snr_ns(mi, ni, mc_i) = local_mc_snr(rng_seeds(mi, ni, mc_i, 2), job, txNorm);
            end
        else
            for mc_i = 1:n_mc
                snr_ns(mi, ni, mc_i) = local_mc_snr(rng_seeds(mi, ni, mc_i, 2), job, txNorm);
                if mod(mc_i, 10) == 0, fprintf('.'); end
            end
        end
        clear X_tx_ns;
        fprintf(' -> %.1f dB\n', mean(snr_ns(mi, ni, :), 'omitnan'));
    end
end

% ==================== 4c. L sweep ========================================
fprintf('\n==== (c) L sweep ====\n');
for mi = 1:n_methods
    method = methods{mi};
    for li = 1:n_L
        L_val = L_list(li);
        p = baseParams;
        p.precoder_type = method;
        p.H_SI = H_SI_common;
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
        [job, txNorm] = local_build_job(X_tx_l, p);

        fprintf('  %s L=%d ', method_labels{mi}, L_val);
        if use_par
            parfor mc_i = 1:n_mc
                snr_L(mi, li, mc_i) = local_mc_snr(rng_seeds(mi, li, mc_i, 3), job, txNorm);
            end
        else
            for mc_i = 1:n_mc
                snr_L(mi, li, mc_i) = local_mc_snr(rng_seeds(mi, li, mc_i, 3), job, txNorm);
                if mod(mc_i, 10) == 0, fprintf('.'); end
            end
        end
        clear X_tx_l;
        fprintf(' -> %.1f dB\n', mean(snr_L(mi, li, :), 'omitnan'));
    end
end

fprintf('\n总仿真时间: %.1f min\n', toc(t_all)/60);

% ==================== 5. 汇总 ============================================
snr_mrx_avg = squeeze(mean(snr_mrx, 3, 'omitnan'));   % n_methods x n_mrx
snr_ns_avg  = squeeze(mean(snr_ns,  3, 'omitnan'));
snr_L_avg   = squeeze(mean(snr_L,   3, 'omitnan'));

fprintf('\n--- Mrx sweep (mean over MC) ---\n');
for mi = 1:n_methods
    fprintf('  %-12s: %s\n', method_labels{mi}, ...
        sprintf('%.2f ', snr_mrx_avg(mi, :)));
end
fprintf('\n--- Ns sweep (mean over MC) ---\n');
for mi = 1:n_methods
    fprintf('  %-12s: %s\n', method_labels{mi}, ...
        sprintf('%.2f ', snr_ns_avg(mi, :)));
end
fprintf('\n--- L sweep (mean over MC) ---\n');
for mi = 1:n_methods
    fprintf('  %-12s: %s\n', method_labels{mi}, ...
        sprintf('%.2f ', snr_L_avg(mi, :)));
end

% ==================== 6. 出图 ============================================
fprintf('\n--- 出图 (fig + png, ZF vs Null-space) ---\n');
fig_dir = fullfile(pwd, 'fig');
if ~exist(fig_dir, 'dir'), mkdir(fig_dir); end

fig_specs = {
    Mrx_list, snr_mrx_avg, 'The number of receive antennas', ...
        '(a) Impact of the number of receive antennas', 'fig_output_snr_vs_mrx_zf_null';
    Ns_list, snr_ns_avg, 'The number of subcarriers', ...
        '(b) Impact of the number of subcarriers', 'fig_output_snr_vs_subcarriers_zf_null';
    L_list, snr_L_avg, 'The CPI length', ...
        '(c) Impact of CPI length (beamforming)', 'fig_output_snr_vs_cpi_length_zf_null'
};

for fig_i = 1:size(fig_specs, 1)
    fig = create_output_snr_comparison_figure( ...
        fig_specs{fig_i, 1}, fig_specs{fig_i, 2}, ...
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
        system(sprintf('python "%s" "Output-SNR ZF vs Null-space 完成" "%.1f min"', ...
            toast_script, toc(t_all)/60));
    catch
    end
end

fprintf('\n完成: %s | 总耗时: %.1f min\n', char(datetime('now')), toc(t_all)/60);
diary off;
end

% =========================================================================
% 局部函数: 预计算 job（单天线等效）
% =========================================================================
function [job, txNorm] = local_build_job(tx_signal, params)
[Ntx, Nty, Ns, L] = size(tx_signal);
Nt   = Ntx * Nty;
Q    = params.num_targets;
kw   = 2 * pi * params.d / params.lambda;
delta_f = params.B / Ns;

nx_vec = (0:Ntx-1).';
ny_vec = (0:Nty-1).';

selectedAnt = ceil((params.Mx * params.My) / 2);
[selX, selY] = ind2sub([params.Mx, params.My], selectedAnt);

tx_flat = reshape(tx_signal, Nt, Ns, L);

tx_eff = zeros(Ns, L, Q);
coeff  = zeros(Ns, L, Q);
for q = 1:Q
    u = sind(params.theta_true(q)) * cosd(params.phi_true(q));
    v = sind(params.theta_true(q)) * sind(params.phi_true(q));

    a_tx = exp(1j * kw * (kron(ones(Nty,1), nx_vec) * u + kron(ny_vec, ones(Ntx,1)) * v));
    tx_eff_q = squeeze(sum(conj(a_tx) .* tx_flat, 1));
    tx_eff(:, :, q) = tx_eff_q;

    b_sel = exp(-1j * kw * ((selX-1) * u + (selY-1) * v));

    phase_r = exp(1j * (0:Ns-1).' * (-4*pi*delta_f*params.R_true(q) / params.c));
    phase_v = exp(1j * (0:L-1) * (4*pi*params.Ts*params.v_true(q)*params.fc / params.c));

    coeff(:, :, q) = params.alpha(q) * b_sel * (phase_r * phase_v);
end

txSum = squeeze(sum(sum(tx_signal, 1), 2));
txNorm = txSum ./ max(max(abs(txSum(:))), eps);

job = struct('tx_eff', tx_eff, 'coeff', coeff, ...
    'Ns', Ns, 'L', L, 'SNR_linear', 10^(params.SNR/10), 'num_targets', Q);
end

% =========================================================================
% 局部函数: 单 MC 仿真 + Output-SNR
% =========================================================================
function snrDb = local_mc_snr(seed, job, txNorm)
rng(seed);
rx = sum(job.tx_eff .* job.coeff, 3);
noise_std = sqrt(mean(abs(rx(:)).^2) / job.SNR_linear / 2);
rx = rx + noise_std * (randn(job.Ns, job.L) + 1j * randn(job.Ns, job.L));

rxEq = rx .* conj(txNorm);
rd = fft(rxEq, job.Ns, 1);
rd = fftshift(fft(rd, job.L, 2), 2);
powerMap = abs(rd).^2;

nPeaks = max(1, min(job.num_targets, numel(powerMap)));
[peakValues, peakIndex] = maxk(powerMap(:), nPeaks);
mask = false(size(powerMap));
guardR = 2; guardV = 2;
for k = 1:numel(peakIndex)
    [ir, iv] = ind2sub(size(powerMap), peakIndex(k));
    rIdx = max(1, ir - guardR):min(job.Ns, ir + guardR);
    vIdx = max(1, iv - guardV):min(job.L, iv + guardV);
    mask(rIdx, vIdx) = true;
end

background = powerMap(~mask);
noiseFloor = median(background(:), 'omitnan');
snrDb = 10 * log10(mean(peakValues, 'omitnan') / max(noiseFloor, eps));
end

% =========================================================================
% 局部函数: 出图（两条曲线）
% =========================================================================
function fig = create_output_snr_comparison_figure(x, y_mat, xLabelText, titleText, figIndex)
fig = figure('Color', 'w', 'Units', 'pixels', ...
    'Position', [100 + 35*figIndex, 140 + 35*figIndex, 560, 420], ...
    'Name', titleText);
ax = axes('Parent', fig);
hold(ax, 'on');

colors    = {[0.85 0.15 0.12], [0.00 0.45 0.74]};
markers   = {'o', 's'};
linestyles = {'-', '--'};
labels    = {'ZF', 'Null-space'};

for k = 1:2
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
