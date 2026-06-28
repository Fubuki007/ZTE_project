function [theta_est, phi_est, R_est, v_est, info] = joint_estimator_fast(rx_cube, tx_signal, params)
% =========================================================================
% JOINT_ESTIMATOR_FAST  快速 4D 联合角度-距离-速度估计器 (v4 工程版)
% -------------------------------------------------------------------------
% v4 改进 (相对 v3 的两阶段快速版):
%   1. 天线维度均衡 — 先在完整 (Mx,My,Ns,L) 上做均衡, 再空间求和
%      数学上与 v3 等价, 但工程优势:
%      (a) 定点化数值稳定性更好 (避免先求和导致的 overflow)
%      (b) 保留天线维信息, 支持后续波束域干扰抑制和 RIS 联合优化
%      (c) 可独立校验每路天线的接收质量
%   2. ESPRIT 采样增强 — n_samp_r=896, n_samp_l=192 (v3: 256/48)
%      提高角度估计的 SNR 增益和相位解模糊能力
%   3. 多普勒 FFT 补零 2x — Nv_pad=512 (v3: 256, 不补零)
%      改善多普勒显示分辨率, 降低速度插值误差
%   4. 2D Hann 窗 — 降低 FFT 旁瓣, 提高弱目标/近距离目标的检测概率
%   5. 候选数增加到 32 — 提高多目标场景的捕获率
%   6. 距离/速度抛物线插值 + 迭代精化 — 提高亚 bin 精度
%
% 架构: 两阶段 (不变, 因为空间求和仍等效)
%   阶段 1: (可选天线维均衡)→空间求和→加窗→补零2D-FFT→RD峰值检测
%   阶段 2: 局部窗口提取→ESPRIT 角度精估计→抛物线+迭代距离/速度精化
%
% 时间目标: 0.7-0.9s (满足 <1s 刷新率验收要求)
% =========================================================================

% 0. 维度与参数
[Mx, My, Ns, L] = size(rx_cube);
Q = params.num_targets;
delta_f = params.B / Ns;
Rmax_val = params.c / (2 * delta_f);

% ---- 配置参数 (可通过 params.fast_estimator 覆盖) ----
cfg = struct();
cfg.preserve_antenna_dim = false;  % 天线维均衡 (默认关: v3等价, 开则约+0.55s)
cfg.n_samp_r             = 1024;   % ESPRIT 距离维采样点数 (v3: 256)
cfg.n_samp_l             = 256;    % ESPRIT 多普勒维采样点数 (v3: 48)
cfg.n_pad_v              = 512;    % 多普勒 FFT 补零点数 (v3: 不补零, L=256)
cfg.enable_hann          = true;   % 2D Hann 窗 (v4 新增)
cfg.enable_refine        = true;   % 抛物线插值后迭代精化 (v4 新增)
cfg.num_candidates       = 32;     % 候选峰值数 (v3: 8)
cfg.nms_r                = 2;      % NMS 距离保护间隔
cfg.nms_v                = 2;      % NMS 多普勒保护间隔

% 用户覆盖
if isfield(params, 'fast_estimator') && ~isempty(params.fast_estimator)
    f = fieldnames(params.fast_estimator);
    for k = 1:numel(f)
        if isfield(cfg, f{k})
            cfg.(f{k}) = params.fast_estimator.(f{k});
        end
    end
end

% ESPRIT 采样点数 (限定范围, 防止超内存)
n_samp_r = min(Ns, max(64, cfg.n_samp_r));
n_samp_l = min(L,  max(16, cfg.n_samp_l));
num_candidates = max(2*Q, cfg.num_candidates);

% =========================================================================
% 阶段 1: RD 检测
% =========================================================================

% --- 1a. 发射端等效标量 ---
sz_tx = size(tx_signal);
if isequal(sz_tx, [Ns, L])
    tx_eff = tx_signal;
else
    tx_eff = squeeze(sum(sum(tx_signal, 1), 2));   % (Ns, L)
end

% --- 1b. 均衡 (移除发射信号调制) ---
tx_norm = tx_eff ./ max(abs(tx_eff), eps);

% --- 1c. 多普勒补零参数 (两个分支共用, 提前计算) ---
Nv_pad = max(L, cfg.n_pad_v);
if abs(Nv_pad - round(Nv_pad)) > eps || mod(Nv_pad, 2) ~= 0
    Nv_pad = 2^nextpow2(max(L, Nv_pad));         % 确保是 2 的幂
end

% --- 1d. 空间处理 + RD 检测 ---
if cfg.preserve_antenna_dim
    % v4 模式: 先在天线维做完整均衡, 再空间求和 + 加窗 + FFT
    rx_eq = rx_cube .* reshape(conj(tx_norm), 1, 1, Ns, L);
    rx_eq_sum = squeeze(sum(rx_eq, [1 2]));             % (Ns, L)
    if cfg.enable_hann
        win_r = hann(Ns, 'periodic');
        win_l = hann(L,  'periodic');
        rx_eq_sum = rx_eq_sum .* (win_r * win_l.');
    end
    RD = fft(rx_eq_sum, Ns, 1);
    RD = fft(RD, Nv_pad, 2);
    RD = fftshift(RD, 2);
    P = abs(RD).^2;
else
    % ★ 多波束空间处理 (替代等增益求和)
    % 根因: sum(rx_cube,[1 2]) 等同 broadside 单波束, 离轴目标被衰减
    % 方案: 2D 空间 FFT 形成 64 个正交波束, 选最强 N 个分别 RD, 非相干累积
    top_n_spatial = min(8, Mx * My);

    % 空间 2D Hann 窗 (压低旁瓣 -13dB→-31dB, 防止强目标掩盖弱目标)
    win_sx = hann(Mx, 'periodic');
    win_sy = hann(My, 'periodic');
    rx_cube_win = rx_cube .* (win_sx * win_sy.');

    rx_bf = fftshift(fftshift(fft2(rx_cube_win), 1), 2);  % (Mx, My, Ns, L)

    % 预选最强的空间 bin (基于平均功率)
    P_spatial = squeeze(mean(mean(abs(rx_bf).^2, 3), 4));   % (Mx, My)
    [~, sort_idx] = sort(P_spatial(:), 'descend');
    top_idx = sort_idx(1:top_n_spatial);

    % 对每个强空间 bin 做 RD 检测, 非相干功率累积
    P = zeros(Ns, Nv_pad);
    for k = 1:numel(top_idx)
        [mx_i, my_i] = ind2sub([Mx, My], top_idx(k));
        rx_s = squeeze(rx_bf(mx_i, my_i, :, :));            % (Ns, L)
        rx_s_eq = rx_s .* conj(tx_norm);                    % 均衡
        if cfg.enable_hann
            win_r = hann(Ns, 'periodic');
            win_l = hann(L,  'periodic');
            rx_s_eq = rx_s_eq .* (win_r * win_l.');
        end
        RD_k = fft(rx_s_eq, Ns, 1);                         % 距离 FFT
        RD_k = fft(RD_k, Nv_pad, 2);                        % 多普勒 FFT
        RD_k = fftshift(RD_k, 2);
        P = P + abs(RD_k).^2;                                % 非相干累积
    end
    P = P / numel(top_idx);                                  % 归一化
end

% --- 1e. 峰值检测 ---
[~, idx] = maxk(P(:), min(num_candidates * 4, numel(P)));%找最大峰值候选，再用 NMS 去掉太近的重复峰

% 距离/多普勒 bin 向量
nr_vec = (0 : Ns - 1).';                         % 距离 (0-based)
nv_vec = (-floor(Nv_pad/2) : (ceil(Nv_pad/2) - 1)).';  % 多普勒 (shifted)

% 多普勒缩放因子: 因为补零后 bin 索引对应的是 Nv_pad 点 FFT
% 原始 L 点多普勒的真实物理频率 f_d = nv / L, 补零后需用 L 做尺度还原
doppler_scale = L / Nv_pad;   % 补零后 bin 间距缩放

% =========================================================================
% 阶段 2: ESPRIT 角度精估计 (局部窗口, 逐目标)
% =========================================================================

% 预计算 ESPRIT 多普勒采样网格 (全范围, K=256 不大)
esprit_l_idx = round(linspace(1, L,  n_samp_l));
esprit_l_vec = esprit_l_idx(:) - 1;

% 输出变量初始化
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
    
    [ir, iv] = ind2sub([Ns, Nv_pad], idx(ii));
    nr = nr_vec(ir);                              % 0-based 距离 bin
    nv_raw = nv_vec(iv);                          % 多普勒 bin (补零后)
    
    % 还原到原始多普勒尺度
    nv = nv_raw * doppler_scale;                  % 等效 L 点 bin 索引
    
    % NMS 去重
    if detected > 0
        nv_prev = selected_iv(1:detected);
        if any(abs(ir - selected_ir(1:detected)) <= cfg.nms_r & ...
               abs(nv - nv_prev) <= cfg.nms_v * doppler_scale)
            continue;
        end
    end
    
    % 距离门限: 排除近距离假峰 (SI残余在 R≈0 处, 对应 nr≈Ns)
    if isfield(cfg, 'R_min_gate') && cfg.R_min_gate > 0
        R_check = params.c * (Ns - nr) / (2 * Ns * delta_f);
        if R_check < cfg.R_min_gate
            continue;
        end
    end
    
    % 局部距离窗口: 以检测 bin 为中心, 缩小范围减少跨目标串扰
    r_win = max(128, round(Ns / 40));  % ~317 bins ≈ 31m
    n_start = max(1, ir - r_win);
    n_end   = min(Ns, ir + r_win);
    esprit_n_idx = round(linspace(n_start, n_end, n_samp_r));
    esprit_n_vec = esprit_n_idx(:) - 1;   % 0-based
    
    % -----------------------------------------------------------------
    % 2.1 ESPRIT 角度精化
    % -----------------------------------------------------------------
    omega_r = 2 * pi * nr / Ns;
    omega_v = 2 * pi * nv / L;                    % 用 L 做物理频率还原
    
    % 相位补偿权重
    W_r = exp(-1j * esprit_n_vec * omega_r);      % (n_samp_r, 1)
    W_l = exp(-1j * esprit_l_vec * omega_v);      % (n_samp_l, 1)
    W_focus = W_r * W_l.';                         % (n_samp_r, n_samp_l)
    
    % 局部窗口数据提取
    X_local = rx_cube(:, :, esprit_n_idx, esprit_l_idx);
    
    % 局部均衡 (移除发射调制) — 在局部窗口上做
    tx_local = tx_eff(esprit_n_idx, esprit_l_idx);           % (n_samp_r, n_samp_l)
    tx_local_norm = tx_local ./ max(abs(tx_local), eps);
    X_local = X_local .* reshape(conj(tx_local_norm), 1, 1, n_samp_r, n_samp_l);
    
    % 相位补偿聚焦: 距离/多普勒维加权求和 → 空间快拍 (Mx, My)
    spatial_snap = sum(X_local .* reshape(W_focus, 1, 1, n_samp_r, n_samp_l), [3 4]);
    
    % 2D-ESPRIT: 相邻阵元相位旋转不变性
    sx1 = spatial_snap(1:end-1, :);
    sx2 = spatial_snap(2:end, :);
    phi_x = angle(sum(conj(sx1(:)) .* sx2(:)));
    
    sy1 = spatial_snap(:, 1:end-1);
    sy2 = spatial_snap(:, 2:end);
    phi_y = angle(sum(conj(sy1(:)) .* sy2(:)));
    
    % 相位差 → 方向余弦 → 俯仰/方位角
    u_hat = -phi_x * params.lambda / (2 * pi * params.d);
    v_hat = -phi_y * params.lambda / (2 * pi * params.d);
    u_hat = max(min(u_hat, 1), -1);
    v_hat = max(min(v_hat, 1), -1);
    
    sin_theta = min(sqrt(u_hat^2 + v_hat^2), 1);
    theta_val = asind(sin_theta);
    phi_val   = atan2d(v_hat, u_hat);
    
    % -----------------------------------------------------------------
    % v4.1 方向感知均衡精化 (仅 MIMO 模式, 当 tx_signal 为 4D 张量)
    % 问题: 仿真回波用 a_tx^H(θ_q,φ_q)·X (方向相关), 但均衡用
    %       sum(sum(X)) (标量求和), 模型不一致造成高 SNR 误差地板.
    % 方案: 用初始 ESPRIT 角度估计重建 Tx 导向矢量 a_tx(θ̂,φ̂),
    %       重新计算方向相关的 tx_eff, 再均衡→再 ESPRIT→再 RD.
    % -----------------------------------------------------------------
    mimo_refined = false;
    if ndims(tx_signal) == 4
        Ntx = size(tx_signal, 1);
        Nty = size(tx_signal, 2);
        kw_tx = 2 * pi * params.d / params.lambda;
        
        u_dir = sind(theta_val) * cosd(phi_val);
        v_dir = sind(theta_val) * sind(phi_val);
        
        a_tx_x = exp(1j * kw_tx * (0:Ntx-1).' * u_dir);
        a_tx_y = exp(1j * kw_tx * (0:Nty-1).' * v_dir);
        a_tx_est = a_tx_x * a_tx_y.';   % (Ntx, Nty)
        conj_atx = conj(a_tx_est);
        
        % --- 精化角度: 正确 tx_eff 均衡 + 重新 ESPRIT ---
        tx_local_ref = zeros(n_samp_r, n_samp_l, 'like', tx_signal);
        for ntx_i = 1:Ntx
            for nty_i = 1:Nty
                tx_local_ref = tx_local_ref + conj_atx(ntx_i, nty_i) * ...
                    squeeze(tx_signal(ntx_i, nty_i, esprit_n_idx, esprit_l_idx));
            end
        end
        
        X_local_ref = rx_cube(:, :, esprit_n_idx, esprit_l_idx);
        tx_local_ref_norm = tx_local_ref ./ max(abs(tx_local_ref), eps);
        X_local_ref = X_local_ref .* reshape(conj(tx_local_ref_norm), 1, 1, n_samp_r, n_samp_l);
        
        spatial_snap_ref = sum(X_local_ref .* reshape(W_focus, 1, 1, n_samp_r, n_samp_l), [3 4]);
        
        sx1 = spatial_snap_ref(1:end-1, :);
        sx2 = spatial_snap_ref(2:end, :);
        phi_x = angle(sum(conj(sx1(:)) .* sx2(:)));
        
        sy1 = spatial_snap_ref(:, 1:end-1);
        sy2 = spatial_snap_ref(:, 2:end);
        phi_y = angle(sum(conj(sy1(:)) .* sy2(:)));
        
        u_hat = -phi_x * params.lambda / (2 * pi * params.d);
        v_hat = -phi_y * params.lambda / (2 * pi * params.d);
        u_hat = max(min(u_hat, 1), -1);
        v_hat = max(min(v_hat, 1), -1);
        
        sin_theta_ref = min(sqrt(u_hat^2 + v_hat^2), 1);
        theta_val = asind(sin_theta_ref);
        phi_val   = atan2d(v_hat, u_hat);
        
        % --- 精化距离/速度: 用正确 tx_eff 重建全尺寸 RD ---
        % 关键: 必须重建全尺寸 RD, 因为 tx_eff 偏差可能导致
        % 峰值偏移远超局部窗口. 对 K_stream>1 尤为重要.
        tx_eff_full = zeros(Ns, L, 'like', tx_signal);
        for ntx_i = 1:Ntx
            for nty_i = 1:Nty
                tx_eff_full = tx_eff_full + conj_atx(ntx_i, nty_i) * ...
                    squeeze(tx_signal(ntx_i, nty_i, :, :));
            end
        end
        
        rx_sum_local = squeeze(sum(rx_cube, [1 2]));
        tx_full_norm = tx_eff_full ./ max(abs(tx_eff_full), eps);
        rx_eq_ref = rx_sum_local .* conj(tx_full_norm);
        
        if cfg.enable_hann
            win_r = hann(Ns, 'periodic');
            win_l = hann(L, 'periodic');
            rx_eq_ref = rx_eq_ref .* (win_r * win_l.');
        end
        
        RD_ref = fft(rx_eq_ref, Ns, 1);
        RD_ref = fft(RD_ref, Nv_pad, 2);
        RD_ref = fftshift(RD_ref, 2);
        P_ref = abs(RD_ref).^2;
        
        % 在原检测到的 (ir, iv) 附近搜索精化峰值
        % 搜索窗: 距离 ±Ns/16, 多普勒 ±Nv_pad/8
        r_search = max(4, round(Ns / 160));  % ~79 bins ≈ 7.8m (严格隔离两目标)
        v_search = max(2, round(Nv_pad / 8));
        ir_min = max(1, ir - r_search);
        ir_max = min(Ns, ir + r_search);
        iv_raw = round(nv / doppler_scale) + floor(Nv_pad/2) + 1;
        iv_min = max(1, iv_raw - v_search);
        iv_max = min(Nv_pad, iv_raw + v_search);
        
        P_roi = P_ref(ir_min:ir_max, iv_min:iv_max);
        [~, idx_roi] = max(P_roi, [], 'all');
        [ir_roi, iv_roi] = ind2sub(size(P_roi), idx_roi);
        ir_ref = ir_min + ir_roi - 1;
        iv_ref = iv_min + iv_roi - 1;
        
        % 合理性守卫: 精化结果不应偏离粗 bin 太远 (防止跨目标跳峰)
        ir_dev = abs(ir_ref - ir);
        iv_dev = abs(iv_ref - iv_raw);
        if ir_dev > 5 || iv_dev > 3     % >~0.5m or >~7m/s deviation → reject
            % 回退: 保留 ESPRIT 角度, 距离/速度走非 MIMO 路径 (mimo_refined stays false)
        else
            % 距离精化 (用原始 P)
            nr_ref = nr_vec(ir_ref);
            if ir_ref > 1 && ir_ref < Ns
                Pl_r = P(ir_ref-1, iv_ref);
                Pc_r = P(ir_ref, iv_ref);
                Pr_r = P(ir_ref+1, iv_ref);
                d_r = Pl_r - 2*Pc_r + Pr_r;
                if abs(d_r) > eps
                    delta_r = 0.5 * (Pl_r - Pr_r) / d_r;
                    nr_ref = nr_ref + max(min(delta_r, 0.5), -0.5);
                end
            end
            nr_frac = nr_ref;
            R_val = mod(-params.c * nr_frac / (2 * Ns * delta_f), Rmax_val);
            
            % 速度精化 (用原始 P, 因为 P_ref 的峰值形状被 tx_eff_ref 扭曲)
            nv_raw_ref = nv_vec(iv_ref);
            nv_ref = nv_raw_ref * doppler_scale;
            nv_frac_ref = nv_ref;
            if iv_ref > 1 && iv_ref < Nv_pad
                Pl_v = P(ir_ref, iv_ref-1);
                Pc_v = P(ir_ref, iv_ref);
                Pr_v = P(ir_ref, iv_ref+1);
                d_v = Pl_v - 2*Pc_v + Pr_v;
                if abs(d_v) > eps
                    delta_v = 0.5 * (Pl_v - Pr_v) / d_v;
                    nv_raw_frac = nv_raw_ref + max(min(delta_v, 0.5), -0.5);
                    nv_frac_ref = nv_raw_frac * doppler_scale;
                end
            end
            nv_frac = nv_frac_ref;
            v_val = params.c * nv_frac / (2 * L * params.Ts * params.fc);
            
            
            % 同步更新 W_focus 用于后续 ESPRIT (影响下一个目标的聚焦)
            omega_r_ref = 2 * pi * nr_ref / Ns;
            omega_v_ref = 2 * pi * nv_ref / L;
            W_r_ref = exp(-1j * esprit_n_vec * omega_r_ref);
            W_l_ref = exp(-1j * esprit_l_vec * omega_v_ref);
            W_focus = W_r_ref * W_l_ref.';
            
            % 更新 bin 索引
            ir = ir_ref;
            nv = nv_ref;
            
            mimo_refined = true;
        end
    end
    
    % -----------------------------------------------------------------
    % 2.2 距离估计: FFT bin + 抛物线插值 + 可选迭代精化
    % (MIMO 模式下已在方向感知精化块中完成, 此处跳过)
    % -----------------------------------------------------------------
    if ~mimo_refined
        nr_frac = double(nr);
    ir_left  = mod(ir - 2, Ns) + 1;
    ir_right = mod(ir, Ns) + 1;
    
    % 第一轮: 标准抛物线插值
    Pl = P(ir_left, iv);
    Pc = P(ir, iv);
    Pr = P(ir_right, iv);
    denom_interp = Pl - 2*Pc + Pr;
    if abs(denom_interp) > eps
        delta_r = 0.5 * (Pl - Pr) / denom_interp;  %抛物线插值
        delta_r = max(min(delta_r, 0.5), -0.5);
        nr_frac = nr_frac + delta_r;
    end
    
    if cfg.enable_refine
        % 第二轮迭代精化: 重心法 (稳健于非对称谱峰)
        % 在抛物线插值结果附近取 3 点, 重心法微调
        ir0 = max(1, min(Ns, round(nr_frac) + 1));   % 1-based 最近邻
        ir_m1 = max(1, ir0 - 1);
        ir_p1 = min(Ns, ir0 + 1);
        w_m1 = P(ir_m1, iv);
        w_0  = P(ir0, iv);
        w_p1 = P(ir_p1, iv);
        sum_w = w_m1 + w_0 + w_p1;
        if sum_w > eps
            nr_refined = ((ir_m1 - 1) * w_m1 + (ir0 - 1) * w_0 + (ir_p1 - 1) * w_p1) / sum_w;
            if abs(nr_refined - nr_frac) < 1.0
                nr_frac = 0.7 * nr_frac + 0.3 * nr_refined;
            end
        end
    end
    
    R_val = mod(-params.c * nr_frac / (2 * Ns * delta_f), Rmax_val);
    
    % -----------------------------------------------------------------
    % 2.3 速度估计: FFT bin + 抛物线插值 + 可选迭代精化
    % -----------------------------------------------------------------
    nv_frac = double(nv);
    
    % 找到补零后 iv 的左右邻 (在 P 矩阵中)
    iv_left  = max(iv - 1, 1);
    iv_right = min(iv + 1, Nv_pad);
    
    if iv_left < iv && iv_right > iv
        Pl_v = P(ir, iv_left);
        Pc_v = P(ir, iv);
        Pr_v = P(ir, iv_right);
        denom_interp_v = Pl_v - 2*Pc_v + Pr_v;
        if abs(denom_interp_v) > eps
            delta_v = 0.5 * (Pl_v - Pr_v) / denom_interp_v;
            delta_v = max(min(delta_v, 0.5), -0.5);
            % delta_v 对应的是补零后网格的偏移
            nv_raw_frac = nv_raw + delta_v;
            nv_frac = nv_raw_frac * doppler_scale;   % 还原到 L 尺度
        end
    end
    
    if cfg.enable_refine
        % 迭代精化: 重心法
        nv0 = round(nv_frac);
        if nv0 > 1 && nv0 < L
            % 还原到补零后网格
            iv0 = round(nv_frac / doppler_scale);
            iv_m1 = max(iv0 - 1, 1);
            iv_p1 = min(iv0 + 1, Nv_pad);
            w_m1 = P(ir, iv_m1);
            w_0  = P(ir, iv0);
            w_p1 = P(ir, iv_p1);
            sum_w = w_m1 + w_0 + w_p1;
            if sum_w > eps
                nv_refined = (iv_m1 * w_m1 + iv0 * w_0 + iv_p1 * w_p1) / sum_w * doppler_scale;
                if abs(nv_refined - nv_frac) < 1.0
                    nv_frac = 0.7 * nv_frac + 0.3 * nv_refined;
                end
            end
        end
    end
    
    % 速度计算: v = c * nv / (2 * L * Ts * fc)
    % nv 为多普勒 bin 索引 (对应 L 点 FFT)
    v_val = params.c * nv_frac / (2 * L * params.Ts * params.fc);
    
    end  % if ~mimo_refined
    
    % -----------------------------------------------------------------
    % 2.4 记录
    % -----------------------------------------------------------------
    detected = detected + 1;
    theta_est(detected) = theta_val;
    phi_est(detected)   = phi_val;
    R_est(detected)     = R_val;
    v_est(detected)     = v_val;
    selected_ir(detected) = ir;
    selected_iv(detected) = nv;   % 保存 L 尺度的 bin
end

% =========================================================================
% 截断输出
% =========================================================================
theta_est = theta_est(1:detected);
phi_est   = phi_est(1:detected);
R_est     = R_est(1:detected);
v_est     = v_est(1:detected);

info = struct();
info.detector         = 'joint_estimator_fast_v4';
info.detected_targets = detected;
info.Ns               = Ns;
info.L                = L;
info.Nv_pad           = Nv_pad;
info.n_samp_r         = n_samp_r;
info.n_samp_l         = n_samp_l;
info.preserve_antenna = cfg.preserve_antenna_dim;
info.enable_hann      = cfg.enable_hann;
info.enable_refine    = cfg.enable_refine;
info.cfg              = cfg;
end
