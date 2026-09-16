function tx = generate_mimo_ofdm_waveform(params)
%GENERATE_MIMO_OFDM_WAVEFORM Build URA TX signal X = W*S.
%   Input: params.N subcarriers, params.K OFDM symbols, Ntx*Nty TX
%   antennas, K_stream users. Angles user_theta_rad/user_phi_rad are radians;
%   without them the first target direction is also the communication user.
%   H_SI is a frequency-flat (Nr x Nt) matrix; H_SI_per_cc is optional
%   (Nr x Nt x N) despite its historical name and takes precedence.
%
%   Output: tx.X (Ntx x Nty x N x K), tx.W (Nt x K_stream x N),
%   tx.H (Nt x K_stream x N), tx.S (K_stream x K x N), plus diagnostics.
%   Array flattening is MATLAB column-major: reshape(X, Ntx*Nty, N, K).

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

% 用户角度: 缺省时指向第一个真实目标 (演示场景设定)。
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
if isscalar(user_theta) && K_stream > 1, user_theta = user_theta * ones(K_stream, 1); end
if isscalar(user_phi) && K_stream > 1, user_phi   = user_phi   * ones(K_stream, 1); end
if numel(user_theta) ~= K_stream || numel(user_phi) ~= K_stream
    error('user_theta_rad / user_phi_rad 的长度必须等于 K_stream=%d', K_stream);
end

% -------------------------------------------------------------------------
% 1. 构造用户 URA 信道 H
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
% 2. 预编码 W
%    每个子载波独立求预编码 + Frobenius 归一化
%    三种方式:
%      'zf'        —— 传统 ZF (不抑制自干扰)
%      'nullspace' —— 公式 (17), 零空间法
%      'lagrange'  —— 公式 (16), 拉格朗日法
% -------------------------------------------------------------------------
% 选择预编码方法
if isfield(params, 'precoder_type') && ~isempty(params.precoder_type)
    precoder_type = lower(params.precoder_type);
else
    precoder_type = 'zf';
end

% 通信信道 H_flat 对所有子载波相同。默认矩阵 SI 也是频率平坦的，
% 此时只求解一次 W；逐子载波 SI 输入仍按原接口逐项求解。
H_SI_by_sc = [];
H_SI_flat = [];
if isfield(params, 'H_SI_per_cc') && ~isempty(params.H_SI_per_cc)
    H_SI_by_sc = params.H_SI_per_cc;
    if size(H_SI_by_sc, 3) ~= Ns || size(H_SI_by_sc, 2) ~= Nt_total
        error('H_SI_per_cc must be Nr x %d x %d.', Nt_total, Ns);
    end
elseif isfield(params, 'H_SI') && ~isempty(params.H_SI)
    H_SI_flat = params.H_SI;
    if size(H_SI_flat, 2) ~= Nt_total
        error('H_SI must have %d TX antenna columns.', Nt_total);
    end
elseif ~strcmp(precoder_type, 'zf')
    error('precoder_type=%s requires H_SI or H_SI_per_cc.', precoder_type);
end

if isempty(H_SI_by_sc)
    [W_flat, si_leak, comm_err] = local_precoder( ...
        H_flat, H_SI_flat, precoder_type, params);
    W = repmat(W_flat, [1, 1, Ns]);
    si_leak_all = repmat(si_leak, 1, Ns);
    comm_err_all = repmat(comm_err, 1, Ns);
else
    W = zeros(Nt_total, K_stream, Ns);
    si_leak_all = zeros(1, Ns);
    comm_err_all = zeros(1, Ns);
    for i = 1:Ns
        [W(:, :, i), si_leak_all(i), comm_err_all(i)] = ...
            local_precoder(H_flat, H_SI_by_sc(:, :, i), ...
            precoder_type, params);
    end
end

% -------------------------------------------------------------------------
% 3. 通信符号 s_i[l] (16-QAM, unit average power)
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
% 4. x_i[l] = W_i · s_i[l]
%    pagemtimes 输出 (Nt_total, L, Ns)，再变换为接收仿真使用的
%    (Ntx, Nty, Ns, L)。这里的列主序决定 H_SI 的列与 TX 天线匹配。
% -------------------------------------------------------------------------
X_flat = pagemtimes(W, S);                      % (Nt_total, L, Ns)发射信号
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
    'user_phi_rad',   user_phi, ...
    'precoder_info', struct( ...
        'method',       precoder_type, ...
        'si_leak_per_cc',  si_leak_all, ...
        'comm_err_per_cc', comm_err_all, ...
        'si_leak_avg',  mean(si_leak_all(~isnan(si_leak_all))), ...
        'comm_err_avg', mean(comm_err_all)));
end

function [W, si_leak, comm_err] = local_precoder(H_c, H_SI, method, params)
switch method
    case 'zf'
        W = H_c / (H_c' * H_c);
        comm_err = norm(H_c' * W - eye(size(H_c, 2)), 'fro')^2;
        W = W / max(norm(W, 'fro'), eps);
        if isempty(H_SI)
            si_leak = NaN;
        else
            si_leak = norm(H_SI * W, 'fro')^2;
        end
    case {'nullspace', 'lagrange'}
        opts = struct('normalize', true);
        if isfield(params, 'ns_lambda'), opts.ns_lambda = params.ns_lambda; end
        if isfield(params, 'lg_lambda'), opts.lg_lambda = params.lg_lambda; end
        [W, diag_info] = design_precoder(H_c, H_SI, method, opts);
        si_leak = diag_info.si_leak;
        comm_err = diag_info.comm_err;
    otherwise
        error('Unknown precoder_type: %s', method);
end
end
