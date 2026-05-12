function tx = generate_mimo_ofdm_waveform(params)
% =========================================================================
% GENERATE_MIMO_OFDM_WAVEFORM  MIMO-OFDM 发射波形生成 (严格对齐作者源代码)
% -------------------------------------------------------------------------
% 参考作者源代码  作者源代码/main_snr_rmse_quicklook.m  第 42-61 行的 inline
% 信号生成段, 把其中 "信道 H → ZF 预编码 W → 通信符号 S → 发射信号 X" 的
% 4 步流程封装成独立函数:
%
%   (作者原文第 42-47 行)
%   H(:, k, i) = exp(1j*2*pi*(0:Nt-1).'*dt*sin(user_a(k))*fc/c);
%
%   (作者原文第 48-53 行)
%   W(:, :, i) = H(:, :, i) / (H(:, :, i)' * H(:, :, i));
%   W(:, :, i) = W(:, :, i) / norm(W(:, :, i), 'fro');
%
%   (作者原文第 55-60 行)
%   DATA = randi([0 para.mod_order - 1], para.K, para.L, para.Ns);
%   S(:, :, i) = qammod(DATA(:, :, i), 16, 'UnitAveragePower', true);
%
%   (作者原文第 61 行, 对应论文公式 (2): x_i[l] = W_i · s_i[l])
%   X0 = pagemtimes(W, S);
%
% 与作者唯一的差异:
%   作者发射阵是 1D ULA (Nt=16), 本函数推广为 2D URA (Ntx × Nty). 原因是
%   本工程接收阵本身就是 URA, 并且同时估计 俯仰/方位 两个角度, 发射端
%   必须同步升级才能构造正确的 steering vector. URA steering 是两维
%   Kronecker:
%       a_tx(θ, φ)_{nx, ny} = exp(+j 2π d/λ · (nx·sinθ·cosφ + ny·sinθ·sinφ))
%   展平后 a_tx ∈ C^{Ntx·Nty × 1}, 维度与作者 ULA 一致.
%
% 输入 params 必需字段:
%   N           子载波数 Ns
%   K           OFDM 符号数 L
%   mod_order   M-QAM 阶数 (默认 16, 论文 Table II)
%   lambda, d, fc, c
%   Ntx, Nty    发射 URA 两维天线数
%
% 可选字段:
%   K_stream         通信用户/空间流数 (默认 1, 与作者一致)
%   user_theta_rad   各用户俯仰角 (rad, 列向量, 长度 = K_stream)
%   user_phi_rad     各用户方位角
%   若缺省, 则把通信用户方向默认指向第一个雷达目标 (theta_true(1),
%   phi_true(1)), 与作者 "communication user is also the target" 的设定一致.
%
% 输出 tx (struct):
%   S        (K_stream, L, Ns) 通信符号 s_i[l], 单位平均功率
%   W        (Ntx·Nty, K_stream, Ns) ZF 预编码, 每个子载波 Frobenius 归一
%   X        (Ntx, Nty, Ns, L) 发射信号 x_i[l] = W_i · s_i[l]
%   H        (Ntx·Nty, K_stream, Ns) 用户 URA 信道 (仅 LoS 导向矢量)
%   K_stream, M_qam, user_theta_rad, user_phi_rad 便于调试
% =========================================================================

% -------------------------- 参数解析 --------------------------------------
Ns       = params.N;
L        = params.K;
Ntx      = params.Ntx;
Nty      = params.Nty;
Nt_total = Ntx * Nty;

if isfield(params, 'mod_order') && ~isempty(params.mod_order)
    M = params.mod_order;
else
    M = 16;
end
log2M = log2(M);
if M < 2 || abs(log2M - round(log2M)) > eps
    error('mod_order 必须是 2 的正整数次幂');
end

if isfield(params, 'K_stream') && ~isempty(params.K_stream)
    K_stream = params.K_stream;
else
    K_stream = 1;
end

% 用户角度: 缺省时指向第一个真实目标 (与作者 "user 即 target" 一致)
if isfield(params, 'user_theta_rad') && ~isempty(params.user_theta_rad)
    user_theta = params.user_theta_rad(:);
else
    user_theta = deg2rad(params.theta_true(1));
end
if isfield(params, 'user_phi_rad') && ~isempty(params.user_phi_rad)
    user_phi = params.user_phi_rad(:);
else
    user_phi = deg2rad(params.phi_true(1));
end
if numel(user_theta) == 1 && K_stream > 1, user_theta = user_theta * ones(K_stream, 1); end
if numel(user_phi)   == 1 && K_stream > 1, user_phi   = user_phi   * ones(K_stream, 1); end
if numel(user_theta) ~= K_stream || numel(user_phi) ~= K_stream
    error('user_theta_rad / user_phi_rad 的长度必须等于 K_stream=%d', K_stream);
end

% -------------------------------------------------------------------------
% 1. 构造用户 URA 信道 H (与作者源代码 42-47 行的 ULA 版一一对应)
%    a_tx(θ, φ)_{nx, ny} = exp(+j 2π d/λ · (nx sinθ cosφ + ny sinθ sinφ))
%    展平到 (Nt_total, K_stream); 子载波间 LoS 信道相同, 再广播到 Ns 维
% -------------------------------------------------------------------------
k_wave = 2*pi * params.d / params.lambda;
nx_vec = (0:Ntx-1).';
ny_vec = (0:Nty-1).';

H_flat = zeros(Nt_total, K_stream);
for k = 1:K_stream
    u_k = sin(user_theta(k)) * cos(user_phi(k));
    v_k = sin(user_theta(k)) * sin(user_phi(k));
    ax_k = exp(1j * k_wave * nx_vec * u_k);   % (Ntx, 1)
    ay_k = exp(1j * k_wave * ny_vec * v_k);   % (Nty, 1)
    A_k  = ax_k * ay_k.';                      % (Ntx, Nty)
    H_flat(:, k) = A_k(:);                     % 列主序展平 (与 permute 约定一致)
end
H = repmat(H_flat, [1, 1, Ns]);                % (Nt_total, K_stream, Ns)

% -------------------------------------------------------------------------
% 2. ZF 预编码 W (对齐作者源代码 48-53 行)
%    每个子载波独立做伪逆 + Frobenius 归一化
% -------------------------------------------------------------------------
W = zeros(Nt_total, K_stream, Ns);
for i = 1:Ns
    H_i  = H(:, :, i);
    Gram = H_i' * H_i;
    W_i  = H_i / Gram;                         % ZF 伪逆
    W(:, :, i) = W_i / norm(W_i, 'fro');       % Frobenius 单位化
end

% -------------------------------------------------------------------------
% 3. 通信符号 s_i[l] (对齐作者源代码 55-60 行, 16-QAM, UnitAveragePower)
% -------------------------------------------------------------------------
DATA = randi([0, M - 1], K_stream, L, Ns);
S    = zeros(K_stream, L, Ns);
if exist('qammod', 'file') == 2
    for i = 1:Ns
        S(:, :, i) = qammod(DATA(:, :, i), M, 'UnitAveragePower', true);
    end
else
    % 无通信工具箱的手写回退 (方形 M-QAM)
    mside = round(sqrt(M));
    if abs(sqrt(M) - mside) > eps
        error('无 qammod 时仅支持方形 QAM (M = 4, 16, 64, 256)');
    end
    norm_factor = sqrt((2/3) * (M - 1));
    levels = (2*(0:mside-1) - (mside - 1)) / norm_factor;
    i_idx = mod(DATA, mside) + 1;
    q_idx = floor(DATA / mside) + 1;
    S = levels(i_idx) + 1j * levels(q_idx);
end

% -------------------------------------------------------------------------
% 4. x_i[l] = W_i · s_i[l]  (对齐作者源代码第 61 行, 论文公式 (2))
%    结果形状: pagemtimes → (Nt_total, L, Ns),
%    再 reshape + permute 到 (Ntx, Nty, Ns, L), 和
%    simulate_radar_channel_3d / joint_angle_range_velocity_estimator
%    的 4D 接口一致 (模式 B).
% -------------------------------------------------------------------------
X_flat = pagemtimes(W, S);                      % (Nt_total, L, Ns)
X = reshape(X_flat, Ntx, Nty, L, Ns);           % (Ntx, Nty, L, Ns)
X = permute(X, [1, 2, 4, 3]);                   % (Ntx, Nty, Ns, L)

% -------------------------- 输出 -----------------------------------------
tx = struct( ...
    'S', S, ...
    'W', W, ...
    'X', X, ...
    'H', H, ...
    'K_stream', K_stream, ...
    'M_qam', M, ...
    'Ntx', Ntx, ...
    'Nty', Nty, ...
    'user_theta_rad', user_theta, ...
    'user_phi_rad',   user_phi);
end
