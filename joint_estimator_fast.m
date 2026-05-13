function [theta_est, phi_est, R_est, v_est, info] = joint_estimator_fast(rx_cube, tx_signal, params)
% =========================================================================
% JOINT_ESTIMATOR_FAST  快速 4D 联合角度-距离-速度估计器
% -------------------------------------------------------------------------
% 设计目标: 在保持估计精度的前提下, 将运行时间从 ~40s 压缩到 <1s.
%
% 与原始算法的关键区别:
%   原始算法: 对每个角度 bin (64个) 都做 (Ns, L) 的 2D-FFT → 64次大FFT
%   快速版:   先空间压缩做 1 次 2D-FFT 粗检测 RD 位置,
%             再对每个目标用相位补偿聚焦 + 2D-ESPRIT 精估角度.
%
% 精度保证:
%   - 距离/速度: 全分辨率 FFT + 抛物线插值, 与原始算法一致
%   - 角度: 2D-ESPRIT 利用原始算法相同的相位补偿聚焦方法
%
% 接口与 joint_angle_range_velocity_estimator 完全兼容.
% =========================================================================

% -------------------------------------------------------------------------
% 0. 维度与参数
% -------------------------------------------------------------------------
[Mx, My, Ns, L] = size(rx_cube);
Q = params.num_targets;
delta_f = params.B / Ns;
Rmax = params.c / (2 * delta_f);

% 配置参数
if isfield(params, 'fast_estimator')
    cfg = params.fast_estimator;
else
    cfg = struct();
end

% ESPRIT 局部采样点数
if isfield(cfg, 'n_samples_range')
    n_samp_r = min(Ns, max(64, cfg.n_samples_range));
else
    n_samp_r = min(Ns, 384);
end
if isfield(cfg, 'n_samples_doppler')
    n_samp_l = min(L, max(16, cfg.n_samples_doppler));
else
    n_samp_l = min(L, 64);
end

% NMS 参数
if isfield(cfg, 'nms_r'), nms_r = cfg.nms_r; else, nms_r = 2; end
if isfield(cfg, 'nms_v'), nms_v = cfg.nms_v; else, nms_v = 2; end

% 候选数
num_candidates = max(2*Q, 8);
if isfield(cfg, 'num_candidates')
    num_candidates = max(2*Q, cfg.num_candidates);
end

% -------------------------------------------------------------------------
% 1. 信道均衡 (去除发射信号影响) - 分块操作节省内存
% -------------------------------------------------------------------------
sz_tx = size(tx_signal);
if isequal(sz_tx, [Ns, L])
    tx_eq = tx_signal;
    % 分块均衡, 避免广播产生 (Mx,My,Ns,L) 临时数组
    conj_tx = conj(tx_signal);  % (Ns, L)
    for l_idx = 1:L
        rx_cube(:,:,:,l_idx) = rx_cube(:,:,:,l_idx) .* ...
            reshape(conj_tx(:,l_idx), 1, 1, Ns);
    end
    rx_eq = rx_cube;  % in-place, 不额外分配
else
    % MIMO 发射端: 用各天线求和后的等效标量做均衡
    tx_sum = squeeze(sum(sum(tx_signal, 1), 2));   % (Ns, L)
    tx_eq = tx_sum;
    tx_sum_norm = tx_sum ./ max(abs(tx_sum), eps);
    conj_tx_norm = conj(tx_sum_norm);  % (Ns, L)
    for l_idx = 1:L
        rx_cube(:,:,:,l_idx) = rx_cube(:,:,:,l_idx) .* ...
            reshape(conj_tx_norm(:,l_idx), 1, 1, Ns);
    end
    rx_eq = rx_cube;
end

% -------------------------------------------------------------------------
% 2. 全分辨率 RD 粗检测 (空间压缩, 单次 2D-FFT)
% -------------------------------------------------------------------------
% 空间维非相干累加: (Mx, My, Ns, L) → (Ns, L)
s_sum = squeeze(sum(sum(rx_eq, 1), 2));   % (Ns, L)

% 全分辨率 2D-FFT → RD 谱
RD = fft(s_sum, Ns, 1);       % 距离维 FFT
RD = fft(RD, L, 2);           % 多普勒维 FFT
RD = fftshift(RD, 2);         % 多普勒 shift 到中心, 距离不 shift
P = abs(RD).^2;

% 峰值检测
[~, idx] = maxk(P(:), min(num_candidates * 4, numel(P)));

% 距离/多普勒 bin 索引
nr_vec = (0 : Ns - 1).';                          % 距离维未 shift (0-based)
nv_vec = (-floor(L/2) : (ceil(L/2) - 1)).';       % 多普勒已 shift

% -------------------------------------------------------------------------
% 3. 对每个候选目标: ESPRIT 角度精化 + 距离/速度插值
% -------------------------------------------------------------------------
% 预计算 ESPRIT 采样网格
esprit_n_idx = round(linspace(1, Ns, n_samp_r));
esprit_l_idx = round(linspace(1, L, n_samp_l));
esprit_n_vec = esprit_n_idx(:) - 1;   % 0-based
esprit_l_vec = esprit_l_idx(:) - 1;

theta_est = zeros(1, Q);
phi_est   = zeros(1, Q);
R_est     = zeros(1, Q);
v_est     = zeros(1, Q);
detected  = 0;
selected_ir = zeros(1, Q);
selected_iv = zeros(1, Q);

for ii = 1:numel(idx)
    if detected >= Q
        break;
    end
    
    [ir, iv] = ind2sub([Ns, L], idx(ii));
    nr = nr_vec(ir);   % 0-based 距离 bin
    nv = nv_vec(iv);   % 多普勒 bin (已 shift)
    
    % NMS: 检查是否与已检测目标太近
    if detected > 0
        if any(abs(ir - selected_ir(1:detected)) <= nms_r & ...
               abs(iv - selected_iv(1:detected)) <= nms_v)
            continue;
        end
    end
    
    % -----------------------------------------------------------------
    % 3.1 ESPRIT 角度精化
    % -----------------------------------------------------------------
    % 计算该目标对应的数字角频率
    omega_r = 2 * pi * nr / Ns;
    omega_v = 2 * pi * nv / L;
    
    % 相位补偿聚焦: 将目标信号在距离/多普勒维聚焦到零频
    phase_n = exp(-1j * esprit_n_vec * omega_r);
    phase_l = exp(-1j * esprit_l_vec * omega_v);
    W_focus = phase_n * phase_l.';   % (n_samp_r, n_samp_l)
    
    % 提取局部均衡数据并聚焦, 得到空间快拍
    X_sub = rx_eq(:, :, esprit_n_idx, esprit_l_idx);
    spatial_snap = sum(sum(X_sub .* reshape(W_focus, 1, 1, n_samp_r, n_samp_l), 3), 4);
    % spatial_snap: (Mx, My)
    
    % 2D-ESPRIT: 相邻阵元相位旋转不变性
    sx1 = spatial_snap(1:end-1, :);
    sx2 = spatial_snap(2:end, :);
    phi_x = angle(sum(conj(sx1(:)) .* sx2(:)));
    
    sy1 = spatial_snap(:, 1:end-1);
    sy2 = spatial_snap(:, 2:end);
    phi_y = angle(sum(conj(sy1(:)) .* sy2(:)));
    
    % 相位差 → 方向余弦 → 角度
    u_hat = -phi_x * params.lambda / (2 * pi * params.d);
    v_hat = -phi_y * params.lambda / (2 * pi * params.d);
    u_hat = max(min(u_hat, 1), -1);
    v_hat = max(min(v_hat, 1), -1);
    
    sin_theta = min(sqrt(u_hat^2 + v_hat^2), 1);
    theta_val = asind(sin_theta);
    phi_val   = atan2d(v_hat, u_hat);
    
    % -----------------------------------------------------------------
    % 3.2 距离估计: FFT bin + 抛物线插值
    % -----------------------------------------------------------------
    nr_frac = double(nr);
    ir_left  = mod(ir - 2, Ns) + 1;
    ir_right = mod(ir, Ns) + 1;
    Pl = P(ir_left, iv);
    Pc = P(ir, iv);
    Pr = P(ir_right, iv);
    denom_interp = Pl - 2*Pc + Pr;
    if abs(denom_interp) > eps
        delta_r = 0.5 * (Pl - Pr) / denom_interp;
        delta_r = max(min(delta_r, 0.5), -0.5);
        nr_frac = nr_frac + delta_r;
    end
    R_val = mod(-params.c * nr_frac / (2 * Ns * delta_f), Rmax);
    
    % -----------------------------------------------------------------
    % 3.3 速度估计: FFT bin + 抛物线插值
    % -----------------------------------------------------------------
    nv_frac = double(nv);
    if iv > 1 && iv < L
        Pl = P(ir, iv-1);
        Pc = P(ir, iv);
        Pr = P(ir, iv+1);
        denom_interp = Pl - 2*Pc + Pr;
        if abs(denom_interp) > eps
            delta_v = 0.5 * (Pl - Pr) / denom_interp;
            delta_v = max(min(delta_v, 0.5), -0.5);
            nv_frac = nv_frac + delta_v;
        end
    end
    v_val = params.c * nv_frac / (2 * L * params.Ts * params.fc);
    
    % -----------------------------------------------------------------
    % 3.4 记录结果
    % -----------------------------------------------------------------
    detected = detected + 1;
    theta_est(detected) = theta_val;
    phi_est(detected)   = phi_val;
    R_est(detected)     = R_val;
    v_est(detected)     = v_val;
    selected_ir(detected) = ir;
    selected_iv(detected) = iv;
end

% -------------------------------------------------------------------------
% 4. 截断并输出
% -------------------------------------------------------------------------
theta_est = theta_est(1:detected);
phi_est   = phi_est(1:detected);
R_est     = R_est(1:detected);
v_est     = v_est(1:detected);

info = struct();
info.detector         = 'joint_estimator_fast';
info.detected_targets = detected;
info.Ns               = Ns;
info.L                = L;
info.n_samp_r         = n_samp_r;
info.n_samp_l         = n_samp_l;
end
