function [theta_est, phi_est, R_est, v_est, info] = joint_angle_range_velocity_estimator(rx_cube, tx_signal, params)
% =========================================================================
% JOINT_ANGLE_RANGE_VELOCITY_ESTIMATOR  4D 联合角度-距离-速度估计器
% -------------------------------------------------------------------------
% 参考文献:
%   [1] Z. Xiao, R. Liu, M. Li, Q. Liu and A. L. Swindlehurst,
%       "A Novel Joint Angle-Range-Velocity Estimation Method for MIMO-OFDM
%       ISAC Systems," IEEE TSP, vol. 72, pp. 3805-3819, 2024.
%   [2] 本项目配套整理的四维扩展版算法推导（见文献 zte_project_3d_extracted_clean.txt），
%       将论文中的 1D 接收 ULA 推广到 2D URA (Mx x My)。
%
% 本函数实现是在作者源代码 my_proposed.m + peak_finding.m 的基础上，按照
% 四维接收 (2D 面阵 × 快时间 × 慢时间) 场景做的重写与扩展，流程与论文一致：
%   Step 1: 沿接收空间两维 (mx, my) 做 2D-DFT          → Y_{i,l}(na_x, na_y)
%   Step 2: 对每个角度 bin (na_x, na_y) 计算信号依赖系数 a^H(u,v)·x_i[l]；
%           按论文式 (21)-(23) 点除去系数，并用缩放因子 alpha 保持每个角度
%           bin 的总功率不变，以保护空间域的功率结构
%   Step 3: 沿 fast-time (i) 与 slow-time (l) 做 2D-DFT → Y(na_x, na_y, nr, nv)
%   Step 4: 在 4D 角度-距离-多普勒立方体上做峰值检测（含 4D 非极大值抑制），
%           按论文式 (27) 把索引还原为物理量 (theta, phi, R, v)
%
% 输入:
%   rx_cube   - (Mx, My, Ns, L) 4D 接收数据立方体
%   tx_signal - 发射基带信号，支持两种格式:
%                (a) (Ns, L)                 —— 已合成/预编码后的等效标量发射端
%                                               此时 a^H(u,v)·x_i[l] = x_i[l]
%                (b) (Nt_x, Nt_y, Ns, L)     —— 完整 2D 发射面阵格式
%                                               将对每个 (na_x, na_y) 计算导向矢量
%   params    - 系统参数结构体，必须字段:
%                fc, c, lambda, d, B, Ts, num_targets
%                可选子结构 params.joint_4d 控制 4D DFT 的补零倍数与峰值搜索:
%                  .Na_x_factor   (默认 1，表示 Na_x = factor * Mx)
%                  .Na_y_factor   (默认 1)
%                  .Nr_factor     (默认 1)
%                  .Nv_factor     (默认 1)
%                  .nms_na_x / .nms_na_y / .nms_r / .nms_v  4D NMS 半径
%                  .num_candidates  初筛峰值候选数(默认 max(2Q, 8))
%
% 输出:
%   theta_est, phi_est - 估计的俯仰角/方位角 (度)
%   R_est, v_est       - 估计的距离 (m) / 速度 (m/s)
%   info               - 调试与诊断信息结构体
%
% 维度速查表（与论文保持一致）:
%   Mx, My           接收 URA 两维阵元数
%   Ns               子载波数  (fast-time)
%   L                CPI 内 OFDM 符号数 (slow-time)
%   Na_x, Na_y       空间 DFT 点数 (>= Mx, My)
%   Nr, Nv           fast-time / slow-time DFT 点数
% =========================================================================

% -------------------------------------------------------------------------
% 0. 维度与默认参数
% -------------------------------------------------------------------------
[Mx, My, Ns, L] = size(rx_cube);
Q = params.num_targets;
delta_f = params.B / Ns;   % 子载波间隔 (Hz)

% -------------------------------------------------------------------------
% 配置读取：优先级  params.joint_4d  >  params.joint_fft_3d  >  默认值
%   - joint_4d.*_factor / joint_4d.Na_x 等绝对字段都接受
%   - joint_fft_3d.Na_x/Na_y/Nr/Nv (项目历史字段) 会被当作绝对补零点数
%   - joint_fft_3d.nms_guard = [ax ay r v] 若存在，映射为四个 nms_* 字段
% -------------------------------------------------------------------------
cfg = struct();

% 1) 历史字段兼容（低优先级，先写入）
if isfield(params, 'joint_fft_3d')
    j3 = params.joint_fft_3d;
    if isfield(j3, 'Na_x'),           cfg.Na_x           = j3.Na_x;           end
    if isfield(j3, 'Na_y'),           cfg.Na_y           = j3.Na_y;           end
    if isfield(j3, 'Nr'),             cfg.Nr             = j3.Nr;             end
    if isfield(j3, 'Nv'),             cfg.Nv             = j3.Nv;             end
    if isfield(j3, 'num_candidates'), cfg.num_candidates = j3.num_candidates; end
    if isfield(j3, 'nms_guard') && numel(j3.nms_guard) >= 4
        cfg.nms_na_x = j3.nms_guard(1);
        cfg.nms_na_y = j3.nms_guard(2);
        cfg.nms_r    = j3.nms_guard(3);
        cfg.nms_v    = j3.nms_guard(4);
    end
end

% 2) 新字段（高优先级，可覆盖历史配置）
if isfield(params, 'joint_4d')
    f = fieldnames(params.joint_4d);
    for k = 1:numel(f)
        cfg.(f{k}) = params.joint_4d.(f{k});
    end
end

% 3) 默认值兜底
if ~isfield(cfg, 'Na_x_factor'),    cfg.Na_x_factor    = 1;          end
if ~isfield(cfg, 'Na_y_factor'),    cfg.Na_y_factor    = 1;          end
if ~isfield(cfg, 'Nr_factor'),      cfg.Nr_factor      = 1;          end
if ~isfield(cfg, 'Nv_factor'),      cfg.Nv_factor      = 1;          end
if ~isfield(cfg, 'nms_na_x'),       cfg.nms_na_x       = 1;          end
if ~isfield(cfg, 'nms_na_y'),       cfg.nms_na_y       = 1;          end
if ~isfield(cfg, 'nms_r'),          cfg.nms_r          = 2;          end
if ~isfield(cfg, 'nms_v'),          cfg.nms_v          = 2;          end
if ~isfield(cfg, 'num_candidates'), cfg.num_candidates = max(2*Q, 8); end

% 绝对字段优先，否则用 factor 推导
if isfield(cfg, 'Na_x'), Na_x = cfg.Na_x; else, Na_x = cfg.Na_x_factor * Mx; end
if isfield(cfg, 'Na_y'), Na_y = cfg.Na_y; else, Na_y = cfg.Na_y_factor * My; end
if isfield(cfg, 'Nr'),   Nr   = cfg.Nr;   else, Nr   = cfg.Nr_factor   * Ns; end
if isfield(cfg, 'Nv'),   Nv   = cfg.Nv;   else, Nv   = cfg.Nv_factor   * L;  end

% 用户传入非法值的安全兜底
Na_x = max(Na_x, Mx);
Na_y = max(Na_y, My);
Nr   = max(Nr,   Ns);
Nv   = max(Nv,   L);

% 简单的内存护栏，避免四维补零时一脚踩爆
cube_elems = Na_x * Na_y * Nr * Nv;
if cube_elems > 2e8
    warning(['JOINT_4D: 4D 谱大小 %d 过大(约 %.1f GB 复数)，建议降低补零倍数。'], ...
        cube_elems, cube_elems*16/1e9);
end

% -------------------------------------------------------------------------
% 1. Step 1: 沿接收两维 (mx, my) 做 2D-DFT (对应论文式 (11))
%    Y_{i,l}(na_x, na_y) = (1/(Mx*My)) * sum_{mx,my} y(mx,my,i,l) *
%                          exp(-j mx·omega_a_x(na_x)) * exp(-j my·omega_a_y(na_y))
% -------------------------------------------------------------------------
Y = fft(rx_cube, Na_x, 1);          % (Na_x, My, Ns, L)
Y = fft(Y,       Na_y, 2);          % (Na_x, Na_y, Ns, L)
Y = Y / (Mx * My);                  % 归一化，符合论文式 (11) 的 1/(Mx·My)
Y = fftshift(fftshift(Y, 1), 2);    % 把零频移到中心，便于后续 bin 索引换算

% -------------------------------------------------------------------------
% 2. Step 2: 去信号依赖系数 + scaling factor (论文式 (21)-(23))
%    对每个角度 bin (na_x, na_y):
%      num   = sum_{i,l} |Y_{i,l} / (a^H(u_na, v_na) · x_i[l])|^2
%      den   = sum_{i,l} |Y_{i,l}|^2
%      alpha = sqrt(num / den)
%      y_tilde = Y / (alpha · a^H(u_na, v_na) · x_i[l])
%    满足 sum|y_tilde|^2 = sum|Y|^2，即不改变不同角度 bin 间的功率关系。
% -------------------------------------------------------------------------

% 角度 bin 对应的数字频率（论文式 (12)(13)），这里是 fftshift 之后的中心化索引
na_x_vec = (-floor(Na_x/2) : (ceil(Na_x/2) - 1)).';   % (Na_x, 1)
na_y_vec = (-floor(Na_y/2) : (ceil(Na_y/2) - 1)).';   % (Na_y, 1)

% 把角度 bin 映射到方向余弦 (论文式 (19))
%   u_na = -na_x·λ / (d·Na_x),   v_na = -na_y·λ / (d·Na_y)
u_na = -na_x_vec * params.lambda / (params.d * Na_x);  % (Na_x, 1)
v_na = -na_y_vec * params.lambda / (params.d * Na_y);  % (Na_y, 1)

% --- 计算 mixed_coef(na_x, na_y, i, l) = a^H(u_na, v_na) · x_i[l] ---
% 分两种模式处理 tx_signal：
tx_dims = ndims(tx_signal);
if isequal(size(tx_signal), [Ns, L])
    % 模式 A: 发射端已合成为标量, a^H · x 与角度 bin 无关, mixed 直接退化为 tx_signal
    mixed_coef = reshape(tx_signal, 1, 1, Ns, L);   % 广播维
    use_full_steering = false;
elseif tx_dims == 4 && size(tx_signal, 3) == Ns && size(tx_signal, 4) == L
    % 模式 B: tx_signal = (Nt_x, Nt_y, Ns, L) 完整 2D 发射面阵格式
    Nt_x = size(tx_signal, 1);
    Nt_y = size(tx_signal, 2);

    % 构造 2D URA 发射 steering vector (论文式 (4)(5) 的共轭转置后)：
    %   a_x(u) = exp(-j·2π·d·u/λ · (0:Nt_x-1)),  a_y(v) 同理
    %   a(u,v) = a_x(u) ⊗ a_y(v)
    % a^H(u,v) · x = sum_{pz, py} conj(a(u,v))_{pz,py} · x_{pz,py,i,l}
    kx = 2*pi*params.d/params.lambda;
    Ax = exp(-1j * kx * (0:Nt_x-1).' * u_na.');   % (Nt_x, Na_x)
    Ay = exp(-1j * kx * (0:Nt_y-1).' * v_na.');   % (Nt_y, Na_y)

    % 内积：mixed(na_x, na_y, i, l) = sum_{pz,py} conj(a_x(pz,na_x))·conj(a_y(py,na_y)) · x(pz,py,i,l)
    % 用两次张量 contraction 实现
    %   Tmp(na_x, py, i, l) = sum_{pz} conj(Ax(pz, na_x)) · x(pz, py, i, l)
    Tmp = zeros(Na_x, Nt_y, Ns, L);
    for i = 1:Ns
        for l = 1:L
            Tmp(:, :, i, l) = Ax' * reshape(tx_signal(:, :, i, l), Nt_x, Nt_y);
        end
    end
    %   mixed(na_x, na_y, i, l) = sum_{py} Tmp(na_x, py, i, l) · conj(Ay(py, na_y))
    mixed_coef = zeros(Na_x, Na_y, Ns, L);
    for i = 1:Ns
        for l = 1:L
            mixed_coef(:, :, i, l) = reshape(Tmp(:, :, i, l), Na_x, Nt_y) * conj(Ay);
        end
    end
    use_full_steering = true;
else
    error('tx_signal 维度非法: 仅支持 (Ns, L) 或 (Nt_x, Nt_y, Ns, L)');
end

% 对应论文式 (21) 的点除；为避免除零，使用正则化
eps_div = 1e-12;
nonzero_mask = abs(mixed_coef) > eps_div;
A_div = Y;    % 先拷贝，零系数处保留原 Y 的值（对应论文 (21) 的分支选择）
A_div(nonzero_mask) = Y(nonzero_mask) ./ mixed_coef(nonzero_mask);

% 计算每个角度 bin 的 scaling factor alpha_{na_x, na_y} (论文式 (23))
%   numerator   = sum_{i,l} |Y / mixed|^2  (仅在 mixed != 0 的点上)
%   denominator = sum_{i,l} |Y|^2          (同上)
numerator   = sum(sum(abs(A_div).^2 .* nonzero_mask, 3), 4);   % (Na_x, Na_y)
denominator = sum(sum(abs(Y).^2     .* nonzero_mask, 3), 4);   % (Na_x, Na_y)
alpha_bin = sqrt(max(numerator, eps) ./ max(denominator, eps));  % (Na_x, Na_y)

% y_tilde = A_div / alpha  (按论文式 (21) 保护空间域功率结构)
y_tilde = A_div ./ reshape(alpha_bin, Na_x, Na_y, 1, 1);

% -------------------------------------------------------------------------
% 3. Step 3: 沿 fast-time / slow-time 做 2D-DFT (论文式 (25))
%    Y(na_x, na_y, nr, nv) = (1/(Ns·L)) * sum_{i,l} y_tilde(na_x,na_y,i,l)
%                            * exp(-j i·omega_r(nr)) * exp(-j l·omega_v(nv))
% -------------------------------------------------------------------------
Ycube = fft(y_tilde, Nr, 3);      % 快时间 DFT → 距离
Ycube = fft(Ycube,   Nv, 4);      % 慢时间 DFT → 多普勒
Ycube = Ycube / (Ns * L);         % 归一化
Ycube = fftshift(Ycube, 4);       % 只对多普勒 shift（距离 ω_r 单边为负，不 shift）
P = abs(Ycube).^2;                 % 4D 功率谱 (Na_x, Na_y, Nr, Nv)

% -------------------------------------------------------------------------
% 4. Step 4: 4D 峰值检测 + 非极大值抑制 (论文算法1 step 5)
% -------------------------------------------------------------------------
nr_vec = (0 : Nr - 1).';                                   % fast-time 未 shift
nv_vec = (-floor(Nv/2) : (ceil(Nv/2) - 1)).';              % 已 shift 的多普勒索引

num_cand = min(cfg.num_candidates, numel(P));
[~, idx_all] = maxk(P(:), num_cand);

theta_est = zeros(1, Q);
phi_est   = zeros(1, Q);
R_est     = zeros(1, Q);
v_est     = zeros(1, Q);
indices4  = zeros(Q, 4);  % [ia_x, ia_y, ir, iv]
detected  = 0;

Rmax = params.c / (2 * delta_f);  % 最大不模糊距离，用于后续折叠

for kk = 1:numel(idx_all)
    if detected >= Q
        break;
    end
    [ia_x, ia_y, ir, iv] = ind2sub([Na_x, Na_y, Nr, Nv], idx_all(kk));

    % 4D NMS：落入已检测目标邻域则视为旁瓣，跳过
    if detected > 0
        da = abs(ia_x - indices4(1:detected, 1));
        db = abs(ia_y - indices4(1:detected, 2));
        dc = abs(ir   - indices4(1:detected, 3));
        dd = abs(iv   - indices4(1:detected, 4));
        if any(da <= cfg.nms_na_x & db <= cfg.nms_na_y & ...
               dc <= cfg.nms_r    & dd <= cfg.nms_v)
            continue;
        end
    end

    % ---- 按论文式 (27) 反演物理参数 ----
    % 方向余弦（fftshift 后的中心化索引）
    na_x_here = na_x_vec(ia_x);
    na_y_here = na_y_vec(ia_y);
    u_est = -na_x_here * params.lambda / (params.d * Na_x);
    v_est_dir = -na_y_here * params.lambda / (params.d * Na_y);

    % 数值保护，防止 sqrt/atan2 出界
    u_est     = max(min(u_est,     1), -1);
    v_est_dir = max(min(v_est_dir, 1), -1);
    sin_theta = min(sqrt(u_est^2 + v_est_dir^2), 1);

    theta_val = asind(sin_theta);
    phi_val   = atan2d(v_est_dir, u_est);

    % 距离：本项目建模用 omega_r = -4π·Δf·R/c (负号)，DFT 峰值出现在 nr ∈ [0, Nr-1] 上，
    % 对应论文式 (27e) 的 R = -c·nr / (2·Nr·Δf) 做 mod 折叠以保证 R ∈ [0, Rmax)
    nr_here = nr_vec(ir);
    R_val = mod(-params.c * nr_here / (2 * Nr * delta_f), Rmax);

    % 速度：omega_v = 4π·T·v·fc/c 正号，对应 v = c·nv / (2·Nv·T·fc)，nv 已 shift
    nv_here = nv_vec(iv);
    v_val = params.c * nv_here / (2 * Nv * params.Ts * params.fc);

    % ---- 保存 ----
    detected = detected + 1;
    theta_est(detected) = theta_val;
    phi_est(detected)   = phi_val;
    R_est(detected)     = R_val;
    v_est(detected)     = v_val;
    indices4(detected, :) = [ia_x, ia_y, ir, iv];
end

% -------------------------------------------------------------------------
% 5. 截断无效位并输出诊断信息
% -------------------------------------------------------------------------
theta_est = theta_est(1:detected);
phi_est   = phi_est(1:detected);
R_est     = R_est(1:detected);
v_est     = v_est(1:detected);

info = struct();
info.detector         = 'joint_arv_4d';
info.detected_targets = detected;
info.indices4         = indices4(1:detected, :);
info.Na_x             = Na_x;
info.Na_y             = Na_y;
info.Nr               = Nr;
info.Nv               = Nv;
info.alpha_bin_mean   = mean(alpha_bin(:));
info.alpha_bin_max    = max(alpha_bin(:));
info.use_full_steering= use_full_steering;
info.num_candidates   = num_cand;
end
