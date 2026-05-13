% =========================================================================
% run_si_mse_analysis.m  自干扰对参数估计性能影响的仿真分析
% -------------------------------------------------------------------------
% 功能:
%   1. 信道建模: 调用 generate_HSI() 生成 LoS+NLoS 自干扰信道 H_SI
%   2. 信号建模: 发射信号 x = a (导向矢量), 回波 y = beta*b*a^H*x*phase
%      干扰项 = sqrt(rho) * H_SI * x, rho 从 -20dB 到 50dB
%   3. 数据叠加: y_new = y + interference + noise
%   4. 性能评估: 2D-FFT 峰值搜索估计距离, 计算 MSE
%   5. 蒙特卡洛: 每个 (rho, SNR) 点跑 numMC 次取平均
%   6. 参数扫描: SNR = [-10, 0, 10] dB, rho = -20:2:50 dB
%   7. 绘图: MSE(dB) vs rho(dB), 标记阈值点
%
% 依赖:
%   generate_HSI.m (若不存在则使用内置 Rician 信道模型)
%   SelfInterferenceChannel_LoS_NLoS_PlotPrep.m (可选, 本脚本自包含)
% =========================================================================
clear; close all; clc;
fprintf('=================================================\n');
fprintf('  自干扰对雷达参数估计性能影响分析\n');
fprintf('=================================================\n');

%% ===== 仿真参数配置 =====
% OFDM 系统参数
c  = 3e8;           % 光速 (m/s)
fc = 28e9;          % 载波频率 (Hz)
Df = 240e3;         % 子载波间隔 (Hz)
N  = 64;            % 子载波数
L  = 64;            % OFDM 符号数 (快拍数)
Nt = 4;             % 发射天线数
Nr = 4;             % 接收天线数
T  = 1 / Df;        % OFDM 符号周期 (s)

% 目标参数
beta_target = 1;                        % 目标复反射系数幅度
dR = c / (2 * N * Df);                  % 距离分辨率
R_true = 5.3 * dR;                      % 目标真实距离 (刻意非格点, 避免 MSE=0)
v_true = 0;                             % 目标速度 (m/s)

% 扫描参数
rho_dB_range = -20:2:50;                % SI 强度 (dB)
snr_dB_list  = [-10, 0, 10];            % 信噪比 (dB)
numMC        = 1000;                    % 蒙特卡洛次数
threshold_rise_dB = 3;                  % 阈值判定: MSE 相对基线抬升 3dB

% SI 信道参数 (Rician 模型)
kappa_SI  = 10;     % Rician K 因子 (线性)
d_ant     = 1;      % 收发阵列间距 (λ/2 为单位)
an_ant    = pi/6;   % 收发阵列夹角

fprintf('系统: fc=%.0fGHz, Δf=%.0fkHz, N=%d, L=%d, Nt=%d, Nr=%d\n', ...
    fc/1e9, Df/1e3, N, L, Nt, Nr);
fprintf('目标: R=%.3fm (%.1f×ΔR), v=%.1fm/s, β=%.2f\n', ...
    R_true, R_true/dR, v_true, beta_target);
fprintf('扫描: ρ=[%d:%d]dB, SNR=[%s]dB, MC=%d\n', ...
    rho_dB_range(1), rho_dB_range(end), ...
    strjoin(arrayfun(@(x) sprintf('%d', x), snr_dB_list, 'UniformOutput', false), ','), ...
    numMC);

%% ===== 预计算固定量 =====
% 距离/多普勒相位 (公式 9, 10)
omega_r = -4 * pi * Df * R_true / c;
omega_v =  4 * pi * T * v_true * fc / c;
phase_r = exp(1j * (0:N-1).' * omega_r);   % N×1
phase_v = exp(1j * (0:L-1)   * omega_v);   % 1×L

% 空间导向矢量 (ULA, 归一化)
a_tx = ones(Nt, 1) / sqrt(Nt);   % 发射导向矢量
b_rx = ones(Nr, 1) / sqrt(Nr);   % 接收导向矢量

% 发射信号: x = a_tx (恒模导频)
% 回波信号核心: sensing_core(i,l) = beta * (a^H * a) * phase_r(i) * phase_v(l)
%   其中 a^H * a = 1 (归一化)
sensing_core = beta_target * (phase_r * phase_v);   % N×L

%% ===== 蒙特卡洛仿真主循环 =====
numRho = numel(rho_dB_range);
numSNR = numel(snr_dB_list);
mse_avg = zeros(numSNR, numRho);

% 进度条
total_iter = numSNR * numRho * numMC;
done_iter  = 0;
t_start    = tic;

for is = 1:numSNR
    snr_dB   = snr_dB_list(is);
    noiseVar = 10^(-snr_dB / 10);   % 噪声方差 (信号功率归一化为 1)
    
    fprintf('\n--- SNR = %d dB ---\n', snr_dB);
    
    for ir = 1:numRho
        rho_dB = rho_dB_range(ir);
        rho_SI = 10^(rho_dB / 10);  % SI 功率系数 (线性)
        
        sq_err = zeros(numMC, 1);
        
        for imc = 1:numMC
            % ---- 生成 SI 信道 H_SI (Nr×Nt) ----
            Hsi = generate_HSI_local(Nt, Nr, kappa_SI, d_ant, an_ant);
            
            % ---- 自干扰项: sqrt(rho_SI) * H_SI * a_tx ----
            % MRC 合并后: int_scalar = sqrt(rho_SI) * b_rx^H * H_SI * a_tx
            g = Hsi * a_tx;                         % Nr×1
            int_scalar = sqrt(rho_SI) * (b_rx' * g); % 标量
            % 频率平坦假设: 干扰对所有 (i,l) 相同
            int_mat = int_scalar * ones(N, L);       % N×L
            
            % ---- MRC 合并后的回波 ----
            sig_comb = sensing_core;                 % N×L
            
            % ---- 噪声 ----
            noise = sqrt(noiseVar/2) * (randn(N, L) + 1j * randn(N, L));
            
            % ---- 接收信号 = 回波 + 干扰 + 噪声 ----
            y_new = sig_comb + int_mat + noise;
            
            % ---- 参数估计: 2D-FFT + 峰值搜索 ----
            R_hat = original_processing_flow_local(y_new, N, L, Df, c);
            
            % ---- MSE 累积 ----
            sq_err(imc) = (R_hat - R_true)^2;
            
            done_iter = done_iter + 1;
        end
        
        mse_avg(is, ir) = mean(sq_err);
        
        % 每 10 个 rho 点打印一次进度
        if mod(ir, 10) == 0 || ir == numRho
            elapsed = toc(t_start);
            eta = elapsed / done_iter * (total_iter - done_iter);
            fprintf('  ρ=%+3ddB: MSE=%.2e m² | 进度 %.1f%% | 预计剩余 %.0fs\n', ...
                rho_dB, mse_avg(is, ir), 100*done_iter/total_iter, eta);
        end
    end
end

fprintf('\n仿真完成, 总耗时 %.1f 秒\n', toc(t_start));

%% ===== 阈值检测 =====
threshold_rho_dB = nan(1, numSNR);
threshold_idx    = nan(1, numSNR);

for is = 1:numSNR
    % 基线: 取最低 5 个 rho 点的平均 MSE
    baseline = mean(mse_avg(is, 1:min(5, numRho)));
    baseline = max(baseline, eps);
    rise_dB  = 10 * log10(max(mse_avg(is, :), eps) / baseline);
    idx_t    = find(rise_dB >= threshold_rise_dB, 1, 'first');
    if ~isempty(idx_t)
        threshold_idx(is)    = idx_t;
        threshold_rho_dB(is) = rho_dB_range(idx_t);
    end
end

%% ===== 绘图 =====
figure('Color', 'w', 'Position', [100 100 800 500]);
hold on; grid on; box on;
colors = lines(numSNR);
hLine  = gobjects(1, numSNR);

for is = 1:numSNR
    mse_dB = 10 * log10(max(mse_avg(is, :), eps));
    hLine(is) = plot(rho_dB_range, mse_dB, '-o', 'LineWidth', 2, ...
        'MarkerSize', 4, 'Color', colors(is, :), ...
        'DisplayName', sprintf('SNR = %d dB', snr_dB_list(is)));
    
    % 标记阈值点
    if ~isnan(threshold_rho_dB(is))
        idx_t = threshold_idx(is);
        plot(threshold_rho_dB(is), mse_dB(idx_t), 's', ...
            'MarkerSize', 12, 'LineWidth', 2, ...
            'Color', colors(is, :), 'MarkerFaceColor', colors(is, :), ...
            'HandleVisibility', 'off');
        text(threshold_rho_dB(is) + 1, mse_dB(idx_t), ...
            sprintf('\\rho_{th}=%.0f dB', threshold_rho_dB(is)), ...
            'Color', colors(is, :), 'FontSize', 11, 'FontWeight', 'bold');
    end
end

xlabel('\rho_{SI} (dB)', 'FontSize', 13);
ylabel('MSE of Range Estimation (dB, m^2)', 'FontSize', 13);
title('自干扰强度对距离估计性能的影响', 'FontSize', 14);
legend(hLine, 'Location', 'northwest', 'FontSize', 11);
set(gca, 'FontSize', 11, 'LineWidth', 1.2);

%% ===== 打印阈值汇总 =====
fprintf('\n=================================================\n');
fprintf('  阈值汇总 (MSE 相对基线抬升 >= %d dB 的 ρ 值)\n', threshold_rise_dB);
fprintf('=================================================\n');
for is = 1:numSNR
    if ~isnan(threshold_rho_dB(is))
        fprintf('  SNR = %+3d dB → ρ_threshold = %+.0f dB\n', ...
            snr_dB_list(is), threshold_rho_dB(is));
    else
        fprintf('  SNR = %+3d dB → 未达到阈值\n', snr_dB_list(is));
    end
end

%% ===== 保存结果 =====
result = struct();
result.rho_dB_range     = rho_dB_range;
result.snr_dB_list      = snr_dB_list;
result.mse_avg          = mse_avg;
result.mse_avg_dB       = 10 * log10(max(mse_avg, eps));
result.threshold_rho_dB = threshold_rho_dB;
result.threshold_idx    = threshold_idx;
result.numMC            = numMC;
result.R_true           = R_true;
result.dR               = dR;
save('SI_MSE_analysis_results.mat', 'result');
fprintf('\n结果已保存到 SI_MSE_analysis_results.mat\n');

%% ===== 局部函数 =====

function Hsi = generate_HSI_local(Nt, Nr, kappa_SI, d, an)
% generate_HSI_local  生成 LoS + NLoS 自干扰信道 (公式 12)
%   H_SI = sqrt(κ/(κ+1)) * H_LoS + sqrt(1/(κ+1)) * H_NLoS
%
% 输出: Hsi (Nr × Nt), 归一化为 ||H||_F^2 = Nt*Nr

    % --- LoS 部分: 近场几何模型 ---
    dot_val = d / tan(an);
    dos_val = d / sin(an);
    Rmat = zeros(Nr, Nt);
    for row = 1:Nr
        for col = 1:Nt
            Rmat(row, col) = sqrt( ...
                (dot_val + (col-1)/2)^2 + ...
                (dos_val + (row-1)/2)^2 - ...
                2*(dot_val + (col-1)/2)*(dos_val + (row-1)/2)*cos(an));
        end
    end
    Hlos = exp(-1j * 2 * pi * Rmat) ./ Rmat;
    Hlos = Hlos * sqrt(Nt * Nr / trace(Hlos * Hlos'));
    
    % --- NLoS 部分: Saleh-Valenzuela 散射信道 ---
    Ncl = 4; Nray = 10;
    std_phi = 0.1; std_theta = 0.1; Pr = 1;
    
    Ltot = Ncl * Nray;
    phi_cl    = sin(2*pi*rand(Ncl, 1));
    theta_cl  = sin(2*pi*rand(Ncl, 1));
    phi_mat   = repmat(phi_cl,   [1 Nray]) + std_phi   * randn(Ncl, Nray);
    theta_mat = repmat(theta_cl, [1 Nray]) + std_theta * randn(Ncl, Nray);
    
    epsilon = (0:Nt-1).';
    zeta    = (0:Nr-1).';
    phi_vec   = phi_mat(:);
    theta_vec = theta_mat(:);
    
    At = exp(1j * pi * (epsilon * phi_vec.'))   / sqrt(Nt);
    Ar = exp(1j * pi * (zeta   * theta_vec.')) / sqrt(Nr);
    
    alpha = (sqrt(Pr)/2) * (randn(Ncl, Nray) + 1j*randn(Ncl, Nray));
    alpha = alpha(:);
    [~, I] = sort(abs(alpha), 'descend');
    alpha = alpha(I);
    
    Hnlos = Ar(:,I) * diag(alpha) * At(:,I)';
    Hnlos = Hnlos * sqrt(Nt * Nr / (norm(Hnlos, 'fro')^2));
    
    % --- 合成 Rician 信道 ---
    Hsi = sqrt(kappa_SI / (kappa_SI + 1)) * Hlos + ...
          sqrt(1 / (kappa_SI + 1)) * Hnlos;
    
    % 最终归一化
    Hsi = Hsi * sqrt(Nt * Nr / (norm(Hsi, 'fro')^2));
end

function R_hat = original_processing_flow_local(y_new, N, L, Df, c)
% original_processing_flow_local  参数估计: 2D-FFT + 峰值搜索 → 距离估计
%   输入: y_new (N×L) 接收信号
%   输出: R_hat 估计距离 (m)

    % 2D-FFT
    R2D = fft2(y_new);          % N×L
    P   = abs(R2D).^2;         % 功率谱
    
    % 峰值搜索
    [~, idx_peak] = max(P(:));
    [n_peak, ~]   = ind2sub([N, L], idx_peak);
    n_idx = n_peak - 1;        % 0-indexed
    
    % 频率索引 → 距离
    % omega_r = -4π·Δf·R/c, FFT bin k 对应 omega = 2π·k/N
    % 所以 R = -k·c/(2·N·Δf), 取模处理
    range_bin = mod(N - n_idx, N);
    if range_bin > N/2
        range_bin = range_bin - N;
    end
    R_hat = range_bin * c / (2 * N * Df);
end
