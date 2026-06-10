function [W_i, info] = tx_beamforming_robust(H_i, theta_scan, opts)
% =========================================================================
% TX_BEAMFORMING_ROBUST  鲁棒零空间投影发射波束形成（五步流程）
% -------------------------------------------------------------------------
% 实现 PPT 方案推导文档中的五步算法：
%   第1步: 信道准备
%   第2步: 功率迭代分配 P/dk
%   第3步: QR 分解取零空间列 N_c
%   第4步: 梯度下降优化 Z（max-min 感知功率）
%   第5步: 合成波束形成矢量 W_i + 功率归一化
%
% 输入:
%   H_i         (N_t × K)   通信信道矩阵
%   theta_scan  (1 × P)     感知角度扫描点 (度)
%   opts        可选参数结构体，字段:
%     .kappa_T   发射硬件失真强度, 默认 0.05
%     .kappa_U   用户接收失真强度, 默认 0.05   (对应 PPT 的 κ_k)
%     .gamma_bar 通信 SINR 阈值 (线性), 默认 10^(10/10)=10
%     .P_max     最大总发射功率, 默认 1
%     .sigma_n2  噪声功率, 默认 1e-3
%     .Nt_x      发射 URA x 向天线数, 默认 4
%     .Nt_y      发射 URA y 向天线数, 默认 4
%     .fc        载波频率 (Hz), 默认 28e9
%     .d         阵元间距 (m), 默认 λ/2 (自动计算)
%     .n_iter_p  功率分配迭代次数, 默认 5
%     .n_iter_gd 梯度下降迭代次数, 默认 20
%     .step_init 梯度下降初始步长, 默认 0.01
%     .verbose   是否打印中间信息, 默认 true
%
% 输出:
%   W_i     (N_t × K)   最优发射预编码矩阵
%   info    结构体，含中间变量和诊断指标
% =========================================================================

%% ====================== 参数解析 ========================================
if nargin < 3, opts = struct(); end

Nt = size(H_i, 1);
K  = size(H_i, 2);
P  = length(theta_scan);

% 硬件失真参数
kappa_T  = setfield_default(opts, 'kappa_T',  0.05);
kappa_U  = setfield_default(opts, 'kappa_U',  0.05);   % κ_k, 各用户相同
gamma_bar = setfield_default(opts, 'gamma_bar', 10^(10/10));  % 10 dB
sinr_margin_db = setfield_default(opts, 'sinr_margin_db', 1.0);  % 功率分配余量 (dB)
P_max    = setfield_default(opts, 'P_max',    1);
sigma_n2 = setfield_default(opts, 'sigma_n2', 1e-3);

% 阵列参数
Nt_x     = setfield_default(opts, 'Nt_x', 4);
Nt_y     = setfield_default(opts, 'Nt_y', 4);
fc       = setfield_default(opts, 'fc',  28e9);
c0       = 3e8;
lambda   = c0 / fc;
d        = setfield_default(opts, 'd',   lambda/2);

% 迭代参数
n_iter_p  = setfield_default(opts, 'n_iter_p',  5);
n_iter_gd = setfield_default(opts, 'n_iter_gd', 20);
step_init = setfield_default(opts, 'step_init', 0.01);
verbose   = setfield_default(opts, 'verbose',  true);

if verbose
    fprintf('=== 鲁棒零空间投影发射波束形成 ===\n');
    fprintf('  N_t = %d, K = %d, P = %d\n', Nt, K, P);
    fprintf('  κ_T = %.3f, κ_U = %.3f, γ̄ = %.1f (%.1f dB), 功率余量 = %.1f dB\n', ...
            kappa_T, kappa_U, gamma_bar, 10*log10(gamma_bar), sinr_margin_db);
end

%% ====================== 第1步: 生成感知导向矢量 ==========================
% a_T(θ_p) for all scan angles
a_T = zeros(Nt, P);
if Nt_x * Nt_y ~= Nt
    % ULA 模式
    n_vec = (0:Nt-1).';
    for p = 1:P
        theta_rad = deg2rad(theta_scan(p));
        a_T(:, p) = exp(-1j * 2*pi*d/lambda * n_vec * sin(theta_rad));
        a_T(:, p) = a_T(:, p) / sqrt(Nt);  % 归一化
    end
else
    % URA 模式
    nx_vec = (0:Nt_x-1).';
    ny_vec = (0:Nt_y-1).';
    for p = 1:P
        theta_rad = deg2rad(theta_scan(p));
        % 假设方位角 φ=0 进行 1D 扫描
        ax = exp(-1j * 2*pi*d/lambda * nx_vec * sin(theta_rad)) / sqrt(Nt_x);
        ay = exp(-1j * 2*pi*d/lambda * ny_vec * 0) / sqrt(Nt_y);  % φ=0
        a_T(:, p) = kron(ay, ax);
    end
end

%% ====================== 第2步: 功率迭代分配 ==============================
% W0_bar = H_i * (H_i^H * H_i)^{-1}  —— ZF预编码基
W0_bar = H_i / (H_i' * H_i);

% 提取各用户 ZF 波束向量
W_zf_cell = cell(K, 1);
for k = 1:K
    W_zf_cell{k} = W0_bar(:, k);  % w_{i,k}^{ZF}
end

% 预计算 diag 项系数用于 d_k(p)
% d_k(p) = κ_T (1+κ_U) Σ_j p_j · (h_k^H diag{w0_j w0_j^H} h_k)
diag_coeff = zeros(K, K);
for k = 1:K
    h_k = H_i(:, k);
    for j = 1:K
        w0j = W0_bar(:, j);
        diag_coeff(k, j) = real(h_k' * diag(diag(w0j * w0j')) * h_k);
    end
end

% 功率分配迭代 (target 比 SINR 门限高 sinr_margin_db dB, 给零空间优化留余地)
gamma_target = gamma_bar * 10^(sinr_margin_db/10);
p = ones(K, 1) / K;  % 初始均匀分配

for iter = 1:n_iter_p
    p_new = zeros(K, 1);
    for k = 1:K
        % d_k(p) = κ_T (1+κ_U) Σ_j p_j · coeff(k,j)
        d_k = kappa_T * (1 + kappa_U) * sum(p .* diag_coeff(k, :)');
        
        % 功率更新公式 (target = gamma_target, 留余量)
        numerator = gamma_target * (d_k + (1 + kappa_U) * sigma_n2);
        denominator = abs(H_i(:, k)' * W_zf_cell{k})^2 * (1 - gamma_target * kappa_U);
        
        if denominator <= 0
            % 分母非正 → SINR 约束不可行, 设为上限
            p_new(k) = Inf;
        else
            p_new(k) = numerator / denominator;
        end
    end
    
    % 处理不可行情况: 如果任何用户需要无限功率, 比例缩放保持总功率
    if any(isinf(p_new))
        finite_idx = ~isinf(p_new);
        p_new(isinf(p_new)) = 10 * max(p_new(finite_idx));
    end
    
    p = p_new;
    p = max(p, 1e-6);  % 防止零功率
    
    if verbose
        fprintf('  功率迭代 %d/%d: 最大功率比 = %.2f\n', ...
                iter, n_iter_p, max(p) / min(p));
    end
end

% W_0 = W0_bar * P^{1/2}
W0 = W0_bar * diag(sqrt(p));

% 校验通信 SINR（归一化前）
if verbose
    [sinr_k, feasible] = check_comm_sinr(H_i, W0, kappa_T, kappa_U, sigma_n2, gamma_bar);
    fprintf('  功率分配后 - 通信 SINR: ');
    fprintf('%.1f dB ', 10*log10(sinr_k));
    if all(feasible)
        fprintf('✅ 全部达标\n');
    else
        fprintf('⚠️ 部分不达标\n');
    end
end

%% ====================== 第3步: QR 分解取零空间列 =========================
% H_i 的 QR 分解: [Q,R] = qr(H_i), H_i: Nt×K, Q: Nt×Nt
[Q_qr, ~] = qr(H_i);

% 零空间基: N_c = Q(:, K+1 : N_t), 尺寸 Nt × (Nt-K)
N_c = Q_qr(:, K+1:end);

% 验证零空间性质: H_i^H * N_c ≈ 0
zero_check = norm(H_i' * N_c, 'fro');
if verbose
    fprintf('  N_c 零空间验证: ||H_i^H N_c||_F = %.2e (应接近 0)\n', zero_check);
    fprintf('  零空间维度: %d (%.0f%% 自由度)\n', ...
            size(N_c, 2), 100 * size(N_c, 2) / Nt);
end

%% ====================== 第4步: 梯度下降优化 Z ============================
% Z: (Nt-K) × K 的系数矩阵, 初始为零
dim_Nc = size(N_c, 2);
Z = zeros(dim_Nc, K);

% 迭代优化
f_history = zeros(n_iter_gd, 1);

for iter = 1:n_iter_gd
    % 当前发射矩阵
    W_i_curr = W0 + N_c * Z;
    
    % 计算所有角度上的感知功率
    f_p = zeros(P, 1);
    for p = 1:P
        a_p = a_T(:, p);
        % |a_T^H W_i|^2 项: 对 K 个流的功率求和
        sig_vec = a_p' * W_i_curr;  % 1×K
        sig_term = sum(abs(sig_vec).^2);
        
        % κ_T a_T^H diag{W_i W_i^H} a_T 项
        W_prod = W_i_curr * W_i_curr';
        diag_term = a_p' * diag(diag(W_prod)) * a_p;
        
        f_p(p) = sum(sig_term) + kappa_T * real(diag_term);
    end
    
    % 找到最差方向
    [f_worst, p_star] = min(f_p);
    f_history(iter) = f_worst;
    
    % 计算最差方向的梯度
    a_star = a_T(:, p_star);
    
    % ∇_Z f_p*(Z) : 对 Z 求梯度
    % f_p(Z) = ||a_T^H W_0 + a_T^H N_c Z||^2 + kappa_T a_T^H diag{(W_0+N_cZ)(·)^H} a_T
    % 主要项梯度: 2 N_c^H a_T a_T^H (W_0 + N_c Z)
    grad_main = 2 * (N_c' * (a_star * a_star')) * W_i_curr;
    
    % 失真项梯度: kappa_T N_c^H diag(a_star a_star^H) (W_0 + N_c Z)  ← 近似
    diag_a = diag(real(a_star .* conj(a_star)));
    grad_dist = kappa_T * (N_c' * diag_a) * W_i_curr;
    
    grad_Z = grad_main + grad_dist;
    
    % Armijo 线搜索: 确定步长 mu, 同时检查通信 SINR + 功率可行性
    mu = step_init;
    beta_decay = 0.5;
    c_armijo = 1e-4;
    
    grad_norm_sq = norm(grad_Z, 'fro')^2;
    accepted = false;
    
    for search = 1:20
        Z_trial = Z + mu * grad_Z;
        W_trial = W0 + N_c * Z_trial;
        
        % 可行性检查: 通信 SINR + 功率约束
        [sinr_trial, feas_trial] = check_comm_sinr(H_i, W_trial, ...
            kappa_T, kappa_U, sigma_n2, gamma_bar);
        P_trial = (1 + kappa_T) * trace(W_trial * W_trial');
        
        if ~all(feas_trial) || P_trial > P_max
            mu = mu * beta_decay;
            continue;
        end
        
        % 计算试探点的 f_p
        f_trial = zeros(P, 1);
        for p = 1:P
            a_p = a_T(:, p);
            sig_t = sum(abs(a_p' * W_trial).^2);
            diag_t = real(a_p' * diag(diag(W_trial * W_trial')) * a_p);
            f_trial(p) = sig_t + kappa_T * diag_t;
        end
        f_trial_worst = min(f_trial);
        
        % Armijo 条件: f(new) >= f(old) + c * mu * ||grad||^2
        if f_trial_worst >= f_worst + c_armijo * mu * grad_norm_sq
            accepted = true;
            break;
        end
        mu = mu * beta_decay;
    end
    
    % 更新 Z (仅当找到可行解时)
    if accepted
        Z = Z + mu * grad_Z;
    else
        if verbose
            fprintf('  梯度迭代 %2d: 线搜索未找到可行解, 跳过更新\n', iter);
        end
    end
    
    if verbose && mod(iter, 5) == 0
        fprintf('  梯度迭代 %2d/%d: f_worst=%.4f, 步长=%.2e\n', ...
                iter, n_iter_gd, f_worst, mu);
    end
end

if verbose
    fprintf('  梯度下降完成: f_worst %.4f → %.4f (提升 %.1f%%)\n', ...
            f_history(1), f_history(end), ...
            100 * (f_history(end)/max(f_history(1), 1e-12) - 1));
end

%% ====================== 第5步: 合成 W_i + 功率归一化 =====================
W_i = W0 + N_c * Z;

% 预初始化 info (供功率归一化中记录缩放拒绝信息)
power_rejected = false;

% 总功率归一化: 推到 P_max 以公平对比, 诚实记录 SINR 变化
P_actual = (1 + kappa_T) * trace(W_i * W_i');  % 含失真的总功率
scale_factor = sqrt(P_max / max(P_actual, 1e-12));

if abs(scale_factor - 1) > 1e-6
    W_i_scaled = W_i * scale_factor;
    [sinr_scaled, feas_scaled] = check_comm_sinr(H_i, W_i_scaled, ...
        kappa_T, kappa_U, sigma_n2, gamma_bar);
    
    if all(feas_scaled)
        % 缩放后 SINR 仍然达标: 接受
        W_i = W_i_scaled;
        if verbose
            fprintf('  功率推满: %.3f → P_max=%.3f (×%.2f), SINR 仍达标\n', ...
                    P_actual, P_max, scale_factor);
        end
    else
        % 缩放后 SINR 不达标: 保持原功率, 记录缩放会被拒绝
        if verbose
            fprintf('  功率推满被拒: P=%.3f → P_max 会导致 SINR 不达标, 保持原功率\n', P_actual);
        end
        power_rejected = true;
    end
else
    if verbose
        fprintf('  功率已达上限: P_actual=%.3f = P_max\n', P_actual);
    end
end

%% ====================== 诊断输出 ========================================
info = struct();
info.W0      = W0;        % ZF + 功率分配
info.Z       = Z;         % 零空间系数矩阵
info.N_c     = N_c;       % 零空间基
info.Z_opt   = Z;         % 最优 Z
info.p_final = p;         % 最终功率分配
info.f_history = f_history;  % 梯度下降历史
info.power_scaling_rejected = power_rejected;  % 功率推满是否被 SINR 拒绝

% 波束方向图（含硬件失真项, 与优化目标函数一致）
% f_p = |a_T^H W_i|^2 + κ_T a_T^H diag{W_i W_i^H} a_T
R_d_full = W_i * W_i';
info.beam_pattern = zeros(P, 1);
for p = 1:P
    a_p = a_T(:, p);
    sig_term = sum(abs(a_p' * W_i).^2);
    dist_term = kappa_T * real(a_p' * diag(diag(R_d_full)) * a_p);
    info.beam_pattern(p) = sig_term + dist_term;
end

% 通信 SINR 检查
[sinr_final, feasible] = check_comm_sinr(H_i, W_i, kappa_T, kappa_U, sigma_n2, gamma_bar);
info.comm_sinr_dB = 10 * log10(sinr_final);
info.comm_feasible = feasible;
info.comm_sinr_linear = sinr_final;

% 最差感知方向功率
[info.worst_sense_power, info.worst_idx] = min(info.beam_pattern);
info.worst_angle = theta_scan(info.worst_idx);

if verbose
    fprintf('\n=== 最终诊断 ===\n');
    fprintf('  通信 SINR: ');
    fprintf('%.1f dB ', info.comm_sinr_dB);
    if all(feasible)
        fprintf('✅\n');
    else
        fprintf('❌ (不达标)\n');
    end
    fprintf('  最差感知方向: θ=%.1f°, 功率=%.4f\n', ...
            info.worst_angle, info.worst_sense_power);
    fprintf('  总发射功率: P_actual=%.4f\n', (1+kappa_T)*trace(W_i*W_i'));
end

end

%% ====================== 辅助函数 ========================================

function [sinr, feasible] = check_comm_sinr(H, W, kappa_T, kappa_U, sigma_n2, gamma_bar)
% 计算通信 SINR 并检查约束
% γ_k = |h_k^H w_k|^2 / (h_k^H (κ_k w_k w_k^H + (1+κ_k) Σ_{j≠k} w_j w_j^H
%      + κ_T(1+κ_k) diag{W W^H}) h_k + (1+κ_k)σ_k^2)
K = size(W, 2);
sinr = zeros(K, 1);
feasible = false(K, 1);  % 初始 false, 必须显式判断

for k = 1:K
    h_k = H(:, k);
    w_k = W(:, k);
    
    sig_power = abs(h_k' * w_k)^2;  % 期望信号
    
    % 干扰: 其他用户 + 发射失真 + 用户自身失真
    interf = 0;
    for j = 1:K
        if j == k
            % 自身失真项: κ_k |h_k^H w_k|^2
            interf = interf + kappa_U * abs(h_k' * W(:, j))^2;
        else
            % 其他用户: (1+κ_k) |h_k^H w_j|^2
            interf = interf + (1 + kappa_U) * abs(h_k' * W(:, j))^2;
        end
    end
    
    % 发射失真贡献: κ_T (1+κ_k) h_k^H diag{W W^H} h_k
    interf = interf + kappa_T * (1 + kappa_U) * ...
             real(h_k' * diag(diag(W * W')) * h_k);
    
    % 噪声: (1+κ_k) σ_k^2
    interf = interf + (1 + kappa_U) * sigma_n2;
    
    sinr(k) = sig_power / max(interf, 1e-15);
    feasible(k) = sinr(k) >= gamma_bar;  % 显式判断
end

end

function val = setfield_default(s, fieldname, default)
% 如果 s 存在 fieldname 字段则赋值, 否则用 default
if isfield(s, fieldname)
    val = s.(fieldname);
else
    val = default;
end
end
