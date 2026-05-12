function result = SelfInterferenceChannel_LoS_NLoS_PlotPrep(cfg)
% SelfInterferenceChannel_LoS_NLoS_PlotPrep
% ========================================================================
% 目标
%   按《毫米波通感实时感知与预警算法方案》公式 (1)~(12) 严格搭建
%   "自干扰信号对雷达参数估计性能的影响" 仿真框架。
%
% 公式对应
%   (2)  x_i[l] = W_i s_i[l]  —— 本版取 W_i = a(phi,psi), s_i[l]=1 (恒模导频)
%   (4)  tilde{y}(t) 连续时间回波模型
%   (7)  y_i[l] = sum_q beta b(·) a^H(·) x_i[l] exp(j·i·omega_r) exp(j·l·omega_v) + z
%   (9)  omega_r(R_q) = -4π Δf R_q / c
%   (10) omega_v(v_q) = 4π T v_q fc / c
%   (11) y_i[l] = 回波 + sqrt(rho_SI) H_SI[i] x_i[l] + z_i[l]
%   (12) H_SI = sqrt(κ/(κ+1)) H_LoS + sqrt(1/(κ+1)) H_NLoS
%
% 参数估计流
%   1) MRC 合并 Nr 根接收天线
%   2) 2D-FFT (距离维 N, 多普勒维 L)
%   3) 峰值搜索 -> R_hat
%   4) MSE_R = E[(R_hat - R_true)^2]  (单位 m^2)
%
% 说明
%   - H_SI 保持 Nr×Nt 矩阵，使用真正的矩阵-向量乘法 (H_SI * a)
%   - 目标 R_true 刻意偏离 FFT 整数格点 (5.3·ΔR)，避免低 ρ 区 MSE=0
%   - 频率平坦 H_SI 下，自干扰主要落在 DC bin；随 ρ 增大，DC 峰抬升
%     超过目标峰时估计器阶跃跳变 → 呈现阈值效应
% ========================================================================

if nargin < 1 || isempty(cfg)
    cfg = struct();
end

% ----- 扫描参数 -----
cfg = local_set_default(cfg, 'rho_dB_range', -20:2:50);
cfg = local_set_default(cfg, 'snr_dB_list',  [-10 0 10]);
cfg = local_set_default(cfg, 'numMC',        500);
cfg = local_set_default(cfg, 'threshold_dB', 3);
cfg = local_set_default(cfg, 'seed',         1);
cfg = local_set_default(cfg, 'plotFlag',     true);
cfg = local_set_default(cfg, 'showWaitbar',  true);
cfg = local_set_default(cfg, 'saveIntermediate', false);

% ----- OFDM 系统参数 -----
cfg = local_set_default(cfg, 'c',  3e8);
cfg = local_set_default(cfg, 'fc', 28e9);
cfg = local_set_default(cfg, 'Df', 240e3);   % 子载波间隔
cfg = local_set_default(cfg, 'N',  64);      % 子载波数
cfg = local_set_default(cfg, 'L',  64);      % 快拍数
cfg = local_set_default(cfg, 'Nt', 4);
cfg = local_set_default(cfg, 'Nr', 4);

% ----- 目标参数 -----
cfg = local_set_default(cfg, 'beta',    1);
dR_ref = cfg.c / (2 * cfg.N * cfg.Df);
cfg = local_set_default(cfg, 'R_true',  5.3 * dR_ref);   % 刻意非格点
cfg = local_set_default(cfg, 'v_true',  0);

if ~isempty(cfg.seed)
    rng(cfg.seed);
end

% ----- 拆包常用变量 -----
c  = cfg.c;  fc = cfg.fc;  Df = cfg.Df;
N  = cfg.N;  L  = cfg.L;   Nt = cfg.Nt;  Nr = cfg.Nr;
T  = 1 / Df;
beta_t = cfg.beta;  R_true = cfg.R_true;  v_true = cfg.v_true;

rho_dB_range = cfg.rho_dB_range(:).';
snr_dB_list  = cfg.snr_dB_list(:).';
numRho = numel(rho_dB_range);
numSNR = numel(snr_dB_list);

% ----- 公式 (9)(10): 距离/多普勒相位 -----
omega_r = -4 * pi * Df * R_true / c;
omega_v =  4 * pi * T * v_true * fc / c;
phase_r = exp(1j * (0:N-1).' * omega_r);   % N×1
phase_v = exp(1j * (0:L-1)   * omega_v);   % 1×L

% ----- 空间导向矢量 (ULA 简化, phi=psi=0) -----
% a, b 归一化 ||a|| = ||b|| = 1
a = ones(Nt, 1) / sqrt(Nt);
b = ones(Nr, 1) / sqrt(Nr);

% ----- 公式(2): 发射端 x_i[l] = a * s_i[l], s 取恒模导频 1 -----
s_mat = ones(N, L);     % 导频 s_i[l] = 1

% ----- 公式(7): 回波模板 (不含 b 的空域权和噪声/干扰) -----
% 任意天线 k: y_k[i,l] = beta·b(k)·s·exp(j·i·ω_r)·exp(j·l·ω_v)
sensing_core = beta_t * (phase_r * phase_v) .* s_mat;   % N×L (公共部分)

% ----- 输出容器 -----
mse_avg          = zeros(numSNR, numRho);
threshold_rho_dB = nan(1, numSNR);
threshold_idx    = nan(1, numSNR);

% ----- 进度条 -----
useWaitbar = cfg.showWaitbar && usejava('jvm');
hWait = [];
if useWaitbar
    hWait = waitbar(0, '开始蒙特卡洛仿真...');
end
totalSteps = numSNR * numRho * cfg.numMC;
doneSteps  = 0;

% ========================================================================
% 蒙特卡洛主循环
% ========================================================================
for is = 1:numSNR
    snr_dB   = snr_dB_list(is);
    noiseVar = 10^(-snr_dB / 10);           % per-sample 噪声方差

    for ir = 1:numRho
        rho_dB = rho_dB_range(ir);
        rho_SI = 10^(rho_dB / 10);

        sq_err = zeros(cfg.numMC, 1);

        for imc = 1:cfg.numMC
            % ---- (12) 生成 H_SI: Nr×Nt 矩阵 (不拍平) ----
            Hsi = local_call_generate_HSI(Nt, Nr);

            % ---- (11) 自干扰项: sqrt(rho_SI) * H_SI * a * s_i[l] ----
            % 频率平坦假设: H_SI 与子载波 i 无关
            g = Hsi * a;                    % Nr×1
            % 各天线上的干扰: u_k[i,l] = sqrt(rho_SI)·g(k)·s_i[l]
            % 频率平坦 → 干扰对 i,l 都是常数 (因 s=1)

            % ---- (7) 感知回波: y_sig(k,i,l) = b(k) * sensing_core(i,l) ----
            % ---- 噪声: z_k[i,l] ~ CN(0, noiseVar) per antenna ----
            % ---- MRC 合并: y_comb = b^H * y_vec ----
            %
            % 合并后的各分量 (b^H b = 1, ||a||=||b||=1):
            %   signal_comb = b^H * b * sensing_core = sensing_core
            %   int_comb    = sqrt(rho_SI) * (b^H * g) * s_mat
            %   noise_comb  ~ CN(0, ||b||^2 * noiseVar) = CN(0, noiseVar)
            sig_comb   = sensing_core;
            int_comb   = sqrt(rho_SI) * (b' * g) * s_mat;      % 标量 × N×L
            noise_comb = sqrt(noiseVar/2) * ...
                         (randn(N, L) + 1j * randn(N, L));

            y_comb = sig_comb + int_comb + noise_comb;

            % ---- 导频匹配滤波 (|s|=1, 不改变统计) ----
            r = y_comb ./ s_mat;

            % ---- 2D-FFT: 距离维 (N) + 多普勒维 (L) ----
            R2D = fft2(r);                   % N×L
            P   = abs(R2D).^2;

            % ---- 峰值搜索 -> (n_peak, m_peak) ----
            [~, idx_peak]   = max(P(:));
            [n_peak, ~]     = ind2sub([N, L], idx_peak);
            n_idx           = n_peak - 1;    % 0-indexed FFT bin

            % ---- 频率索引 → 距离 ----
            % 公式(9): omega_r = -4π·Δf·R/c  (负号)
            % phase_r[i] = exp(j·i·omega_r) = exp(-j·2π·(2RΔf/c)·i)
            % 正距离 R 在 FFT 中对应 bin: k = N - 2N·Δf·R/c  (高频一侧)
            % 反解: range_bin = (N - n_idx) mod N, R_hat = range_bin·dR
            range_bin = mod(N - n_idx, N);
            % 允许"负距离"表示（干扰引起的 DC 峰 n_idx=0 会给 range_bin=0 → R_hat=0）
            if range_bin > N/2
                range_bin = range_bin - N;
            end
            R_hat = range_bin * c / (2 * N * Df);

            sq_err(imc) = (R_hat - R_true)^2;

            % 进度条刷新 (节流)
            doneSteps = doneSteps + 1;
            if useWaitbar && isvalid(hWait)
                step = max(1, floor(totalSteps / 200));
                if mod(doneSteps, step) == 0 || doneSteps == totalSteps
                    frac = doneSteps / totalSteps;
                    msg  = sprintf('SNR=%g dB | ρ=%g dB | MC=%d/%d | %.1f%%', ...
                        snr_dB, rho_dB, imc, cfg.numMC, 100 * frac);
                    waitbar(frac, hWait, msg);
                end
            end
        end

        mse_avg(is, ir) = mean(sq_err);
    end

    % --- 阈值点：相对低 ρ 基线抬升 >= threshold_dB ---
    baselineEnd = max(3, min(5, numRho));
    baseline    = mean(mse_avg(is, 1:baselineEnd));
    baseline    = max(baseline, eps);
    rise_dB = 10 * log10(max(mse_avg(is, :), eps) / baseline);
    idx_t   = find(rise_dB >= cfg.threshold_dB, 1, 'first');
    if ~isempty(idx_t)
        threshold_idx(is)    = idx_t;
        threshold_rho_dB(is) = rho_dB_range(idx_t);
    end

    if cfg.saveIntermediate
        intermediate = struct('mse_avg', mse_avg, ...
            'threshold_rho_dB', threshold_rho_dB, ...
            'threshold_idx',    threshold_idx, ...
            'rho_dB_range',     rho_dB_range, ...
            'snr_dB_list',      snr_dB_list);
        save('SelfInterferenceChannel_LoS_NLoS_PlotPrep_intermediate.mat', 'intermediate');
    end
end

if useWaitbar && isvalid(hWait)
    close(hWait);
end

% ========================================================================
% 绘图
% ========================================================================
if cfg.plotFlag
    figure('Color', 'w'); hold on; grid on; box on;
    colors = lines(numSNR);
    hLine  = gobjects(1, numSNR);
    for is = 1:numSNR
        mse_dB = 10 * log10(max(mse_avg(is, :), eps));
        hLine(is) = plot(rho_dB_range, mse_dB, 'LineWidth', 2, ...
            'Color', colors(is, :), ...
            'DisplayName', sprintf('SNR = %g dB', snr_dB_list(is)));

        if ~isnan(threshold_rho_dB(is))
            idx_t = threshold_idx(is);
            plot(threshold_rho_dB(is), mse_dB(idx_t), 'o', ...
                'MarkerSize', 8, 'LineWidth', 1.5, ...
                'Color', colors(is, :), 'MarkerFaceColor', colors(is, :), ...
                'HandleVisibility', 'off');
            text(threshold_rho_dB(is), mse_dB(idx_t), ...
                sprintf('  \\rho_{th}=%.1f dB', threshold_rho_dB(is)), ...
                'Color', colors(is, :), 'FontSize', 10, ...
                'VerticalAlignment', 'bottom');
        end
    end
    xlabel('\rho_{SI} (dB)');
    ylabel('MSE of R (dB, m^2)');
    title('Effect of Self-Interference on Range Estimation Performance');
    legend(hLine, 'Location', 'northwest');
    set(gca, 'FontSize', 11, 'LineWidth', 1.2);
end

% ========================================================================
% 输出
% ========================================================================
result = struct();
result.rho_dB_range     = rho_dB_range;
result.snr_dB_list      = snr_dB_list;
result.mse_avg          = mse_avg;
result.mse_avg_dB       = 10 * log10(max(mse_avg, eps));
result.threshold_rho_dB = threshold_rho_dB;
result.threshold_idx    = threshold_idx;
result.cfg              = cfg;

end

% ========================================================================
% H_SI 调用封装：优先使用工作区同名函数，否则调用本地 fallback
% ========================================================================
function Hsi = local_call_generate_HSI(Nt, Nr)
if exist('generate_HSI', 'file') == 2
    Hsi = generate_HSI();
    % 若外部函数返回列向量 (老接口)，尝试 reshape 回矩阵
    if isvector(Hsi) && numel(Hsi) == Nt * Nr
        Hsi = reshape(Hsi, Nr, Nt);
    end
else
    Hsi = local_generate_HSI_fallback(Nt, Nr);
end
Hsi = double(Hsi);
end

% ========================================================================
% fallback: 公式 (12) Rician 自干扰信道
% ========================================================================
function Hsi = local_generate_HSI_fallback(Nt, Nr)
Ncl       = 4;
Nray      = 10;
std_phi   = 0.1;
std_theta = 0.1;
Pr        = 1;
kappa_SI  = 10;
d         = 1;
an        = pi / 6;

% --- LoS 部分：简化几何 ---
dots = d / tan(an);
dos  = d / sin(an);
Rmat = zeros(Nr, Nt);
for row = 1:Nr
    for col = 1:Nt
        Rmat(row, col) = sqrt( ...
            (dots + (col - 1) / 2)^2 + ...
            (dos  + (row - 1) / 2)^2 - ...
            2 * (dots + (col - 1) / 2) * ...
                (dos  + (row - 1) / 2) * cos(an));
    end
end
Hlos = exp(-1j * 2 * pi * Rmat) ./ Rmat;
Hlos = Hlos * sqrt(Nt * Nr / trace(Hlos * Hlos'));     % ||Hlos||_F^2 = Nt·Nr

% --- NLoS 部分：Sayeed 虚信道 ---
Hnlos = local_gen_channel_fallback(Ncl, Nray, std_phi, std_theta, Pr, Nt, Nr);
% local_gen_channel_fallback 内部已归一化为 ||H||_F^2 = Nt·Nr

% --- 公式 (12) 合成 (不再二次归一化，保持 Rician κ 的功率含义) ---
Hsi = sqrt(kappa_SI / (kappa_SI + 1)) * Hlos + ...
      sqrt(1        / (kappa_SI + 1)) * Hnlos;
end

function H = local_gen_channel_fallback(Ncl, Nray, std_phi, std_theta, Pr, Nt, Nr)
Ltot       = Ncl * Nray;
phi_cl     = sin(2 * pi * rand(Ncl, 1));
theta_cl   = sin(2 * pi * rand(Ncl, 1));
phi_mat    = repmat(phi_cl,   [1 Nray]) + std_phi   * randn(Ncl, Nray);
theta_mat  = repmat(theta_cl, [1 Nray]) + std_theta * randn(Ncl, Nray);
epsilon    = (0:Nt-1).';
zeta       = (0:Nr-1).';

phi_vec    = phi_mat(:);
theta_vec  = theta_mat(:);
At = exp(1j * pi * (epsilon * phi_vec.'))   / sqrt(Nt);     % Nt × Ltot
Ar = exp(1j * pi * (zeta    * theta_vec.')) / sqrt(Nr);     % Nr × Ltot

alpha = (sqrt(Pr) / 2) * (randn(Ncl, Nray) + 1j * randn(Ncl, Nray));
alpha = alpha(:);
[~, I] = sort(abs(alpha), 'descend');
alpha  = alpha(I);

H = Ar(:, I) * diag(alpha) * At(:, I)';
H = H * sqrt(Nt * Nr / (norm(H, 'fro')^2));
end

% ========================================================================
% 工具函数
% ========================================================================
function s = local_set_default(s, field, value)
if ~isfield(s, field) || isempty(s.(field))
    s.(field) = value;
end
end
