function rx_cube = simulate_radar_channel_3d(tx_signal, params)
% =========================================================================
% SIMULATE_RADAR_CHANNEL_3D  MIMO-OFDM ISAC 回波仿真 (URA, 4D 版)
% -------------------------------------------------------------------------
% 对齐作者源代码 echo_generate.m 的无噪回波模型, 并按论文 (4D 扩展版, 见
% 文献 zte_project_3d_extracted_clean.txt 公式 (3)(7a)) 扩展到
%   接收 URA (Mx × My)  +  发射 URA (Ntx × Nty).
%
% 论文 4D 版 (7a): 对第 q 个目标
%   y(mx, my, i, l) = Σ_q β_q · a_tx^H(θ_q, φ_q) · x_i[l]
%                     · exp(j·mx·ω_ax) · exp(j·my·ω_ay)
%                     · exp(j·i·ω_r)   · exp(j·l·ω_v) + z(·)
% 其中 a_tx(θ, φ) 为发射 URA 导向矢量 (Ntx·Nty 展平).
%
% 支持两种 tx_signal 格式:
%   (A) (Ns, L)                 —— 标量发射端 (N_tx = 1), 对应
%                                    a_tx^H · x_i[l] = x_i[l].
%                                    兼容旧的标量发射接口.
%   (B) (Ntx, Nty, Ns, L)       —— 完整 MIMO 发射张量, 由
%                                    generate_mimo_ofdm_waveform.m 产出
%                                    (已包含 ZF 预编码 W·s).
%                                    此时会按 URA 发射 steering 做
%                                    a_tx^H · x 的内积.
%
% 输入:
%   tx_signal - (Ns, L) 或 (Ntx, Nty, Ns, L)
%   params    - 必需: Mx, My, N, K, num_targets, lambda, d, fc, c, B, Ts,
%                     theta_true, phi_true, R_true, v_true, alpha, SNR
%                可选: enable_SI, beta_SI, beta_SI_abs, theta_SI, phi_SI,
%                      R_SI, v_SI, array_mismatch.*
%
% 输出:
%   rx_cube   - (Mx, My, Ns, L) 接收数据立方体 (已叠加 AWGN)
% =========================================================================

Mx = params.Mx;
My = params.My;
Ns = params.N;
L  = params.K;
Q  = params.num_targets;
delta_f = params.B / Ns;

% 发射端格式分辨
sz = size(tx_signal);
if isequal(sz, [Ns, L])
    tx_mode = 'scalar';
    Ntx = 1; Nty = 1;
elseif ndims(tx_signal) == 4 && sz(3) == Ns && sz(4) == L
    tx_mode = 'mimo';
    Ntx = sz(1); Nty = sz(2);
else
    error('tx_signal 维度非法: 仅支持 (Ns, L) 或 (Ntx, Nty, Ns, L).');
end

rx_cube = zeros(Mx, My, Ns, L, 'like', tx_signal);

% 可选: 接收阵幅相失配 (高 SNR 误差地板)
g_rx = ones(Mx, My);
if isfield(params, 'array_mismatch') && isfield(params.array_mismatch, 'enable') && params.array_mismatch.enable
    amp_sigma_db    = 0.0;
    phase_sigma_deg = 0.0;
    if isfield(params.array_mismatch, 'amp_sigma_db'),    amp_sigma_db    = params.array_mismatch.amp_sigma_db;    end
    if isfield(params.array_mismatch, 'phase_sigma_deg'), phase_sigma_deg = params.array_mismatch.phase_sigma_deg; end
    amp_err_db  = amp_sigma_db * randn(Mx, My);
    amp_err_lin = 10.^(amp_err_db / 20);
    phase_err   = deg2rad(phase_sigma_deg * randn(Mx, My));
    g_rx        = amp_err_lin .* exp(1j * phase_err);
end

% 预计算发射端 steering 相关常量 (仅 MIMO 模式下用)
kw = 2*pi * params.d / params.lambda;
nx_tx = (0:Ntx-1).';
ny_tx = (0:Nty-1).';

% -------------------------- 真实目标 -------------------------------------
for q = 1:Q
    theta_q = params.theta_true(q);
    phi_q   = params.phi_true(q);

    % 接收空间相位 (URA)
    u = sind(theta_q) * cosd(phi_q);
    vdir = sind(theta_q) * sind(phi_q);
    omega_ax = -2 * pi * params.d * u    / params.lambda;% x 方向空间相位，决定俯仰/方位
    omega_ay = -2 * pi * params.d * vdir / params.lambda;% y 方向空间相位，决定俯仰/方位
    omega_r  = -4 * pi * delta_f * params.R_true(q) / params.c;% y 方向空间相位，决定俯仰/方位
    omega_v  =  4 * pi * params.Ts * params.v_true(q) * params.fc / params.c;% 速度相位，随 OFDM 符号变化
%空间相位变化 → 目标从哪个方向来
%子载波相位变化 → 目标距离多远
%符号间相位变化 → 目标速度多快
    a_rx_x = exp(1j * (0:Mx-1).' * omega_ax);
    a_rx_y = exp(1j * (0:My-1)   * omega_ay);
    a_rx   = a_rx_x * a_rx_y;                  % (Mx, My)构造接收 steering

    phase_n = exp(1j * (0:Ns-1).' * omega_r);  %再构造距离/速度相位
    phase_l = exp(1j * (0:L-1)    * omega_v);
    phase   = phase_n * phase_l;               % (Ns, L)

    % 发射端系数 a_tx^H(θ_q, φ_q) · x_i[l]   (论文式 (7a) / 原始回波式 (3))
    switch tx_mode
        case 'scalar'
            ax_q_sig = tx_signal;              % (Ns, L)
        case 'mimo'
            ax_tx_x = exp(1j * kw * nx_tx * u);      % (Ntx, 1)
            ax_tx_y = exp(1j * kw * ny_tx * vdir);   % (Nty, 1)
            a_tx_q  = ax_tx_x * ax_tx_y.';           % (Ntx, Nty)
            conj_atx = conj(a_tx_q);
            % 逐天线累加 a_tx^H · x, 避免分配 (Ntx,Nty,Ns,L) 临时数组
            ax_q_sig = zeros(Ns, L, 'like', tx_signal);
            for ntx_i = 1:Ntx
                for nty_i = 1:Nty
                    ax_q_sig = ax_q_sig + conj_atx(ntx_i, nty_i) * ...
                        squeeze(tx_signal(ntx_i, nty_i, :, :));
                end
            end
    end

    echo_q = params.alpha(q) * (ax_q_sig .* phase);%最后把发射信号经过目标反射之后加到 rx_cube 里
    a_rx_mismatch = a_rx .* g_rx;
    % 分块累加到 rx_cube, 避免广播产生 (Mx,My,Ns,L) 临时数组
    for l_idx = 1:L
        rx_cube(:,:,:,l_idx) = rx_cube(:,:,:,l_idx) + ...
            a_rx_mismatch .* reshape(echo_q(:,l_idx), 1, 1, Ns);
    end
end

% ★ 在 SI 注入前保存目标回波功率 (用于 SNR 定义, 不受 SI 污染)
target_sig_pow = mean(abs(rx_cube(:)).^2);

% -------------------------- 可选 SI 项 -----------------------------------
if isfield(params, 'enable_SI') && params.enable_SI
    % 两种 SI 模型:
    %   (A) 点散射 (默认): beta_SI * a_rx(θ_SI,φ_SI) * a_tx^H(θ_SI,φ_SI)
    %                      * x * exp(距离/多普勒相位)
    %   (B) 矩阵 H_SI (若 params.H_SI_matrix 非空): 直接用 H_SI × x,
    %       对应文档公式 (11)-(13) 的 Rician 矩阵模型.
    use_matrix_si = isfield(params, 'H_SI_matrix') && ~isempty(params.H_SI_matrix);

    if use_matrix_si && strcmp(tx_mode, 'scalar')
        error('矩阵 SI 模式仅支持 MIMO tx_signal (Ntx·Nty 展平), 不支持 scalar 模式');
    end

    beta_si_abs = params.beta_SI;
    if isfield(params, 'beta_SI_abs'), beta_si_abs = params.beta_SI_abs; end
    if beta_si_abs == 0, beta_si_abs = realmin; end

    if use_matrix_si
        % ============== (B) 矩阵 H_SI 模式 (向量化加速) ==============
        % y_SI(:, i, l) = beta_SI * H_SI * x(:, i, l)
        % 频率平坦假设: H_SI 对所有子载波相同
        % 向量化: 逐符号做 H_SI * X_l, X_l 为 (Nt × Ns)
        Nt_total = Ntx * Nty;
        Nr_total = Mx * My;

        if isfield(params, 'H_SI_matrix_per_cc') && ~isempty(params.H_SI_matrix_per_cc)
            H_SI_cube = params.H_SI_matrix_per_cc;   % (Nr_total × Nt_total × Ns)
            freq_flat = false;
        else
            H_SI_mat = params.H_SI_matrix;
            if size(H_SI_mat, 1) ~= Nr_total || size(H_SI_mat, 2) ~= Nt_total
                error('H_SI_matrix 形状必须为 (Nr_total=%d × Nt_total=%d), 实际 (%d × %d)', ...
                    Nr_total, Nt_total, size(H_SI_mat, 1), size(H_SI_mat, 2));
            end
            % 频率平坦: 保留单矩阵, 不 repmat 到 Ns (向量化快速路径)
            H_SI_cube = H_SI_mat;                    % (Nr_total × Nt_total)
            freq_flat = true;
        end

        % 可选多普勒/距离相位
        if isfield(params, 'R_SI') && params.R_SI > 0
            omega_r_si = -4 * pi * delta_f * params.R_SI / params.c;
        else
            omega_r_si = 0;
        end
        if isfield(params, 'v_SI')
            omega_v_si = 4 * pi * params.Ts * params.v_SI * params.fc / params.c;
        else
            omega_v_si = 0;
        end
        phase_n_si = exp(1j * (0:Ns-1).' * omega_r_si);     % (Ns, 1)
        phase_l_si = exp(1j * (0:L-1)    * omega_v_si);     % (1,  L)

        % ★ 向量化: 逐符号一次矩阵乘, 替代原来的 Ns×L 双重循环 ★
        for l_idx = 1:L
            % 把 (Ntx, Nty, Ns) 展平 → (Nt_total, Ns)
            x_l = reshape(tx_signal(:, :, :, l_idx), Nt_total, Ns);
            if freq_flat
                % 所有子载波共用同一 H_SI → 一次大矩阵乘 (Nr×Nt) × (Nt×Ns) = (Nr×Ns)
                y_l = H_SI_cube * x_l;                       % (Nr_total, Ns)
            else
                % 逐子载波不同 H_SI → 逐列乘
                y_l = zeros(Nr_total, Ns, 'like', tx_signal);
                for i = 1:Ns
                    y_l(:, i) = H_SI_cube(:, :, i) * x_l(:, i);
                end
            end
            % 加距离相位 + 符号间多普勒相位 + 接收阵失配
            y_l = y_l .* phase_n_si.';                       % (Nr, Ns) 逐子载波相位
            y_l = beta_si_abs * phase_l_si(l_idx) * y_l;     % 多普勒 + 幅度
            % reshape 回 (Mx, My, Ns) 并叠加到 rx_cube
            rx_cube(:, :, :, l_idx) = rx_cube(:, :, :, l_idx) + ...
                reshape(g_rx(:) .* y_l, Mx, My, Ns);
        end
    else
        % ============== (A) 点散射 SI 模式 (原实现) ==============
        u_si = sind(params.theta_SI) * cosd(params.phi_SI);
        v_si = sind(params.theta_SI) * sind(params.phi_SI);
        omega_ax_si = -2 * pi * params.d * u_si / params.lambda;
        omega_ay_si = -2 * pi * params.d * v_si / params.lambda;
        omega_r_si  = -4 * pi * delta_f * params.R_SI / params.c;
        omega_v_si  =  4 * pi * params.Ts * params.v_SI * params.fc / params.c;

        a_rx_x_si = exp(1j * (0:Mx-1).' * omega_ax_si);
        a_rx_y_si = exp(1j * (0:My-1)   * omega_ay_si);
        a_rx_si   = a_rx_x_si * a_rx_y_si;

        phase_n_si = exp(1j * (0:Ns-1).' * omega_r_si);
        phase_l_si = exp(1j * (0:L-1)    * omega_v_si);
        phase_si   = phase_n_si * phase_l_si;

        switch tx_mode
            case 'scalar'
                si_sig = tx_signal;
            case 'mimo'
                ax_tx_x_si = exp(1j * kw * nx_tx * u_si);
                ax_tx_y_si = exp(1j * kw * ny_tx * v_si);
                a_tx_si    = ax_tx_x_si * ax_tx_y_si.';
                conj_atx_si = conj(a_tx_si);
                si_sig = zeros(Ns, L, 'like', tx_signal);
                for ntx_i = 1:Ntx
                    for nty_i = 1:Nty
                        si_sig = si_sig + conj_atx_si(ntx_i, nty_i) * ...
                            squeeze(tx_signal(ntx_i, nty_i, :, :));
                    end
                end
        end

        echo_si = beta_si_abs * (si_sig .* phase_si);
        a_rx_si_mismatch = a_rx_si .* g_rx;
        for l_idx = 1:L
            rx_cube(:,:,:,l_idx) = rx_cube(:,:,:,l_idx) + ...
                a_rx_si_mismatch .* reshape(echo_si(:,l_idx), 1, 1, Ns);
        end
    end
end

% -------------------------- AWGN (分块生成, 降低峰值内存) ----------------
SNR_linear = 10^(params.SNR / 10);
noise_pow  = target_sig_pow / SNR_linear;   % ★ 基于目标回波功率 (不含 SI)
noise_std  = sqrt(noise_pow / 2);
% 按最后一维 (符号维 L) 分块加噪, 避免一次性分配整个噪声矩阵
% 使用 'like' 匹配 rx_cube 的精度 (single/double)
for l_idx = 1:L
    rx_cube(:,:,:,l_idx) = rx_cube(:,:,:,l_idx) + ...
        noise_std * (randn(Mx, My, Ns, 'like', rx_cube) + 1j * randn(Mx, My, Ns, 'like', rx_cube));
end
end
