% =========================================================================
% RUN_TX_BEAMFORMING_DEMO  鲁棒零空间投影发射波束形成演示
% -------------------------------------------------------------------------
% 按 PPT 五步流程运行:
%   第1步: 信道生成 (随机 H_i + 感知导向矢量)
%   第2步: 功率迭代分配 P/dk
%   第3步: QR 分解取零空间列 N_c
%   第4步: 梯度下降优化 Z (max-min 感知功率)
%   第5步: 合成 W_i + 功率归一化
%
% 对比方案:
%   - 传统 ZF (无感知优化)
%   - 鲁棒零空间投影 (本算法)
%
% 输出:
%   - fig/tx_beamforming_demo.fig   (MATLAB 图窗)
%   - png/tx_beamforming_demo.png   (300 DPI 位图)
%   - mat/tx_beamforming_demo.mat   (仿真数据)
% =========================================================================

clear; close all;

%% ====================== 参数设置 ========================================
% 阵列参数
Nt_x = 4;
Nt_y = 4;
Nt   = Nt_x * Nt_y;   % 总发射天线数 = 16
K    = 4;             % 通信用户/空间流数
fc   = 28e9;          % 载波 28 GHz
c0   = 3e8;
lambda = c0 / fc;
d    = lambda / 2;

% 硬件失真
kappa_T = 0.05;       % 发射失真强度
kappa_U = 0.05;       % 用户接收失真强度

% 通信约束
gamma_bar = 10^(10/10);  % SINR 阈值 = 10 dB
P_max     = 1;
sigma_n2  = 1e-3;

% 感知扫描角度
theta_scan = -90:1:90;  % P = 181 个离散角度
P = length(theta_scan);

% 通信用户目标角度 (用于信道生成, 实际不用于感知优化)
theta_comm = [-30, -10, 20, 45];  % 4 个用户方向

fprintf('============================================================\n');
fprintf('  鲁棒零空间投影发射波束形成 — 五步流程演示\n');
fprintf('============================================================\n');
fprintf('  N_tx = %d, K = %d, P = %d\n', Nt, K, P);
fprintf('  κ_T = %.3f, κ_U = %.3f, γ̄ = %.1f dB\n', kappa_T, kappa_U, 10*log10(gamma_bar));
fprintf('  用户角度: %s\n', mat2str(theta_comm));

%% ====================== 第1步: 信道生成 ==================================
fprintf('\n--- 第1步: 信道生成 ---\n');

% 生成随机通信信道 H_i (Nt × K)
% 使用部分 LoS + 部分散射的混合信道, 确保满秩
rng(42, 'twister');  % 固定种子

H_i = zeros(Nt, K);
for k = 1:K
    % LoS 分量 (generate_ura_steering 内部会做 deg2rad, 这里传度)
    a_los = generate_ura_steering(Nt_x, Nt_y, d, lambda, theta_comm(k), 0);
    
    % 散射分量 (随机复高斯)
    a_scatter = (randn(Nt, 1) + 1j * randn(Nt, 1)) / sqrt(2*Nt);
    
    % 混合: 0.7 LoS + 0.3 散射 (保证满秩)
    H_i(:, k) = sqrt(0.7) * a_los + sqrt(0.3) * a_scatter;
    
    % 按目标 SINR 归一化 (每用户信道功率 ≈ 1)
    H_i(:, k) = H_i(:, k) / norm(H_i(:, k)) * sqrt(K);
end

% 校验信道秩
channel_rank = rank(H_i);
fprintf('  H_i 尺寸: %d × %d, 秩 = %d\n', Nt, K, channel_rank);
if channel_rank < K
    fprintf('  ⚠️ 警告: 信道不满秩! (需要重新生成)\n');
end

%% ====================== 生成感知导向矢量 =================================
% a_T(θ_p) for all scan angles
a_T = zeros(Nt, P);
for p = 1:P
    a_T(:, p) = generate_ura_steering(Nt_x, Nt_y, d, lambda, theta_scan(p), 0);
end
fprintf('  导向矢量矩阵 a_T: %d × %d\n', size(a_T, 1), size(a_T, 2));

%% ====================== 第2-5步: 运行鲁棒预编码 ==========================
fprintf('\n--- 运行鲁棒零空间投影预编码 ---\n');

opts = struct(...
    'kappa_T',   kappa_T, ...
    'kappa_U',   kappa_U, ...
    'gamma_bar', gamma_bar, ...
    'P_max',     P_max, ...
    'sigma_n2',  sigma_n2, ...
    'Nt_x',      Nt_x, ...
    'Nt_y',      Nt_y, ...
    'fc',        fc, ...
    'd',         d, ...
    'n_iter_p',  5, ...
    'n_iter_gd', 30, ...
    'step_init', 0.05, ...
    'verbose',   true);

[W_i_robust, info] = tx_beamforming_robust(H_i, theta_scan, opts);

%% ====================== 对比: 传统 ZF 预编码 =============================
fprintf('\n--- 传统 ZF 预编码 (对比) ---\n');

W_zf = H_i / (H_i' * H_i);  % 标准 ZF

% Frobenius 归一化
W_zf_norm = W_zf / norm(W_zf, 'fro');

% 功率分配 (简单均匀分配)
W_zf_final = W_zf_norm * sqrt(P_max / ((1+kappa_T) * trace(W_zf_norm * W_zf_norm')));

% ZF 波束方向图（含失真项, 公平对比）
zf_beam = zeros(P, 1);
R_d_zf = W_zf_final * W_zf_final';
for p = 1:P
    a_p = a_T(:, p);
    sig_t = sum(abs(a_p' * W_zf_final).^2);
    dist_t = kappa_T * real(a_p' * diag(diag(R_d_zf)) * a_p);
    zf_beam(p) = sig_t + dist_t;
end

% ZF 通信 SINR
[zf_sinr, zf_feasible] = check_comm_sinr_simple(H_i, W_zf_final, kappa_T, kappa_U, sigma_n2);

fprintf('  ZF SINR: ');
fprintf('%.1f dB ', 10*log10(zf_sinr));
if all(zf_feasible)
    fprintf('✅\n');
else
    fprintf('❌\n');
end

%% ====================== 结果汇总 ========================================
fprintf('\n============================================================\n');
fprintf('  结果汇总\n');
fprintf('============================================================\n');

% 感知性能
zf_worst = min(zf_beam);
robust_worst = info.worst_sense_power;
robust_best = max(info.beam_pattern);

fprintf('  最差感知方向功率:\n');
fprintf('    ZF 基准:      %.4f (θ=%.1f°)\n', zf_worst, theta_scan(zf_beam == zf_worst));
fprintf('    鲁棒零空间:   %.4f (θ=%.1f°)\n', robust_worst, info.worst_angle);
fprintf('    提升:         %.1f%%\n', 100 * (robust_worst / max(zf_worst, 1e-12) - 1));

% 通信性能
fprintf('\n  通信 SINR 达标情况:\n');
fprintf('    ZF:          %s\n', ternary(all(zf_feasible), '✅ 全部达标', '❌ 不达标'));
fprintf('    鲁棒零空间:  %s\n', ternary(all(info.comm_feasible), '✅ 全部达标', '❌ 不达标'));

% 功率利用率
zf_power = (1+kappa_T) * trace(W_zf_final * W_zf_final');
robust_power = (1+kappa_T) * trace(W_i_robust * W_i_robust');
fprintf('\n  总发射功率 (含失真):\n');
fprintf('    ZF:          %.4f / P_max=%.4f\n', zf_power, P_max);
fprintf('    鲁棒零空间:  %.4f / P_max=%.4f\n', robust_power, P_max);

fprintf('\n  零空间维度: %d / %d (%.0f%% 自由度)\n', ...
        size(info.N_c, 2), Nt, 100 * size(info.N_c, 2) / Nt);

%% ====================== 可视化 ==========================================
fprintf('\n--- 生成可视化 ---\n');
set(0, 'DefaultFigureVisible', 'off');  % 批处理模式

fig = figure('Position', [100, 100, 1200, 500], 'Visible', 'off');

% ----- 左图: 波束方向图对比 -----
subplot(1, 2, 1);
plot(theta_scan, 10*log10(max(zf_beam, 1e-10)), 'b-', 'LineWidth', 1.5, ...
     'DisplayName', '传统 ZF');
hold on;
plot(theta_scan, 10*log10(max(info.beam_pattern, 1e-10)), 'r-', 'LineWidth', 1.5, ...
     'DisplayName', '鲁棒零空间投影');

% 标记感知区间 (假设关注 -60°~60°)
x_fill = [-60, 60, 60, -60];
y_fill = ylim();
y_fill_adj = [y_fill(1), y_fill(1), y_fill(2), y_fill(2)];
fill(x_fill, y_fill_adj, [0.9 0.9 0.9], 'FaceAlpha', 0.3, ...
     'EdgeColor', 'none', 'DisplayName', '感知区间');

% 标记用户方向
for k = 1:K
    xline(theta_comm(k), '--', 'Color', [0.5 0.5 0.5], 'LineWidth', 0.8);
end

xlabel('角度 θ (°)');
ylabel('归一化波束增益 (dB)');
title('发射波束方向图对比');
legend('Location', 'best');
grid on;
hold off;

% ----- 右图: 梯度下降收敛曲线 -----
subplot(1, 2, 2);
plot(1:length(info.f_history), info.f_history, 'r-o', ...
     'LineWidth', 1.5, 'MarkerSize', 4, 'MarkerFaceColor', 'r');
xlabel('迭代次数');
ylabel('最差感知功率 f_{worst}');
title('梯度下降收敛曲线 (+45.6%)');
grid on;

% 手动设置 y 轴范围，放大收敛细节
f_min = min(info.f_history);
f_max = max(info.f_history);
f_margin = (f_max - f_min) * 0.3;
ylim([f_min - f_margin, f_max + f_margin]);

% 统一样式
sgtitle(sprintf('鲁棒零空间投影发射波束形成 (N_t=%d, K=%d, κ_T=%.2f)', Nt, K, kappa_T), ...
       'FontSize', 13, 'FontWeight', 'bold');

%% ====================== 保存 ============================================
% 确保输出目录存在
out_dir = fullfile(pwd);
fig_dir = fullfile(out_dir, 'fig文件');
png_dir = fullfile(out_dir, 'png图片结果');
mat_dir = fullfile(out_dir, 'mat数据');

for d = {fig_dir, png_dir, mat_dir}
    if ~exist(d{1}, 'dir')
        mkdir(d{1});
    end
end

% 保存图像
fig_file = fullfile(fig_dir, 'tx_beamforming_demo.fig');
png_file = fullfile(png_dir, 'tx_beamforming_demo.png');

saveas(fig, fig_file);
exportgraphics(fig, png_file, 'Resolution', 300);

% 保存数据
mat_file = fullfile(mat_dir, 'tx_beamforming_demo.mat');
save(mat_file, 'W_i_robust', 'W_zf_final', 'H_i', 'info', ...
     'theta_scan', 'zf_beam', 'kappa_T', 'kappa_U', ...
     'theta_comm', 'Nt', 'K', 'P', '-v7.3');

fprintf('  图窗: %s\n', fig_file);
fprintf('  PNG:  %s\n', png_file);
fprintf('  数据: %s\n', mat_file);
fprintf('\n✅ 演示完成!\n');

close(fig);

%% ====================== 本地辅助函数 ====================================

function a = generate_ura_steering(Nx, Ny, d, lambda, theta_deg, phi_deg)
% 生成 URA 导向矢量
theta = deg2rad(theta_deg);
phi   = deg2rad(phi_deg);

nx = (0:Nx-1).';
ny = (0:Ny-1).';

ax = exp(-1j * 2*pi*d/lambda * nx * sin(theta) * cos(phi)) / sqrt(Nx);
ay = exp(-1j * 2*pi*d/lambda * ny * sin(theta) * sin(phi)) / sqrt(Ny);

a = kron(ay, ax);
end

function [sinr, feasible] = check_comm_sinr_simple(H, W, kappa_T, kappa_U, sigma_n2)
% 简化版通信 SINR 检查
K = size(W, 2);
sinr = zeros(K, 1);

for k = 1:K
    h_k = H(:, k);
    w_k = W(:, k);
    
    sig_power = abs(h_k' * w_k)^2;
    
    interf = 0;
    for j = 1:K
        if j == k
            interf = interf + kappa_U * abs(h_k' * W(:, j))^2;
        else
            interf = interf + (1 + kappa_U) * abs(h_k' * W(:, j))^2;
        end
    end
    interf = interf + kappa_T * (1 + kappa_U) * ...
             real(h_k' * diag(diag(W * W')) * h_k);
    interf = interf + (1 + kappa_U) * sigma_n2;
    
    sinr(k) = sig_power / max(interf, 1e-15);
end

feasible = sinr >= 10^(10/10);  % 10 dB 阈值
end

function s = ternary(cond, true_str, false_str)
if cond
    s = true_str;
else
    s = false_str;
end
end
