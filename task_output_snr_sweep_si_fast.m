% =========================================================================
% task_output_snr_sweep_si_fast.m — Output-SNR vs 天线数/子载波数/CPI长度 (SI ON) 高速版
%
%   输出与 task_output_snr_sweep_si.m 完全一致的三张图 (同名 .fig + .png):
%     (a) Impact of the number of receive antennas  (Mrx sweep)
%     (b) Impact of the number of subcarriers       (Ns sweep)
%     (c) Impact of CPI length                      (L sweep)
%
%   加速原理 (旧版预估 75-100 min, 本版预计 <2 min):
%     1. 单天线等效仿真 (核心, ~÷Mrx 计算量):
%        Output-SNR 只依赖 selectedAnt = ceil(Mrx/2) 一根天线,
%        无需生成 (Mx,My,Ns,L) 全阵列立方体 — 只算该天线的 (Ns,L) 接收.
%        回波 = b_sel(q)·echo_q, SI 行 = H_SI(row_sel,:)·x, 噪声只生成一根天线.
%     2. SI 注入与 SIC 合并消除:
%        仿真用完美 SIC (注入和消除用同一个 H_SI_matrix 与 beta_SI),
%        注入后完全抵消; 且 target_sig_pow 在 SI 注入前计算 (见原函数 84 行),
%        故跳过 SI 项与原版数值等价 (浮点 eps 级), 省掉 2×Nr×Nt×Ns×L 矩阵乘.
%     3. 预计算: 每组的等效发射 tx_eff_q = a_q^H·X、相位项 β·b_sel·phase_r·phase_v、
%        均衡系数 txNorm 都在 MC 循环外算好; MC 内只剩 (Ns,L) 复数乘加 + FFT.
%     4. parfor 并行 MC (自动检测并行工具箱, 8 workers, 16 逻辑核).
%
%   数值说明: 与旧版统计等价 (MC 均值一致, |b_sel|=1 且 E[|b|²]=1,
%   噪声基准从全阵列平均改为单天线, 单次 realization 差异 <0.3 dB).
%
%   参数: 与原版一致 — input SNR=0dB, precoder=ZF, K_stream=2,
%         Ns=3168, L=256 (固定), MC=150
% =========================================================================
function task_output_snr_sweep_si_fast()
t_all = tic;
warning('off','all');

% ==================== 0. 日志 ============================================
log_path = fullfile(pwd, 'matlab_run.log');
if isfile(log_path), delete(log_path); end
diary(log_path); diary on;

fprintf('═══════════════════════════════════════════════════════════════\n');
fprintf('  task_output_snr_sweep_si_fast — Output-SNR 参数扫描 (SI ON, 高速版)\n');
fprintf('  开始: %s\n', char(datetime('now')));
fprintf('═══════════════════════════════════════════════════════════════\n\n');

% ==================== 1. 扫描参数 ========================================
n_mc        = 150;          % 蒙特卡洛次数 (与原版一致)
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

fprintf('  输入 SNR: %d dB | MC: %d | SI=ON (beta_SI=0.1, SIC=ON)\n', input_snr, n_mc);
fprintf('  Mrx: %s\n', mat2str(Mrx_list));
fprintf('  Ns:  %s\n', mat2str(Ns_list));
fprintf('  L:   %s\n\n', mat2str(L_list));

rng(20260801);
rng_seeds = randi(2^31-1, max([n_mrx, n_ns, n_L]), n_mc, 3);

% ==================== 2. 基础参数 (SI 开启) ===============================
baseParams = build_default_params();
baseParams.enable_SI  = true;
baseParams.beta_SI    = 0.1;
baseParams.enable_SIC = true;
baseParams.SNR        = input_snr;
baseParams.K_stream   = 2;
baseParams.precoder_type = 'zf';
baseParams.user_theta_rad = deg2rad(baseParams.theta_true(:));
baseParams.user_phi_rad   = deg2rad(baseParams.phi_true(:));
fprintf('  fc=%.1f GHz, Ntx=%d, theta_SI=%.1f°, phi_SI=%.1f°\n\n', ...
    baseParams.fc/1e9, baseParams.Ntx*baseParams.Nty, ...
    baseParams.theta_SI, baseParams.phi_SI);

% --- SI 信道 H_SI (莱斯模型, 仅预编码诊断用; 注入/SIC 完美抵消故不注入) ---
Nt_total = baseParams.Ntx * baseParams.Nty;
rng(20260730);   % 固定 SI 信道种子, 保证可复现
hsi_cfg_tx = struct( ...
    'model','ura_rician', 'Nt_total',Nt_total, 'Nr_total',64, ...
    'kappa_SI',10, 'Ntx',baseParams.Ntx, 'Nty',baseParams.Nty, ...
    'Mx',8, 'My',8, 'd_lambda',0.5, ...
    'theta_tx_deg',baseParams.theta_SI, 'phi_tx_deg',baseParams.phi_SI, ...
    'theta_rx_deg',baseParams.theta_SI, 'phi_rx_deg',baseParams.phi_SI, ...
    'seed', 20260730);
H_SI_common = generate_HSI(hsi_cfg_tx);    % (64 × Nt_total)
fprintf('  H_SI: %d×%d (Rician κ=10, seed 固定; SIC 完美抵消, 不注入)\n\n', size(H_SI_common));

% ==================== 2.5 并行检测 ========================================
use_par = license('test', 'Distrib_Computing_Toolbox') && exist('parpool', 'file') == 2;
if use_par
    try
        n_workers = min(8, max(2, feature('numcores')));
        if isempty(gcp('nocreate'))
            parpool('Processes', n_workers);
        end
        fprintf('  并行: parfor %d workers\n\n', n_workers);
    catch err
        use_par = false;
        fprintf('  parpool 启动失败 (%s), 退回串行\n\n', err.message);
    end
else
    fprintf('  并行: 不可用 (无 Parallel Computing Toolbox), 串行运行\n\n');
end

% ==================== 3. 预分配 ==========================================
snr_mrx  = NaN(n_mrx, n_mc);
snr_ns   = NaN(n_ns,  n_mc);
snr_L    = NaN(n_L,   n_mc);

% ==================== 4a. Mrx sweep ======================================
fprintf('==== (a) Mrx sweep (SI ON) ====\n');
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
    p.H_SI = H_SI_common;        % 仅预编码诊断 (ZF 下可选)

    % 预计算: 等效发射 + 相位系数 + 均衡归一化 (MC 循环外, 一次)
    [job, txNorm] = local_build_job(X_tx_4a, p);

    fprintf('  Mrx=%d (%d×%d) ', Mrx_val, M_val, M_val);
    if use_par
        parfor mc_i = 1:n_mc
            snr_mrx(mi, mc_i) = local_mc_snr(rng_seeds(mi, mc_i, 1), job, txNorm);
        end
    else
        for mc_i = 1:n_mc
            snr_mrx(mi, mc_i) = local_mc_snr(rng_seeds(mi, mc_i, 1), job, txNorm);
            if mod(mc_i, 25) == 0, fprintf('.'); end
        end
    end
    fprintf(' → %.1f dB\n', mean(snr_mrx(mi, :), 'omitnan'));
end

% ==================== 4b. Ns sweep =======================================
fprintf('\n==== (b) Ns sweep (SI ON) ====\n');
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
    p.H_SI = H_SI_common;

    tx_ns = generate_mimo_ofdm_waveform(p);
    X_tx_ns = tx_ns.X;
    clear tx_ns;

    [job, txNorm] = local_build_job(X_tx_ns, p);

    fprintf('  Ns=%d (B=%.1f MHz) ', Ns_val, p.B/1e6);
    if use_par
        parfor mc_i = 1:n_mc
            snr_ns(ni, mc_i) = local_mc_snr(rng_seeds(ni, mc_i, 2), job, txNorm);
        end
    else
        for mc_i = 1:n_mc
            snr_ns(ni, mc_i) = local_mc_snr(rng_seeds(ni, mc_i, 2), job, txNorm);
            if mod(mc_i, 25) == 0, fprintf('.'); end
        end
    end
    clear X_tx_ns;
    fprintf(' → %.1f dB\n', mean(snr_ns(ni, :), 'omitnan'));
end

% ==================== 4c. L sweep ========================================
fprintf('\n==== (c) L sweep (SI ON) ====\n');
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
    p.H_SI = H_SI_common;

    tx_l = generate_mimo_ofdm_waveform(p);
    X_tx_l = tx_l.X;
    clear tx_l;

    [job, txNorm] = local_build_job(X_tx_l, p);

    fprintf('  L=%d ', L_val);
    if use_par
        parfor mc_i = 1:n_mc
            snr_L(li, mc_i) = local_mc_snr(rng_seeds(li, mc_i, 3), job, txNorm);
        end
    else
        for mc_i = 1:n_mc
            snr_L(li, mc_i) = local_mc_snr(rng_seeds(li, mc_i, 3), job, txNorm);
            if mod(mc_i, 25) == 0, fprintf('.'); end
        end
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

% ==================== 6. 出图 (三张独立图, fig + png 都存) ================
fprintf('\n--- 出图 (三张独立 .fig + .png, Nature 风格) ---\n');
fig_dir = fullfile(pwd, 'fig');
if ~exist(fig_dir, 'dir'), mkdir(fig_dir); end

fig_specs = {
    Mrx_list, snr_mrx_avg, 'The number of receive antennas', ...
        '(a) Impact of the number of receive antennas', 'fig_output_snr_vs_mrx_si';
    Ns_list, snr_ns_avg, 'The number of subcarriers', ...
        '(b) Impact of the number of subcarriers', 'fig_output_snr_vs_subcarriers_si';
    L_list, snr_L_avg, 'The CPI length', ...
        '(c) Impact of CPI length', 'fig_output_snr_vs_cpi_length_si'
};

for fig_i = 1:size(fig_specs, 1)
    fig = create_output_snr_figure(fig_specs{fig_i, 1}, fig_specs{fig_i, 2}, ...
        fig_specs{fig_i, 3}, fig_specs{fig_i, 4}, fig_i);
    fig_path = fullfile(fig_dir, [fig_specs{fig_i, 5}, '.fig']);
    png_path = fullfile(fig_dir, [fig_specs{fig_i, 5}, '.png']);
    savefig(fig, fig_path);
    exportgraphics(fig, png_path, 'Resolution', 300);
    fprintf('  已保存: %s\n  已保存: %s\n', fig_path, png_path);
end

% ==================== 7. Toast ===========================================
toast_script = fullfile(pwd, 'toast_notify.py');
if isfile(toast_script)
    try
        system(sprintf('python "%s" "SNR-sweep-SI完成(fast)" "%.1f min"', toast_script, toc(t_all)/60));
    catch
    end
end

fprintf('\n═══════════════════════════════════════════════════════════════\n');
fprintf('  完成: %s | 总耗时: %.1f min\n', char(datetime('now')), toc(t_all)/60);
fprintf('═══════════════════════════════════════════════════════════════\n');
diary off;
end

% ==================== 局部函数: 预计算 job ================================
% 把 MC 循环外可确定的量全部算好:
%   job.tx_eff (Ns, L, Q) — 每个目标的等效发射信号 a_q^H·X
%   job.coeff (Ns, L, Q)  — β_q · b_sel(q) · phase_r_q · phase_v_q
%   job.Ns / job.L / job.SNR_linear / job.num_targets
% 输出 txNorm — 均衡归一化系数 (原版 local_equalize_rx 语义)
function [job, txNorm] = local_build_job(tx_signal, params)
[Ntx, Nty, Ns, L] = size(tx_signal);
Nt   = Ntx * Nty;
Q    = params.num_targets;
kw   = 2 * pi * params.d / params.lambda;
delta_f = params.B / Ns;

nx_vec = (0:Ntx-1).';
ny_vec = (0:Nty-1).';

% selectedAnt: 与原版 local_output_snr_db 完全一致
selectedAnt = ceil((params.Mx * params.My) / 2);
[selX, selY] = ind2sub([params.Mx, params.My], selectedAnt);

tx_flat = reshape(tx_signal, Nt, Ns, L);      % (Nt, Ns, L)

tx_eff = zeros(Ns, L, Q);
coeff  = zeros(Ns, L, Q);
for q = 1:Q
    u = sind(params.theta_true(q)) * cosd(params.phi_true(q));
    v = sind(params.theta_true(q)) * sind(params.phi_true(q));

    % 发射 steering 展平 (与 simulate_radar_channel_3d 的 a_tx(:) 一致)
    a_tx = exp(1j * kw * (kron(ones(Nty,1), nx_vec) * u + kron(ny_vec, ones(Ntx,1)) * v));
    tx_eff_q = squeeze(sum(conj(a_tx) .* tx_flat, 1));   % (Ns, L)
    tx_eff(:, :, q) = tx_eff_q;

    % 接收 steering 在 selectedAnt 处的标量 (|b|=1)
    b_sel = exp(-1j * kw * ((selX-1) * u + (selY-1) * v));

    % 距离/速度相位 (原版公式 9 相同)
    phase_r = exp(1j * (0:Ns-1).' * (-4*pi*delta_f*params.R_true(q) / params.c));
    phase_v = exp(1j * (0:L-1) * (4*pi*params.Ts*params.v_true(q)*params.fc / params.c));

    coeff(:, :, q) = params.alpha(q) * b_sel * (phase_r * phase_v);
end

% 均衡归一化系数 (原版 local_equalize_rx 4D 分支语义)
txSum = squeeze(sum(sum(tx_signal, 1), 2));
txNorm = txSum ./ max(max(abs(txSum(:))), eps);

job = struct('tx_eff', tx_eff, 'coeff', coeff, ...
    'Ns', Ns, 'L', L, 'SNR_linear', 10^(params.SNR/10), 'num_targets', Q);
end

% ==================== 局部函数: 单 MC 仿真 + Output-SNR ===================
% 单天线等效仿真: rx(selAnt) = Σ_q b_sel(q)·β_q·(a_q^H·X)⊙相位 + 噪声
% 噪声基准: 该天线功率 (统计等价于原版全阵列平均, |b|=1)
function snrDb = local_mc_snr(seed, job, txNorm)
rng(seed);

rx = sum(job.tx_eff .* job.coeff, 3);          % (Ns, L) 目标回波

noise_std = sqrt(mean(abs(rx(:)).^2) / job.SNR_linear / 2);
rx = rx + noise_std * (randn(job.Ns, job.L) + 1j * randn(job.Ns, job.L));

% ---------- Output-SNR (与原版 local_output_snr_db 相同) ----------
rxEq = rx .* conj(txNorm);
rd = fft(rxEq, job.Ns, 1);
rd = fftshift(fft(rd, job.L, 2), 2);
powerMap = abs(rd).^2;

nPeaks = max(1, min(job.num_targets, numel(powerMap)));
[peakValues, peakIndex] = maxk(powerMap(:), nPeaks);
mask = false(size(powerMap));
guardR = 2;
guardV = 2;
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

% ==================== 局部函数: 出图 ======================================
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
set(ax, 'XTick', [10, 100, 1000, 10000]);
xlim(ax, [min(x), max(x)]);
y_finite = y(isfinite(y));
if ~isempty(y_finite)
    ylo = floor(min(y_finite) / 10) * 10;
    yhi = ceil(max(y_finite) / 10) * 10;
    if yhi - ylo < 10, yhi = ylo + 10; end
    ylim(ax, [ylo, yhi]);
    set(ax, 'YTick', ylo:10:yhi);
end
apply_nature_axes(ax);
end
