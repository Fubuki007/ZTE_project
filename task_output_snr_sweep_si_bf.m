% =========================================================================
% task_output_snr_sweep_si_bf.m — Output-SNR 扫描 SI-ON 接收波束成形版
%
%   与 task_output_snr_sweep_si_fast.m 输出同三张图, 但 Output-SNR 定义升级:
%     单天线版: 只用 selectedAnt 一根天线 → Mrx 曲线平坦 (无阵列增益)
%     本版:     对每个目标方向做接收匹配滤波 b_q^H·r (全阵列相干合成,
%               等价于估计器实际的空间求和) → 输出 SNR 随 Mrx 增长
%               ~10·log10(Mrx) dB (阵列增益)
%
%   数学: 回波 r = Σ_q b_q ⊗ echo_q (b_q 单位模 steering),
%         b_q^H·r = Σ_p (b_q^H b_p)·echo_p = Σ_p c_qp·echo_p
%         噪声: b_q^H·z 方差 = Mrx·σ²  (i.i.d. 天线噪声相干合成)
%         交叉项 c_qp = b_q^H b_p (解析可算, 两目标角度分离大时 ≈ 0)
%
%   加速手段与 fast 版相同: 预计算 + 单 MC 向量化 + parfor 8 workers
%   SI: 完美 SIC 抵消, 跳过 (与 fast 版相同的数值论证)
%
%   输出: fig/fig_output_snr_vs_mrx_si_bf.fig/.png 等 (不覆盖单天线版)
% =========================================================================
function task_output_snr_sweep_si_bf()
t_all = tic;
warning('off','all');

% ==================== 0. 日志 ============================================
log_path = fullfile(pwd, 'matlab_run.log');
if isfile(log_path), delete(log_path); end
diary(log_path); diary on;

fprintf('═══════════════════════════════════════════════════════════════\n');
fprintf('  task_output_snr_sweep_si_bf — Output-SNR 扫描 (SI ON, 波束成形版)\n');
fprintf('  开始: %s\n', char(datetime('now')));
fprintf('═══════════════════════════════════════════════════════════════\n\n');

% ==================== 1. 扫描参数 ========================================
n_mc        = 150;
input_snr   = 0;

M_list    = [2, 4, 6, 8];
Mrx_list  = M_list.^2;
n_mrx     = numel(Mrx_list);

Ns_list   = [512, 1024, 2048, 3168, 6336];
n_ns      = numel(Ns_list);

L_list    = [16, 32, 64, 128, 256];
n_L       = numel(L_list);

fprintf('  输入 SNR: %d dB | MC: %d | SI=ON (beta_SI=0.1, SIC=ON)\n', input_snr, n_mc);
fprintf('  Mrx: %s\n', mat2str(Mrx_list));
fprintf('  Ns:  %s\n', mat2str(Ns_list));
fprintf('  L:   %s\n\n', mat2str(L_list));

rng(20260801);
rng_seeds = randi(2^31-1, max([n_mrx, n_ns, n_L]), n_mc, 3);

% ==================== 2. 基础参数 ========================================
baseParams = build_default_params();
baseParams.enable_SI  = true;
baseParams.beta_SI    = 0.1;
baseParams.enable_SIC = true;
baseParams.SNR        = input_snr;
baseParams.K_stream   = 2;
baseParams.precoder_type = 'zf';
baseParams.user_theta_rad = deg2rad(baseParams.theta_true(:));
baseParams.user_phi_rad   = deg2rad(baseParams.phi_true(:));
fprintf('  fc=%.1f GHz, Ntx=%d\n\n', baseParams.fc/1e9, baseParams.Ntx*baseParams.Nty);

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
        fprintf('  并行: 启动失败, 退回串行\n\n');
    end
else
    fprintf('  并行: 不可用, 串行运行\n\n');
end

% ==================== 3. 预分配 ==========================================
snr_mrx  = NaN(n_mrx, n_mc);
snr_ns   = NaN(n_ns,  n_mc);
snr_L    = NaN(n_L,   n_mc);

% ==================== 4a. Mrx sweep ======================================
fprintf('==== (a) Mrx sweep (SI ON, 波束成形) ====\n');
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

    [job, txNorm] = local_build_job_bf(X_tx_4a, p);

    fprintf('  Mrx=%d (%d×%d) ', Mrx_val, M_val, M_val);
    if use_par
        parfor mc_i = 1:n_mc
            snr_mrx(mi, mc_i) = local_mc_snr_bf(rng_seeds(mi, mc_i, 1), job, txNorm);
        end
    else
        for mc_i = 1:n_mc
            snr_mrx(mi, mc_i) = local_mc_snr_bf(rng_seeds(mi, mc_i, 1), job, txNorm);
            if mod(mc_i, 25) == 0, fprintf('.'); end
        end
    end
    fprintf(' → %.1f dB\n', mean(snr_mrx(mi, :), 'omitnan'));
end

% ==================== 4b. Ns sweep =======================================
fprintf('\n==== (b) Ns sweep (SI ON, 波束成形) ====\n');
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

    [job, txNorm] = local_build_job_bf(X_tx_ns, p);

    fprintf('  Ns=%d (B=%.1f MHz) ', Ns_val, p.B/1e6);
    if use_par
        parfor mc_i = 1:n_mc
            snr_ns(ni, mc_i) = local_mc_snr_bf(rng_seeds(ni, mc_i, 2), job, txNorm);
        end
    else
        for mc_i = 1:n_mc
            snr_ns(ni, mc_i) = local_mc_snr_bf(rng_seeds(ni, mc_i, 2), job, txNorm);
            if mod(mc_i, 25) == 0, fprintf('.'); end
        end
    end
    clear X_tx_ns;
    fprintf(' → %.1f dB\n', mean(snr_ns(ni, :), 'omitnan'));
end

% ==================== 4c. L sweep ========================================
fprintf('\n==== (c) L sweep (SI ON, 波束成形) ====\n');
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

    [job, txNorm] = local_build_job_bf(X_tx_l, p);

    fprintf('  L=%d ', L_val);
    if use_par
        parfor mc_i = 1:n_mc
            snr_L(li, mc_i) = local_mc_snr_bf(rng_seeds(li, mc_i, 3), job, txNorm);
        end
    else
        for mc_i = 1:n_mc
            snr_L(li, mc_i) = local_mc_snr_bf(rng_seeds(li, mc_i, 3), job, txNorm);
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

% ==================== 6. 出图 ============================================
fprintf('\n--- 出图 (三张独立 .fig + .png, Nature 风格, _bf 后缀) ---\n');
fig_dir = fullfile(pwd, 'fig');
if ~exist(fig_dir, 'dir'), mkdir(fig_dir); end

fig_specs = {
    Mrx_list, snr_mrx_avg, 'The number of receive antennas', ...
        '(a) Impact of the number of receive antennas (beamforming)', 'fig_output_snr_vs_mrx_si_bf';
    Ns_list, snr_ns_avg, 'The number of subcarriers', ...
        '(b) Impact of the number of subcarriers (beamforming)', 'fig_output_snr_vs_subcarriers_si_bf';
    L_list, snr_L_avg, 'The CPI length', ...
        '(c) Impact of CPI length (beamforming)', 'fig_output_snr_vs_cpi_length_si_bf'
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
        system(sprintf('python "%s" "SNR-sweep-SI完成(bf)" "%.1f min"', toast_script, toc(t_all)/60));
    catch
    end
end

fprintf('\n═══════════════════════════════════════════════════════════════\n');
fprintf('  完成: %s | 总耗时: %.1f min\n', char(datetime('now')), toc(t_all)/60);
fprintf('═══════════════════════════════════════════════════════════════\n');
diary off;
end

% ==================== 局部函数: 预计算 (波束成形版) =======================
% job.echo    (Ns, L, Q)  — β_q·tx_eff_q·phase_r·phase_v (单天线回波)
% job.tx_eff  (Ns, L, Q)  — 每目标发射有效照射 a_q^H·X (理想匹配滤波用)
% job.C       (Q, Q)      — 接收 steering 互相关 c_qp = b_q^H·b_p
% job.noise_std            — 单天线噪声 std (由全阵列回波功率归一)
% job.Mrx                  — 接收天线总数 (噪声相干合成 √Mrx)
%
% 均衡方式: 每目标用 conj(tx_eff_q) 做匹配滤波 (而非 txSum 近似),
%   消除均衡残余调制泄漏 → 背景纯噪声 → 输出 SNR 严格 ∝ Mrx (阵列增益)
function [job, txNorm] = local_build_job_bf(tx_signal, params)
[Ntx, Nty, Ns, L] = size(tx_signal);
Nt   = Ntx * Nty;
Q    = params.num_targets;
Mrx  = params.Mx * params.My;
kw   = 2 * pi * params.d / params.lambda;
delta_f = params.B / Ns;

nx_vec = (0:Ntx-1).';
ny_vec = (0:Nty-1).';

tx_flat = reshape(tx_signal, Nt, Ns, L);      % (Nt, Ns, L)

% 接收 steering 矩阵 B (Mx·My, Q)
B = zeros(Mrx, Q);
echo = zeros(Ns, L, Q);
tx_eff = zeros(Ns, L, Q);
mx = (0:params.Mx-1).';
my = (0:params.My-1).';
for q = 1:Q
    u = sind(params.theta_true(q)) * cosd(params.phi_true(q));
    v = sind(params.theta_true(q)) * sind(params.phi_true(q));
    bx = exp(-1j * kw * mx * u);
    by = exp(-1j * kw * my * v);
    Bmat_q = bx * by.';                % (Mx, My)
    B(:, q) = Bmat_q(:);               % 列主序展平, 与原 simulate b_vec(:) 一致

    % 发射 steering (与 simulate 的 a_tx(:) 一致)
    a_tx = exp(1j * kw * (kron(ones(Nty,1), nx_vec) * u + kron(ny_vec, ones(Ntx,1)) * v));
    tx_eff_q = squeeze(sum(conj(a_tx) .* tx_flat, 1));   % (Ns, L)
    tx_eff(:, :, q) = tx_eff_q;

    phase_r = exp(1j * (0:Ns-1).' * (-4*pi*delta_f*params.R_true(q) / params.c));
    phase_v = exp(1j * (0:L-1) * (4*pi*params.Ts*params.v_true(q)*params.fc / params.c));
    % 回波 = β_q · tx_eff_q · phase (含发射有效照射, 匹配滤波后相干积累)
    echo(:, :, q) = params.alpha(q) * tx_eff_q .* (phase_r * phase_v);
end

% 接收 steering 互相关 C = B^H·B (Q×Q), c_qq = Mrx
C = B' * B;

% 全阵列回波功率 (解析): rxCube = B·E' (E: NsL×Q), target_sig_pow = ||B·E'||_F²/(Mrx·Ns·L)
E = reshape(echo, Ns*L, Q);                    % (NsL, Q)
G = E' * E;                                    % (Q, Q)
target_sig_pow = trace(B * G * B') / (Mrx * Ns * L);

fprintf('    [BF] C 矩阵(对角=Mrx=%d), 串扰比 |c_12|²/Mrx²=%.1f dB\n', ...
    Mrx, 10*log10(abs(C(1,2))^2 / Mrx^2 + eps));

% 均衡归一化系数
txSum = squeeze(sum(sum(tx_signal, 1), 2));
txNorm = txSum ./ max(max(abs(txSum(:))), eps);

job = struct('echo', echo, 'tx_eff', tx_eff, 'C', C, 'Mrx', Mrx, ...
    'Ns', Ns, 'L', L, ...
    'noise_std', sqrt(target_sig_pow / 10^(params.SNR/10) / 2), ...
    'zf_delta', 1e-4 * mean(abs(tx_eff(:)).^2), ...
    'num_targets', Q);
end

% ==================== 局部函数: 单 MC 波束成形 + Output-SNR ===============
% 接收链: 波束成形 b_q^H·r (阵列增益 √Mrx) → ZF 去调制均衡
%         (conj(tx_eff_q)/|tx_eff_q|², 消除调制自噪声)
%         → 2D FFT (距离/多普勒相干积累) → 峰均比
% 均衡后信号为纯相位斜坡 → 零自噪声 → 输出 SNR 严格 ∝ Mrx (阵列增益)
function snrDb = local_mc_snr_bf(seed, job, txNorm)
rng(seed);

% 波束成形输出: R (NsL, Q), R(:,q) = Σ_p c_qp·echo_p
E = reshape(job.echo, job.Ns*job.L, job.num_targets);
R = E * job.C.';                               % (NsL, Q)

% 噪声: b_q^H·z 方差 = Mrx·σ² (各 q 独立近似, 角度分离大时串扰可忽略)
noise_amp = sqrt(job.Mrx) * job.noise_std;
R = R + noise_amp * (randn(job.Ns*job.L, job.num_targets) + ...
                     1j * randn(job.Ns*job.L, job.num_targets));

% 每个波束方向: ZF 去调制 + RD 图, 合并取峰
powerMapAll = zeros(job.Ns, job.L, job.num_targets);
for q = 1:job.num_targets
    rx_bf = reshape(R(:, q), job.Ns, job.L);
    te = job.tx_eff(:, :, q);
    w_zf = conj(te) ./ (abs(te).^2 + job.zf_delta);   % ZF 均衡系数
    rxEq = rx_bf .* w_zf;
    rd = fft(rxEq, job.Ns, 1);
    rd = fftshift(fft(rd, job.L, 2), 2);
    powerMapAll(:, :, q) = abs(rd).^2;
end

nPeaks = max(1, min(job.num_targets, numel(powerMapAll)));
[peakValues, peakIndex] = maxk(powerMapAll(:), nPeaks);
mask = false(size(powerMapAll));
guardR = 2; guardV = 2;
for k = 1:numel(peakIndex)
    [ir, iv, iq] = ind2sub(size(powerMapAll), peakIndex(k));
    mask(max(1, ir - guardR):min(job.Ns, ir + guardR), ...
         max(1, iv - guardV):min(job.L, iv + guardV), iq) = true;
end

background = powerMapAll(~mask);
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
