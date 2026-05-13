function [theta_est, phi_est, R_est, v_est, info] = joint_angle_range_velocity_estimator(rx_cube, tx_signal, params)
% =========================================================================
% JOINT_ANGLE_RANGE_VELOCITY_ESTIMATOR  4D 联合角度-距离-速度估计器
% -------------------------------------------------------------------------
% 参考文献:
%！！！此为还原原作者代码的流程，由于运行时间太长已被改用为joint_es_fast函数，此函数未实际调用！！！
%   [1] Z. Xiao, R. Liu, M. Li, Q. Liu and A. L. Swindlehurst,
%       "A Novel Joint Angle-Range-Velocity Estimation Method for MIMO-OFDM
%       ISAC Systems," IEEE TSP, vol. 72, pp. 3805-3819, 2024.
%   [2] 本项目配套整理的四维扩展版算法推导 (zte_project_3d_extracted_clean.txt),
%       将论文中的 1D 接收 ULA 推广到 2D URA (Mx x My).
%
% 本函数基于作者源代码 my_proposed.m + peak_finding.m 的骨架, 扩展到 4D
% (2D 面阵 × 快时间 × 慢时间) 场景. 流程完全对齐论文 Algorithm 1:
%   Step 1: 沿接收空间两维 (mx, my) 做 2D-DFT          → Y_{i,l}(na_x, na_y)
%   Step 2: 对每个角度 bin (na_x, na_y) 计算信号依赖系数 a^H(u,v)·x_i[l];
%           按论文式 (21)-(23) 点除去系数, 并用缩放因子 alpha 保持每个角度
%           bin 的总功率不变, 以保护空间域的功率结构
%   Step 3: 沿 fast-time (i) 与 slow-time (l) 做 2D-DFT → Y(na_x, na_y, nr, nv)
%   Step 4: 在 4D 角度-距离-多普勒立方体上做峰值检测 (含 4D 非极大值抑制),
%           按论文式 (27) 把索引还原为物理量 (theta, phi, R, v)
%
% 内存优化 (避免一次性分配超大 4D double 数组):
%   - Step 3 改为 "按角度 bin 逐切片 2D-FFT" 的流式循环, 每次只分配 (Nr, Nv)
%     大小的 single 精度切片; 全局只维护每个切片的 top-K 局部峰值作为候选池.
%   - Step 1 结束后显式释放原始 rx_cube 和 Y_spatial 的中间变量.
%   - 峰值候选池内部使用 single 精度存储, 最终反演物理参数时再转回 double.
%
% 输入:
%   rx_cube   - (Mx, My, Ns, L) 4D 接收数据立方体
%   tx_signal - 发射基带信号, 支持两种格式:
%                (a) (Ns, L)                 —— 已合成/预编码后的等效标量发射端,
%                                               此时 a^H(u,v)·x_i[l] = x_i[l]
%                (b) (Nt_x, Nt_y, Ns, L)     —— 完整 2D 发射面阵格式,
%                                               将对每个 (na_x, na_y) 计算导向矢量
%   params    - 系统参数结构体, 必须字段:
%                fc, c, lambda, d, B, Ts, num_targets
%                可选子结构 params.joint_4d 控制 4D DFT 的补零倍数与峰值搜索:
%                  .Na_x_factor   (默认 1, 表示 Na_x = factor * Mx)
%                  .Na_y_factor   (默认 1)
%                  .Nr_factor     (默认 1)
%                  .Nv_factor     (默认 1)
%                  .Na_x / .Na_y / .Nr / .Nv   直接指定绝对点数 (优先级更高)
%                  .nms_na_x / .nms_na_y / .nms_r / .nms_v  4D NMS 半径
%                  .num_candidates  初筛峰值候选数 (默认 max(2Q, 8))
%                  .local_topk      每个角度 bin 保留的局部峰值数 (默认 8)
%                  .memory_cap_gb   4D 立方体硬上限 (默认 8 GB, 超过直接报错)
%                  .use_double_power  峰值池使用 double (默认 false, 即 single)
%                兼容字段 params.joint_fft_3d.* (老项目字段, 优先级低于 joint_4d)
%
% 输出:
%   theta_est, phi_est - 估计的俯仰角/方位角 (度)
%   R_est, v_est       - 估计的距离 (m) / 速度 (m/s)
%   info               - 调试与诊断信息结构体
% =========================================================================

% -------------------------------------------------------------------------
% 0. 维度与默认参数
% -------------------------------------------------------------------------
[Mx, My, Ns, L] = size(rx_cube);
Q = params.num_targets;
delta_f = params.B / Ns;

% -------------------------------------------------------------------------
% 配置读取: 优先级  params.joint_4d  >  params.joint_fft_3d  >  默认值
% -------------------------------------------------------------------------
cfg = struct();
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
if isfield(params, 'joint_4d')
    f = fieldnames(params.joint_4d);
    for k = 1:numel(f)
        cfg.(f{k}) = params.joint_4d.(f{k});
    end
end

if ~isfield(cfg, 'Na_x_factor'),     cfg.Na_x_factor     = 1;          end
if ~isfield(cfg, 'Na_y_factor'),     cfg.Na_y_factor     = 1;          end
if ~isfield(cfg, 'Nr_factor'),       cfg.Nr_factor       = 1;          end
if ~isfield(cfg, 'Nv_factor'),       cfg.Nv_factor       = 1;          end
if ~isfield(cfg, 'nms_na_x'),        cfg.nms_na_x        = 1;          end
if ~isfield(cfg, 'nms_na_y'),        cfg.nms_na_y        = 1;          end
if ~isfield(cfg, 'nms_r'),           cfg.nms_r           = 2;          end
if ~isfield(cfg, 'nms_v'),           cfg.nms_v           = 2;          end
if ~isfield(cfg, 'num_candidates'),  cfg.num_candidates  = max(2*Q, 8); end
if ~isfield(cfg, 'local_topk'),      cfg.local_topk      = 8;          end
if ~isfield(cfg, 'memory_cap_gb'),   cfg.memory_cap_gb   = 8;          end
if ~isfield(cfg, 'use_double_power'),cfg.use_double_power = false;     end

if isfield(cfg, 'Na_x'), Na_x = cfg.Na_x; else, Na_x = cfg.Na_x_factor * Mx; end
if isfield(cfg, 'Na_y'), Na_y = cfg.Na_y; else, Na_y = cfg.Na_y_factor * My; end
if isfield(cfg, 'Nr'),   Nr   = cfg.Nr;   else, Nr   = cfg.Nr_factor   * Ns; end
if isfield(cfg, 'Nv'),   Nv   = cfg.Nv;   else, Nv   = cfg.Nv_factor   * L;  end
Na_x = max(Na_x, Mx);
Na_y = max(Na_y, My);
Nr   = max(Nr,   Ns);
Nv   = max(Nv,   L);

% -------------------------------------------------------------------------
% 内存护栏: 检测最大中间数组, 超限直接报错并给出调参建议
% -------------------------------------------------------------------------
bytes_complex = 16;      % complex double
bytes_single_power = 4;  % single 精度功率谱
mem_spatial = Na_x * Na_y * Ns * L * bytes_complex;     % Step 1/2 的中间立方体
mem_perslice = Nr * Nv * bytes_single_power;             % Step 3 每个切片
mem_peak = max(mem_spatial, mem_perslice);
mem_cap = cfg.memory_cap_gb * 1e9;

if mem_peak > mem_cap
    error('JOINT_ARV:MemoryCap', ...
        ['4D 立方体峰值内存 %.2f GB 超过 memory_cap_gb=%.1f GB.\n', ...
         '维度: Na_x=%d, Na_y=%d, Ns=%d, L=%d, Nr=%d, Nv=%d\n', ...
         '建议: 降低 spatial_pad_factor / doppler_pad_factor, ', ...
         '或者调大 params.joint_4d.memory_cap_gb.'], ...
        mem_peak/1e9, cfg.memory_cap_gb, Na_x, Na_y, Ns, L, Nr, Nv);
end

% -------------------------------------------------------------------------
% 1. Step 1: 沿接收两维 (mx, my) 做 2D-DFT (论文式 (11))
%    Y_{i,l}(na_x, na_y) = (1/(Mx*My)) * sum_{mx,my} y(mx,my,i,l)
%                          * exp(-j mx·ω_ax(na_x)) * exp(-j my·ω_ay(na_y))
% -------------------------------------------------------------------------
Y_spatial = fft(rx_cube, Na_x, 1);       % (Na_x, My, Ns, L)
Y_spatial = fft(Y_spatial, Na_y, 2);     % (Na_x, Na_y, Ns, L)
Y_spatial = Y_spatial / (Mx * My);        % 对齐论文式 (11) 的 1/(Mx·My)
Y_spatial = fftshift(fftshift(Y_spatial, 1), 2);  % 零频移到中心

% -------------------------------------------------------------------------
% 2. Step 2: 去信号依赖系数 + scaling factor (论文式 (21)-(23))
% -------------------------------------------------------------------------
na_x_vec = (-floor(Na_x/2) : (ceil(Na_x/2) - 1)).';   % (Na_x, 1)
na_y_vec = (-floor(Na_y/2) : (ceil(Na_y/2) - 1)).';   % (Na_y, 1)
u_na = -na_x_vec * params.lambda / (params.d * Na_x); % (Na_x, 1)
v_na = -na_y_vec * params.lambda / (params.d * Na_y); % (Na_y, 1)

tx_dims = ndims(tx_signal);
if isequal(size(tx_signal), [Ns, L])
    % 模式 A: tx 已合成为标量, mixed_coef 退化为 tx_signal (广播到 4D)
    use_full_steering = false;

    nonzero_mask_l = abs(tx_signal) > 1e-12;   % (Ns, L) 共享到所有角度 bin

    % 为了把除法向量化, 直接对 Y_spatial 的 (:, :, i, l) 切片做 ./
    % 注: mixed_coef(na_x, na_y, i, l) = tx_signal(i, l), 与角度 bin 无关
    mixed_bc = reshape(tx_signal, 1, 1, Ns, L);                 % 广播形状
    A_div = Y_spatial;
    % 只在非零点上做除, 零点保持原值 (对应论文式 (21) 分支)
    safe_mixed = mixed_bc;
    safe_mixed(~nonzero_mask_l) = 1;                 % 先避免除零; 后续不计入统计
    A_div = A_div ./ safe_mixed;

    % 统计分子/分母时只在 nonzero 处累加 (论文式 (23))
    mask_bc = reshape(nonzero_mask_l, 1, 1, Ns, L);
    numerator   = sum(sum(abs(A_div).^2 .* mask_bc, 3), 4);     % (Na_x, Na_y)
    denominator = sum(sum(abs(Y_spatial).^2 .* mask_bc, 3), 4); % (Na_x, Na_y)
else
    % 模式 B: 完整 2D 发射面阵 tx_signal = (Nt_x, Nt_y, Ns, L)
    use_full_steering = true;
    if ~(tx_dims == 4 && size(tx_signal, 3) == Ns && size(tx_signal, 4) == L)
        error('tx_signal 维度非法: 仅支持 (Ns, L) 或 (Nt_x, Nt_y, Ns, L)');
    end
    Nt_x = size(tx_signal, 1);
    Nt_y = size(tx_signal, 2);
    kx = 2*pi*params.d/params.lambda;
    % conj(a_tx) 在 u_na 处: exp(-j·kx·nx·u_na), 即 Ax 本身就是 conj(a_tx)
    Ax = exp(-1j * kx * (0:Nt_x-1).' * u_na.');   % (Nt_x, Na_x)
    Ay = exp(-1j * kx * (0:Nt_y-1).' * v_na.');   % (Nt_y, Na_y)

    % 小心内存: 此时 mixed_coef 是 (Na_x, Na_y, Ns, L), 和 Y_spatial 同量级
    % mixed_coef(na_x, na_y, i, l) = a^H(θ_{na}) · x_i[l]
    %   = Σ_nx Σ_ny conj(a_tx(nx,ny)) · x(nx,ny,i,l)
    %   = (Ax.' * x) * Ay   (转置不共轭, 因为 Ax 本身已经是 conj(a_tx))
    mixed_coef = zeros(Na_x, Na_y, Ns, L, 'like', Y_spatial);
    Tmp = zeros(Na_x, Nt_y, Ns, L, 'like', Y_spatial);
    for i = 1:Ns
        for l = 1:L
            Tmp(:, :, i, l) = Ax.' * tx_signal(:, :, i, l);
        end
    end
    for i = 1:Ns
        for l = 1:L
            mixed_coef(:, :, i, l) = reshape(Tmp(:, :, i, l), Na_x, Nt_y) * Ay;
        end
    end
    clear Tmp;

    eps_div = 1e-12;
    nonzero_mask = abs(mixed_coef) > eps_div;
    A_div = Y_spatial;
    safe_mixed = mixed_coef;
    safe_mixed(~nonzero_mask) = 1;
    A_div = A_div ./ safe_mixed;
    clear safe_mixed mixed_coef;

    numerator   = sum(sum(abs(A_div).^2 .* nonzero_mask, 3), 4);
    denominator = sum(sum(abs(Y_spatial).^2 .* nonzero_mask, 3), 4);
    clear nonzero_mask;
end

alpha_bin = sqrt(max(numerator, eps) ./ max(denominator, eps));   % (Na_x, Na_y)
y_tilde = A_div ./ reshape(alpha_bin, Na_x, Na_y, 1, 1);           % (Na_x, Na_y, Ns, L)
clear A_div Y_spatial;

% -------------------------------------------------------------------------
% 3. Step 3: 沿 fast-time / slow-time 做 2D-DFT (论文式 (25))
%    —— 流式实现: 按 (na_x, na_y) 逐切片 2D-FFT, 只保留 top-K 局部峰值,
%       避免一次性构造 Na_x × Na_y × Nr × Nv 的大数组
%    —— 同时保存峰值相邻 bin 的功率, 用于后续二次插值
% -------------------------------------------------------------------------
local_topk = max(1, round(cfg.local_topk));
total_cand = Na_x * Na_y * local_topk;

% 候选池: 记录每个切片 top-K 的 (na_x, na_y, ir, iv, power, 邻域功率)
cand_na_x = zeros(total_cand, 1, 'uint32');
cand_na_y = zeros(total_cand, 1, 'uint32');
cand_ir   = zeros(total_cand, 1, 'uint32');
cand_iv   = zeros(total_cand, 1, 'uint32');
if cfg.use_double_power
    cand_pow = zeros(total_cand, 1, 'double');
    % 距离维邻域: [ir-1, ir+1] 的功率
    cand_pow_r_left  = zeros(total_cand, 1, 'double');
    cand_pow_r_right = zeros(total_cand, 1, 'double');
    % 多普勒维邻域: [iv-1, iv+1] 的功率
    cand_pow_v_left  = zeros(total_cand, 1, 'double');
    cand_pow_v_right = zeros(total_cand, 1, 'double');
else
    cand_pow = zeros(total_cand, 1, 'single');
    cand_pow_r_left  = zeros(total_cand, 1, 'single');
    cand_pow_r_right = zeros(total_cand, 1, 'single');
    cand_pow_v_left  = zeros(total_cand, 1, 'single');
    cand_pow_v_right = zeros(total_cand, 1, 'single');
end
cand_cnt = 0;

for ia_x = 1:Na_x
    for ia_y = 1:Na_y
        % 提取 (Ns, L) 切片, 做 (Nr, Nv)-点 2D-FFT
        slice_il = reshape(y_tilde(ia_x, ia_y, :, :), Ns, L);
        S = fft(slice_il, Nr, 1);       % (Nr, L)
        S = fft(S, Nv, 2);              % (Nr, Nv)
        S = fftshift(S, 2);             % 多普勒 shift 到中心, 距离不 shift
        if cfg.use_double_power
            P2 = abs(S).^2;
        else
            P2 = single(abs(S).^2);
        end

        % 切片内取 top-K
        [topv, topidx] = maxk(P2(:), min(local_topk, numel(P2)));
        [ir_list, iv_list] = ind2sub([Nr, Nv], topidx);

        n_add = numel(topv);
        rng_w = cand_cnt + (1:n_add);
        cand_na_x(rng_w) = ia_x;
        cand_na_y(rng_w) = ia_y;
        cand_ir(rng_w)   = ir_list;
        cand_iv(rng_w)   = iv_list;
        cand_pow(rng_w)  = topv;

        % 保存距离/多普勒维邻域功率 (循环边界处理)
        for kk = 1:n_add
            ir_k = ir_list(kk);
            iv_k = iv_list(kk);
            % 距离维邻域 (循环)
            ir_left  = mod(ir_k - 2, Nr) + 1;
            ir_right = mod(ir_k, Nr) + 1;
            cand_pow_r_left(cand_cnt + kk)  = P2(ir_left, iv_k);
            cand_pow_r_right(cand_cnt + kk) = P2(ir_right, iv_k);
            % 多普勒维邻域 (循环)
            iv_left  = mod(iv_k - 2, Nv) + 1;
            iv_right = mod(iv_k, Nv) + 1;
            cand_pow_v_left(cand_cnt + kk)  = P2(ir_k, iv_left);
            cand_pow_v_right(cand_cnt + kk) = P2(ir_k, iv_right);
        end
        cand_cnt = cand_cnt + n_add;
    end
end
clear y_tilde;

cand_na_x = cand_na_x(1:cand_cnt);
cand_na_y = cand_na_y(1:cand_cnt);
cand_ir   = cand_ir(1:cand_cnt);
cand_iv   = cand_iv(1:cand_cnt);
cand_pow  = cand_pow(1:cand_cnt);
cand_pow_r_left  = cand_pow_r_left(1:cand_cnt);
cand_pow_r_right = cand_pow_r_right(1:cand_cnt);
cand_pow_v_left  = cand_pow_v_left(1:cand_cnt);
cand_pow_v_right = cand_pow_v_right(1:cand_cnt);

% -------------------------------------------------------------------------
% 4. Step 4: 全局排序 + 4D NMS + 物理量反演
%    角度精化: 借鉴 local_ESPRIT 思路, 对每个候选目标回到原始 rx_cube,
%    利用粗检测的距离/多普勒信息做相位补偿聚焦, 提取空间快拍后用
%    2D-ESPRIT 精估角度. 距离/速度仍用 FFT + 抛物线插值.
% -------------------------------------------------------------------------
num_cand = min(cfg.num_candidates, cand_cnt);
[~, global_order] = maxk(cand_pow, num_cand);

nr_vec = (0 : Nr - 1).';                                   % fast-time 未 shift
nv_vec = (-floor(Nv/2) : (ceil(Nv/2) - 1)).';              % 多普勒已 shift
Rmax = params.c / (2 * delta_f);

% 是否启用插值
use_interp = true;
if isfield(params, 'use_interpolation')
    use_interp = params.use_interpolation;
end

% ESPRIT 精化所需的局部采样参数
if isfield(params, 'local_esprit') && isfield(params.local_esprit, 'n_samples_range')
    n_samp_r = min(Ns, max(64, params.local_esprit.n_samples_range));
else
    n_samp_r = min(Ns, 512);
end
if isfield(params, 'local_esprit') && isfield(params.local_esprit, 'n_samples_doppler')
    n_samp_l = min(L, max(16, params.local_esprit.n_samples_doppler));
else
    n_samp_l = min(L, 64);
end
% 等间隔采样网格
esprit_n_idx = round(linspace(1, Ns, n_samp_r));
esprit_l_idx = round(linspace(1, L, n_samp_l));
esprit_n_vec = esprit_n_idx(:) - 1;   % 0-based 子载波索引
esprit_l_vec = esprit_l_idx(:) - 1;   % 0-based 符号索引

% 预计算信道均衡数据 (用于 ESPRIT 空间快拍提取)
% rx_eq(mx, my, i, l) = rx_cube .* conj(tx_signal) 去除发射信号影响
sz_tx = size(tx_signal);
if isequal(sz_tx, [Ns, L])
    % 标量发射端: 直接点乘共轭
    rx_eq = rx_cube .* conj(reshape(tx_signal, 1, 1, Ns, L));
else
    % MIMO 发射端: 用发射信号各天线求和后的等效标量做均衡
    % rx_eq(mx, my, i, l) ≈ rx(mx,my,i,l) * conj(sum(tx)) / |sum(tx)|
    tx_sum = squeeze(sum(sum(tx_signal, 1), 2));   % (Ns, L)
    tx_sum_norm = tx_sum ./ max(abs(tx_sum), eps);
    rx_eq = rx_cube .* conj(reshape(tx_sum_norm, 1, 1, Ns, L));
end

theta_est = zeros(1, Q);
phi_est   = zeros(1, Q);
R_est     = zeros(1, Q);
v_est     = zeros(1, Q);
indices4  = zeros(Q, 4);
detected  = 0;

for kk = 1:numel(global_order)
    if detected >= Q
        break;
    end
    ic = global_order(kk);
    ia_x = double(cand_na_x(ic));
    ia_y = double(cand_na_y(ic));
    ir   = double(cand_ir(ic));
    iv   = double(cand_iv(ic));

    % 4D 非极大值抑制
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

    % =====================================================================
    % 角度精化: 2D-ESPRIT (借鉴 local_ESPRIT_estimator_3d)
    % =====================================================================
    % 从粗检测的距离/多普勒 bin 索引计算数字角频率
    nr_here = nr_vec(ir);
    nv_here = nv_vec(iv);
    omega_r_coarse = 2 * pi * nr_here / Nr;
    omega_v_coarse = 2 * pi * nv_here / Nv;

    % 构造相位补偿矩阵, 将目标信号聚焦到零频
    phase_n = exp(-1j * esprit_n_vec * omega_r_coarse);
    phase_l = exp(-1j * esprit_l_vec * omega_v_coarse);
    W_focus = phase_n * phase_l.';   % (n_samp_r, n_samp_l)

    % 提取局部均衡数据并应用聚焦, 在子载波和符号维求和得到空间快拍
    X_sub = rx_eq(:, :, esprit_n_idx, esprit_l_idx);   % (Mx, My, n_samp_r, n_samp_l)
    spatial_snap = sum(sum(X_sub .* reshape(W_focus, 1, 1, n_samp_r, n_samp_l), 3), 4);
    % spatial_snap: (Mx, My) 复数矩阵, 包含该目标的空间信息

    % 2D-ESPRIT: 利用相邻阵元的相位旋转不变性
    % x 方向
    sx1 = spatial_snap(1:end-1, :);
    sx2 = spatial_snap(2:end, :);
    phi_x = angle(sum(conj(sx1(:)) .* sx2(:)));

    % y 方向
    sy1 = spatial_snap(:, 1:end-1);
    sy2 = spatial_snap(:, 2:end);
    phi_y = angle(sum(conj(sy1(:)) .* sy2(:)));

    % 相位差 → 方向余弦
    % 信道模型: a_rx(mx) = exp(j·mx·ω_ax), ω_ax = -2π·d·u/λ
    % ESPRIT 相位差 = ω_ax = -2π·d·u/λ  →  u = -phi_x·λ/(2π·d)
    u_hat = -phi_x * params.lambda / (2 * pi * params.d);
    v_hat = -phi_y * params.lambda / (2 * pi * params.d);

    u_hat = max(min(u_hat, 1), -1);
    v_hat = max(min(v_hat, 1), -1);
    sin_theta = min(sqrt(u_hat^2 + v_hat^2), 1);
    theta_val = asind(sin_theta);
    phi_val   = atan2d(v_hat, u_hat);

    % =====================================================================
    % 距离/速度: FFT bin + 抛物线插值
    % =====================================================================
    nr_frac = double(nr_here);
    if use_interp
        Pl = double(cand_pow_r_left(ic));
        Pc = double(cand_pow(ic));
        Pr = double(cand_pow_r_right(ic));
        denom_interp = Pl - 2*Pc + Pr;
        if abs(denom_interp) > eps
            delta_r = 0.5 * (Pl - Pr) / denom_interp;
            delta_r = max(min(delta_r, 0.5), -0.5);
            nr_frac = nr_frac + delta_r;
        end
    end
    R_val = mod(-params.c * nr_frac / (2 * Nr * delta_f), Rmax);

    nv_frac = double(nv_here);
    if use_interp
        Pl = double(cand_pow_v_left(ic));
        Pc = double(cand_pow(ic));
        Pr = double(cand_pow_v_right(ic));
        denom_interp = Pl - 2*Pc + Pr;
        if abs(denom_interp) > eps
            delta_v = 0.5 * (Pl - Pr) / denom_interp;
            delta_v = max(min(delta_v, 0.5), -0.5);
            nv_frac = nv_frac + delta_v;
        end
    end
    v_val = params.c * nv_frac / (2 * Nv * params.Ts * params.fc);

    detected = detected + 1;
    theta_est(detected) = theta_val;
    phi_est(detected)   = phi_val;
    R_est(detected)     = R_val;
    v_est(detected)     = v_val;
    indices4(detected, :) = [ia_x, ia_y, ir, iv];
end

% -------------------------------------------------------------------------
% 5. 截断并输出诊断信息
% -------------------------------------------------------------------------
theta_est = theta_est(1:detected);
phi_est   = phi_est(1:detected);
R_est     = R_est(1:detected);
v_est     = v_est(1:detected);

info = struct();
info.detector          = 'joint_arv_4d_streaming';
info.detected_targets  = detected;
info.indices4          = indices4(1:detected, :);
info.Na_x              = Na_x;
info.Na_y              = Na_y;
info.Nr                = Nr;
info.Nv                = Nv;
info.alpha_bin_mean    = mean(alpha_bin(:));
info.alpha_bin_max     = max(alpha_bin(:));
info.use_full_steering = use_full_steering;
info.num_candidates    = num_cand;
info.local_topk        = local_topk;
info.mem_peak_gb       = mem_peak / 1e9;
end
