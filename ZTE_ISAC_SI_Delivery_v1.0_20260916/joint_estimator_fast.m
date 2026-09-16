function [theta_est, phi_est, R_est, v_est, info] = joint_estimator_fast(rx_cube, tx_signal, params)
% =========================================================================
% JOINT_ESTIMATOR_FAST  RD 粗检测 + 角度估计 + 距离/速度峰值插值
% 输入: rx_cube (Mx x My x N x K), tx_signal (Ntx x Nty x N x K)
%       或已经求和的发射参考 (N x K)。K 是 OFDM 符号数。
% 输出: 估计值均为 1 x detected_targets 行向量，单位依次为度、度、米、m/s。
% 假设: MIMO 参考采用 TX 天线求和近似；适用范围需用目标场景评估。
% =========================================================================

[~, ~, Ns, L] = size(rx_cube);
Q = params.num_targets;
delta_f = params.B / Ns;

% ---- 可配置参数 ----
cfg = struct();
cfg.n_samp_r       = 256;   % 聚焦快拍选取的距离采样数
cfg.n_samp_l       = 64;    % 聚焦快拍选取的 OFDM 符号数
cfg.n_pad_v        = L;     % 多普勒 FFT 点数，至少为 L
cfg.enable_hann    = true;  % Hann 窗降旁瓣
cfg.num_candidates = 64;    % 候选峰值数
cfg.nms_r          = 2;     % NMS 距离保护
cfg.nms_v          = 2;     % NMS 多普勒保护
cfg.R_min_gate     = 20;    % 距离门限: 排除 SI 假峰
cfg.R_max_gate     = 0;     % 最大距离门限 (0 = 不启用):
                            % 频率平坦 SI 在 DC bin (R=Rmax) 有相干峰,
                            % 超出感知范围时可用此门限滤除

% 用户覆盖
if isfield(params, 'fast_estimator')
    f = fieldnames(params.fast_estimator);
    for k = 1:numel(f)
        if isfield(cfg, f{k})
            cfg.(f{k}) = params.fast_estimator.(f{k});
        end
    end
end

n_samp_r = min(Ns, max(64, cfg.n_samp_r));
n_samp_l = min(L,  max(16, cfg.n_samp_l));
Nv_pad   = max(L, cfg.n_pad_v);
% 奇数 FFT 长度补到下一个 2 的幂；偶数长度保持配置值。
if mod(Nv_pad, 2) ~= 0
    Nv_pad = 2^nextpow2(Nv_pad);
end
num_candidates = max(2*Q, cfg.num_candidates);

% =========================================================================
% 阶段 1: 距离-速度粗检测 (公式 17-21)
% =========================================================================

% --- 公式(17): 均衡 ---
% 发射参考用 TX 天线求和近似 (broadside)，不是真值目标方向的 a^H*x。
sz_tx = size(tx_signal);
if isequal(sz_tx, [Ns, L])
    tx_ref = tx_signal;
else
    % MIMO 模式: sum over TX antennas = broadside 近似 a^H·x
    tx_ref = squeeze(sum(sum(tx_signal, 1), 2));   % (Ns, L)
end
tx_ref_norm = tx_ref ./ max(abs(tx_ref), eps);

% --- 公式(18): 空间求和 ---
rx_sum = squeeze(sum(rx_cube, [1, 2]));            % (Ns, L)
rx_eq = rx_sum .* conj(tx_ref_norm);               % (Ns, L)

% --- 公式(19-20): 2D-FFT → 功率谱 ---
if cfg.enable_hann
    win_r = local_periodic_hann(Ns);
    win_v = local_periodic_hann(L);
    rx_eq = rx_eq .* (win_r * win_v.');
end
RD = fft(rx_eq, Ns, 1);                            % 距离 FFT
RD = fft(RD, Nv_pad, 2);                           % 多普勒 FFT (不补零时 Nv_pad=L)
RD = fftshift(RD, 2);
P = abs(RD).^2;                                     % 公式(20)

% --- 公式(21): 峰值检测 ---
[~, idx] = maxk(P(:), min(num_candidates * 4, numel(P)));

% 距离/多普勒 bin 向量 (0-based, 与公式一致)
nr_vec = (0 : Ns - 1).';
nv_vec = (-floor(Nv_pad/2) : (ceil(Nv_pad/2) - 1)).';
doppler_scale = L / Nv_pad;   % 补零后 bin 缩放

% =========================================================================
% 阶段 2: 空间相位差角度估计 + 抛物线插值
% =========================================================================

% 输出初始化
theta_est = zeros(1, Q);
phi_est   = zeros(1, Q);
R_est     = zeros(1, Q);
v_est     = zeros(1, Q);
detected  = 0;
selected_ir = zeros(1, Q);
selected_iv = zeros(1, Q);

for ii = 1:numel(idx)
    if detected >= Q, break; end
    
    [ir, iv] = ind2sub([Ns, Nv_pad], idx(ii));
    nr = nr_vec(ir);                                % 0-based 距离 bin
    nv_raw = nv_vec(iv);                            % 多普勒 bin (补零后)
    nv = nv_raw * doppler_scale;                    % 还原到 L 尺度
    
    % NMS 去重
    if detected > 0
        nv_prev = selected_iv(1:detected);
        if any(abs(ir - selected_ir(1:detected)) <= cfg.nms_r & ...
               abs(nv - nv_prev) <= cfg.nms_v * doppler_scale)
            continue;
        end
    end
    
    % 距离门限
    if isfield(cfg, 'R_min_gate') && cfg.R_min_gate > 0
        R_check = params.c * (Ns - nr) / (2 * Ns * delta_f);
        if R_check < cfg.R_min_gate, continue; end
    end
    if isfield(cfg, 'R_max_gate') && cfg.R_max_gate > 0
        R_check = params.c * (Ns - nr) / (2 * Ns * delta_f);
        if R_check > cfg.R_max_gate, continue; end
    end
    
    % --- 局部窗口 (公式 22-23 的 Ω_r, Ω_v) ---
    % 以检测峰为中心选取局部快拍，避免在全距离轴做空间聚焦。
    r_win = max(32, round(Ns / 100));               % ~127 bins ≈ 12.5m
    v_win = max(8,  round(L / 32));                 % ~8 bins
    n_start = max(1, ir - r_win);
    n_end   = min(Ns, ir + r_win);
    l_idx_abs = round(nv + L/2) + 1;                % 转为 1-based L 尺度
    l_start = max(1, l_idx_abs - v_win);
    l_end   = min(L, l_idx_abs + v_win);
    
    esprit_r_idx = round(linspace(n_start, n_end, n_samp_r));
    esprit_l_idx = round(linspace(l_start, l_end, n_samp_l));
    esprit_r_vec = esprit_r_idx(:) - 1;             % 0-based
    esprit_l_vec = esprit_l_idx(:) - 1;             % 0-based
    
    % --- 公式(22): 相位补偿因子 ---
    omega_r = 2 * pi * nr / Ns;
    omega_v = 2 * pi * nv / L;
    W_r = exp(-1j * esprit_r_vec * omega_r);        % (n_samp_r, 1)
    W_l = exp(-1j * esprit_l_vec * omega_v);        % (n_samp_l, 1)
    W_focus = W_r * W_l.';                           % (n_samp_r, n_samp_l)
    
    % --- 公式(23): 空间快拍 ---
    % Ȳ_i[l] = rx_cube(:,:,i,l) · conj(x_ref[i,l])
    X_local = rx_cube(:, :, esprit_r_idx, esprit_l_idx);
    tx_local = tx_ref(esprit_r_idx, esprit_l_idx);
    tx_local_norm = tx_local ./ max(abs(tx_local), eps);
    X_local_eq = X_local .* reshape(conj(tx_local_norm), 1, 1, n_samp_r, n_samp_l);
    
    % Y_snap = Σᵢ Σₗ Ȳ_i[l] · e^{-jω̂_r} · e^{-jω̂_v}
    Y_snap = sum(X_local_eq .* reshape(W_focus, 1, 1, n_samp_r, n_samp_l), [3 4]);
    
    % 相邻 RX 阵元共轭乘积的相位差；未构造子空间 ESPRIT 算子。
    Y_x1 = Y_snap(1:end-1, :);
    Y_x2 = Y_snap(2:end, :);
    phi_x = angle(sum(conj(Y_x1(:)) .* Y_x2(:)));
    
    Y_y1 = Y_snap(:, 1:end-1);
    Y_y2 = Y_snap(:, 2:end);
    phi_y = angle(sum(conj(Y_y1(:)) .* Y_y2(:)));
    
    % --- 公式(26): 方向余弦 ---
    u_hat = -phi_x * params.lambda / (2 * pi * params.d);
    v_hat = -phi_y * params.lambda / (2 * pi * params.d);
    u_hat = max(min(u_hat, 1), -1);
    v_hat = max(min(v_hat, 1), -1);
    
    % --- 公式(27): 俯仰角/方位角 ---
    sin_psi = min(sqrt(u_hat^2 + v_hat^2), 1);
    theta_val = asind(sin_psi);                     % ψ (俯仰角)
    phi_val   = atan2d(v_hat, u_hat);               % φ (方位角)
    
    % --- 距离估计: FFT bin + 抛物线插值 ---
    nr_frac = double(nr);
    if ir > 1 && ir < Ns
        ir_left  = max(ir - 1, 1);
        ir_right = min(ir + 1, Ns);
        Pl = P(ir_left, iv);
        Pc = P(ir, iv);
        Pr = P(ir_right, iv);
        denom = Pl - 2*Pc + Pr;
        if abs(denom) > eps
            delta_r = 0.5 * (Pl - Pr) / denom;
            delta_r = max(min(delta_r, 0.5), -0.5);
            nr_frac = nr_frac + delta_r;
        end
    end
    Rmax_val = params.c / (2 * delta_f);
    R_val = mod(-params.c * nr_frac / (2 * Ns * delta_f), Rmax_val);
    
    % --- 速度估计: FFT bin + 抛物线插值 ---
    nv_frac = double(nv);
    if iv > 1 && iv < Nv_pad
        iv_left  = max(iv - 1, 1);
        iv_right = min(iv + 1, Nv_pad);
        Pl_v = P(ir, iv_left);
        Pc_v = P(ir, iv);
        Pr_v = P(ir, iv_right);
        denom_v = Pl_v - 2*Pc_v + Pr_v;
        if abs(denom_v) > eps
            delta_v = 0.5 * (Pl_v - Pr_v) / denom_v;
            delta_v = max(min(delta_v, 0.5), -0.5);
            nv_raw_frac = nv_raw + delta_v;
            nv_frac = nv_raw_frac * doppler_scale;
        end
    end
    v_val = params.c * nv_frac / (2 * L * params.Ts * params.fc);
    
    % --- 记录 ---
    detected = detected + 1;
    theta_est(detected) = theta_val;
    phi_est(detected)   = phi_val;
    R_est(detected)     = R_val;
    v_est(detected)     = v_val;
    selected_ir(detected) = ir;
    selected_iv(detected) = nv;
end

% 截断输出
theta_est = theta_est(1:detected);
phi_est   = phi_est(1:detected);
R_est     = R_est(1:detected);
v_est     = v_est(1:detected);

info = struct();
info.detector         = 'rd_phase_difference';
info.detected_targets = detected;
info.Ns = Ns;
info.L  = L;
info.Nv_pad = Nv_pad;
info.n_samp_r = n_samp_r;
info.n_samp_l = n_samp_l;
info.cfg = cfg;
end

% 工程内置周期 Hann 窗，避免对 Signal Processing Toolbox 的强制依赖。
function w = local_periodic_hann(n)
if n <= 1
    w = ones(n, 1);
else
    k = (0:n-1).';
    w = 0.5 - 0.5 * cos(2*pi*k/n);
end
end
