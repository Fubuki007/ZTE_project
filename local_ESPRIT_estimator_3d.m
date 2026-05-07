function [theta_est, phi_est, R_est, v_est, info] = local_ESPRIT_estimator_3d(rx_cube, tx_signal, params)
% LOCAL_ESPRIT_ESTIMATOR_3D 三维局部ESPRIT联合参数估计算法
% 该函数用于通信感知一体化(ISAC)系统中的目标参数估计。
% 核心思想：先通过2D-FFT在距离-多普勒(Range-Doppler)域进行粗搜索，找到峰值候选点；
% 然后在候选点局部提取空间快拍，利用2D-ESPRIT算法进行高精度的俯仰角(theta)和方位角(phi)估计；
% 最后可选择使用抛物线插值进一步细化距离(Range)和速度(Velocity)的估计。
%
% 输入参数:
%   rx_cube   - 接收端数据立方体，维度为 [Mx(x向天线数), My(y向天线数), Ns(子载波数), L(OFDM符号数)]
%   tx_signal - 发射信号
%   params    - 系统参数结构体，包含带宽、载频、天线间距等物理参数
%
% 输出参数:
%   theta_est - 估计的目标俯仰角集合 (度)
%   phi_est   - 估计的目标方位角集合 (度)
%   R_est     - 估计的目标距离集合 (米)
%   v_est     - 估计的目标速度集合 (米/秒)
%   info      - 包含检测信息的结构体

% =========================================================================
% 1. 获取维度与初始化参数
% =========================================================================
[Mx, My, Ns, L] = size(rx_cube);
Q = params.num_targets; % 需要估计的目标数量
delta_f = params.B / Ns; % 子载波间隔 (Hz)

% 加载局部ESPRIT配置参数，如果没有则使用默认值
if isfield(params, 'local_esprit')
    cfg = params.local_esprit;
else
    cfg = struct();
end

% num_candidates: RD域候选峰值数量，通常取目标数的2倍或至少8个，用于后续筛选
if isfield(cfg, 'num_candidates')
    num_candidates = max(2 * Q, round(cfg.num_candidates));
else
    num_candidates = max(2 * Q, 8);
end

% n_samples_range / n_samples_doppler: 局部快拍提取时，在距离/多普勒域采样的点数
if isfield(cfg, 'n_samples_range')
    n_samples_range = min(Ns, max(64, round(cfg.n_samples_range)));
else
    n_samples_range = min(Ns, 512);
end
if isfield(cfg, 'n_samples_doppler')
    n_samples_doppler = min(L, max(16, round(cfg.n_samples_doppler)));
else
    n_samples_doppler = min(L, 64);
end

% rd_nms_r / rd_nms_v: 距离/速度域的非极大值抑制(NMS)窗口大小，防止同一个目标的旁瓣被重复检测
if isfield(cfg, 'rd_nms_r')
    rd_nms_r = max(0, round(cfg.rd_nms_r));
else
    rd_nms_r = 2;
end
if isfield(cfg, 'rd_nms_v')
    rd_nms_v = max(0, round(cfg.rd_nms_v));
else
    rd_nms_v = 2;
end

% 轻量化“去信号相关系数”开关与参数
if isfield(cfg, 'enable_coeff_removal')
    enable_coeff_removal = logical(cfg.enable_coeff_removal);
else
    enable_coeff_removal = false;
end
if isfield(cfg, 'eps_div')
    eps_div = cfg.eps_div;
else
    eps_div = 1e-6;
end
if isfield(cfg, 'coeff_refine_blend')
    coeff_refine_blend = max(0, min(1, cfg.coeff_refine_blend));
else
    coeff_refine_blend = 1.0; % 1:完全采用去系数后的局部估计
end

% =========================================================================
% 2. 信道均衡与 Range-Doppler (RD) 谱计算
% =========================================================================
% 通过点乘发射信号的共轭，消除发射信号的影响，得到等效信道频率响应
rx_eq = rx_cube .* conj(reshape(tx_signal, 1, 1, Ns, L));

% 将所有天线阵元的数据进行非相干累加，提升RD谱的信噪比 (压缩空间维度)
s_sum = squeeze(sum(sum(rx_eq, 1), 2));

% 进行2D-FFT得到 Range-Doppler 谱，并使用 fftshift 将零频移到中心
RD = fftshift(fftshift(fft2(s_sum), 1), 2);
P = abs(RD).^2; % 计算功率谱

% 在RD谱中找到功率最大的前 num_candidates 个候选点的线性索引 idx
[~, idx] = maxk(P(:), min(num_candidates, numel(P)));

% 定义经过 fftshift 后的距离(nr)和多普勒(nv)频点对应的真实频率索引范围
nr_bins = -floor(Ns / 2) : (ceil(Ns / 2) - 1);
nv_bins = -floor(L / 2) : (ceil(L / 2) - 1);

% =========================================================================
% 3. 初始化目标提取过程中的变量
% =========================================================================
selected_r = zeros(1, Q); % 记录已选目标的距离索引
selected_v = zeros(1, Q); % 记录已选目标的速度索引
detected = 0; % 已检测到的目标计数器

theta_est = zeros(1, Q);
phi_est = zeros(1, Q);
R_est = zeros(1, Q);
v_est = zeros(1, Q);
indices = zeros(Q, 2); % 记录目标在RD谱中的 [距离索引, 速度索引]
coeff_refined = false(Q, 1);
coeff_alpha = ones(Q, 1);
coeff_quality = zeros(Q, 1);

% 生成用于提取局部空间快拍的等间隔采样网格
n_idx = round(linspace(1, Ns, n_samples_range));
l_idx = round(linspace(1, L, n_samples_doppler));
n_vec = n_idx(:) - 1;
l_vec = l_idx(:) - 1;

% 是否启用抛物线插值进行分数阶的峰值细化
if isfield(params, 'use_interpolation')
    use_interpolation = logical(params.use_interpolation);
else
    use_interpolation = true;
end

% =========================================================================
% 4. 遍历候选点，提取目标参数
% =========================================================================
for ii = 1:numel(idx)
    if detected >= Q
        break; % 如果已找到足够的目标，则停止搜索
    end
    
    % 将一维索引转换回二维RD谱的行列索引 [ir(距离), iv(速度)]
    [ir, iv] = ind2sub([Ns, L], idx(ii));
    nr = nr_bins(ir);
    nv = nv_bins(iv);
    
    % 非极大值抑制 (NMS): 检查当前候选点是否落在已检测目标的邻域内
    if detected > 0
        if any(abs(nr - selected_r(1:detected)) <= rd_nms_r & abs(nv - selected_v(1:detected)) <= rd_nms_v)
            continue; % 如果是，则认为是同一个目标的旁瓣，跳过当前点
        end
    end

    % ---------------------------------------------------------------------
    % 4.1 提取目标的局部空间快拍 (聚焦操作)
    % ---------------------------------------------------------------------
    % 计算该峰值对应的数字角频率
    omega_r = 2 * pi * nr / Ns;
    omega_v = 2 * pi * nv / L;
    
    % 构造补偿相位矩阵，用于将目标信号“聚焦”到零频
    phase_n = exp(-1j * n_vec * omega_r);
    phase_l = exp(-1j * l_vec * omega_v);
    W = phase_n * phase_l.';

    % 在指定的采样网格上提取等效接收数据
    X_sub = rx_eq(:, :, n_idx, l_idx);
    
    % 将补偿相位应用到数据上并在子载波和符号维度上求和，得到针对该目标的纯空间域快拍
    spatial_snap = sum(sum(X_sub .* reshape(W, 1, 1, numel(n_idx), numel(l_idx)), 3), 4);

    % ---------------------------------------------------------------------
    % 4.2 利用 2D-ESPRIT 算法估计二维角度 (俯仰角 theta 和 方位角 phi)
    % ---------------------------------------------------------------------
    % x方向上的相邻阵元数据对齐 (用于估计 phi_x)
    sx1 = spatial_snap(1:end-1, :);
    sx2 = spatial_snap(2:end, :);
    % y方向上的相邻阵元数据对齐 (用于估计 phi_y)
    sy1 = spatial_snap(:, 1:end-1);
    sy2 = spatial_snap(:, 2:end);
    
    % 通过计算自相关矩阵的相位，得到 x 和 y 方向的阵元间相位差
    phi_x = angle(sum(conj(sx1(:)) .* sx2(:)));
    phi_y = angle(sum(conj(sy1(:)) .* sy2(:)));
    
    % 将相位差转换为方向余弦 (u_hat, v_hat)
    u_hat = -phi_x * params.lambda / (2 * pi * params.d);
    v_hat = -phi_y * params.lambda / (2 * pi * params.d);
    
    % 限制范围在 [-1, 1] 以免产生无效的复数角度
    u_hat = max(min(u_hat, 1), -1);
    v_hat = max(min(v_hat, 1), -1);
    
    % 从方向余弦计算实际的俯仰角 (theta) 和方位角 (phi)
    sin_theta = min(max(sqrt(u_hat^2 + v_hat^2), -1), 1);
    theta_val = asind(sin_theta);
    phi_val = atan2d(v_hat, u_hat);

    % ---------------------------------------------------------------------
    % 4.3 距离与速度细化：默认抛物线插值 + 可选轻量去系数局部2D-DFT细化
    % ---------------------------------------------------------------------
    nr_f = nr;
    nv_f = nv;
    if use_interpolation
        % 距离维抛物线插值
        if ir > 1 && ir < Ns
            pl = P(ir - 1, iv); % 左侧点功率
            pc = P(ir, iv);     % 中心点功率
            pr = P(ir + 1, iv); % 右侧点功率
            den = pl - 2 * pc + pr;
            if abs(den) > eps
                % 计算抛物线顶点偏移量，并限制最大偏移范围在 [-0.5, 0.5]
                nr_f = nr + max(min(0.5 * (pl - pr) / den, 0.5), -0.5);
            end
        end
        
        % 速度维抛物线插值
        if iv > 1 && iv < L
            pl = P(ir, iv - 1); % 上侧点功率
            pc = P(ir, iv);     % 中心点功率
            pr = P(ir, iv + 1); % 下侧点功率
            den = pl - 2 * pc + pr;
            if abs(den) > eps
                nv_f = nv + max(min(0.5 * (pl - pr) / den, 0.5), -0.5);
            end
        end
    end

    % 轻量化引入论文核心思想：去除信号相关系数 a^H(u,v)x 后做局部2D-DFT细化
    if enable_coeff_removal
        % 使用当前角度估计构造方向余弦（与论文中的bin代表方向一致思想）
        u_hat_bin = sind(theta_val) * cosd(phi_val);
        v_hat_bin = sind(theta_val) * sind(phi_val); %#ok<NASGU>

        % 采用正则化除法进行轻量去系数，避免近零放大
        % tx_signal 为 Ns x L，发射天线维在当前实现中已等效折叠，使用均值投影近似 a^H x
        d_eff = mean(tx_signal, 1);
        d_eff = repmat(d_eff, Ns, 1);
        denom = abs(d_eff).^2 + eps_div;
        y_tilde = (s_sum .* conj(d_eff)) ./ denom;

        % alpha缩放保持能量量级（论文式(22)(23)思想的轻量近似）
        p_raw = mean(abs(s_sum(:)).^2);
        p_tilde = mean(abs(y_tilde(:)).^2);
        alpha_hat = 1;
        if p_tilde > 0
            alpha_hat = sqrt(max(p_raw, eps) / max(p_tilde, eps));
        end
        y_tilde = alpha_hat * y_tilde;

        % 对去系数后的序列做一次低开销局部2D-DFT细化
        RD_tilde = fftshift(fftshift(fft2(y_tilde), 1), 2);
        P_tilde = abs(RD_tilde).^2;

        ir_l = max(1, ir-1); ir_h = min(Ns, ir+1);
        iv_l = max(1, iv-1); iv_h = min(L, iv+1);
        local_patch = P_tilde(ir_l:ir_h, iv_l:iv_h);
        [~, local_idx] = max(local_patch(:));
        [dr_i, dv_i] = ind2sub(size(local_patch), local_idx);
        ir_new = ir_l + dr_i - 1;
        iv_new = iv_l + dv_i - 1;
        nr_new = nr_bins(ir_new);
        nv_new = nv_bins(iv_new);

        % 与原估计融合，避免误修正
        nr_f = (1 - coeff_refine_blend) * nr_f + coeff_refine_blend * nr_new;
        nv_f = (1 - coeff_refine_blend) * nv_f + coeff_refine_blend * nv_new;

        coeff_refined(detected + 1) = true;
        coeff_alpha(detected + 1) = alpha_hat;
        coeff_quality(detected + 1) = p_raw / max(p_tilde, eps);
    end
    
    % ---------------------------------------------------------------------
    % 4.4 物理量换算 (将频率索引转为物理距离和速度)
    % ---------------------------------------------------------------------
    % 计算实际的距离 R (使用 mod 处理解模糊，应对超过最大不模糊距离的情况)
    R_val = mod(-params.c * nr_f / (2 * Ns * delta_f), params.c / (2 * delta_f));
    
    % 计算实际的速度 v
    v_val = params.c * nv_f / (2 * L * params.Ts * params.fc);

    % 记录并保存当前检测到的目标参数
    detected = detected + 1;
    selected_r(detected) = nr;
    selected_v(detected) = nv;
    theta_est(detected) = theta_val;
    phi_est(detected) = phi_val;
    R_est(detected) = R_val;
    v_est(detected) = v_val;
    indices(detected, :) = [ir, iv];
end

% =========================================================================
% 5. 截断未使用的预分配空间并返回信息
% =========================================================================
theta_est = theta_est(1:detected);
phi_est = phi_est(1:detected);
R_est = R_est(1:detected);
v_est = v_est(1:detected);

% 打包检测信息，用于后续的性能评估或调试
info = struct();
info.detector = 'local_esprit';
info.detected_targets = detected;
info.indices = indices(1:detected, :);
info.num_candidates = num_candidates;
info.n_samples_range = n_samples_range;
info.n_samples_doppler = n_samples_doppler;
info.use_interpolation = use_interpolation;
info.enable_coeff_removal = enable_coeff_removal;
info.coeff_refined = coeff_refined(1:detected);
info.coeff_alpha = coeff_alpha(1:detected);
info.coeff_quality = coeff_quality(1:detected);
end