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

rx_cube = zeros(Mx, My, Ns, L);

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
    omega_ax = -2 * pi * params.d * u    / params.lambda;
    omega_ay = -2 * pi * params.d * vdir / params.lambda;
    omega_r  = -4 * pi * delta_f * params.R_true(q) / params.c;
    omega_v  =  4 * pi * params.Ts * params.v_true(q) * params.fc / params.c;

    a_rx_x = exp(1j * (0:Mx-1).' * omega_ax);
    a_rx_y = exp(1j * (0:My-1)   * omega_ay);
    a_rx   = a_rx_x * a_rx_y;                  % (Mx, My)

    phase_n = exp(1j * (0:Ns-1).' * omega_r);
    phase_l = exp(1j * (0:L-1)    * omega_v);
    phase   = phase_n * phase_l;               % (Ns, L)

    % 发射端系数 a_tx^H(θ_q, φ_q) · x_i[l]   (论文式 (7a) / 原始回波式 (3))
    switch tx_mode
        case 'scalar'
            ax_q_sig = tx_signal;              % (Ns, L)
        case 'mimo'
            ax_tx_x = exp(1j * kw * nx_tx * u);      % (Ntx, 1)
            ax_tx_y = exp(1j * kw * ny_tx * vdir);   % (Nty, 1)
            a_tx_q  = ax_tx_x * ax_tx_y.';           % (Ntx, Nty)  (无共轭)
            % a_tx^H · x  按 (Ntx, Nty) 两维 sum: sum_{nx, ny} conj(a_tx) .* x
            conj_atx = conj(a_tx_q);
            % (Ntx, Nty, Ns, L) 与 (Ntx, Nty, 1, 1) 相乘后对前两维求和
            prod_nt = tx_signal .* reshape(conj_atx, Ntx, Nty, 1, 1);
            ax_q_sig = reshape(sum(sum(prod_nt, 1), 2), Ns, L);
    end

    echo_q = params.alpha(q) * (ax_q_sig .* phase);
    a_rx_mismatch = a_rx .* g_rx;
    rx_cube = rx_cube + reshape(a_rx_mismatch, Mx, My, 1, 1) ...
                     .* reshape(echo_q,       1,  1,  Ns, L);
end

% -------------------------- 可选 SI 项 -----------------------------------
if isfield(params, 'enable_SI') && params.enable_SI
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
            prod_nt_si  = tx_signal .* reshape(conj_atx_si, Ntx, Nty, 1, 1);
            si_sig      = reshape(sum(sum(prod_nt_si, 1), 2), Ns, L);
    end

    beta_si_abs = params.beta_SI;
    if isfield(params, 'beta_SI_abs'), beta_si_abs = params.beta_SI_abs; end
    if beta_si_abs == 0, beta_si_abs = realmin; end

    echo_si = beta_si_abs * (si_sig .* phase_si);
    rx_cube = rx_cube + reshape(a_rx_si .* g_rx, Mx, My, 1, 1) ...
                     .* reshape(echo_si,         1,  1,  Ns, L);
end

% -------------------------- AWGN -----------------------------------------
SNR_linear = 10^(params.SNR / 10);
sig_pow    = mean(abs(rx_cube(:)).^2);
noise_pow  = sig_pow / SNR_linear;
noise      = sqrt(noise_pow / 2) * (randn(size(rx_cube)) + 1j * randn(size(rx_cube)));
rx_cube    = rx_cube + noise;
end
