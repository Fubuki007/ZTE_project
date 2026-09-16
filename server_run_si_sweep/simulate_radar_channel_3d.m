function rx_cube = simulate_radar_channel_3d(tx_signal, params)
% =========================================================================
% SIMULATE_RADAR_CHANNEL_3D  感知回波仿真 (严格按论文公式 (6) + (28))
% -------------------------------------------------------------------------
% 论文: 《毫米波通感实时感知与预警算法方案》
%
% 公式(6):  y_i[l] = Σ_q β_q·b(φ_q,ψ_q)·a^H(φ_q,ψ_q)·x_i[l]·e^{jiω_s(R_q)}·e^{jlω_s(v_q)} + z_i[l]
% 公式(28): + √ρ_SI·H_SI[i]·x_i[l] (自干扰项)
% 公式(50): y_i^{SIC}[l] = y_i[l] - Ĝ_SI[i]·x_i[l]   (数字自干扰消除, IV.B)
% =========================================================================

Mx = params.Mx;
My = params.My;
Ns = params.N;
L  = params.K;
Q  = params.num_targets;
delta_f = params.B / Ns;
lambda  = params.lambda;
d       = params.d;
kw      = 2 * pi * d / lambda;

sz = size(tx_signal);
if isequal(sz, [Ns, L])
    tx_mode = 'scalar';
    Ntx = 1; Nty = 1;
elseif ndims(tx_signal) == 4 && sz(3) == Ns && sz(4) == L
    tx_mode = 'mimo';
    Ntx = sz(1); Nty = sz(2);
else
    error('tx_signal 维度非法');
end
Nt_total = Ntx * Nty;
Nr_total = Mx * My;

rx_cube = zeros(Mx, My, Ns, L, 'like', tx_signal);

mx_vec = (0:Mx-1).';
my_vec = (0:My-1).';
nx_vec = (0:Ntx-1).';
ny_vec = (0:Nty-1).';

% =================== 目标回波 (公式 6) =====================================
for q = 1:Q
    theta_q = params.theta_true(q);
    phi_q   = params.phi_true(q);
    R_q     = params.R_true(q);
    v_q     = params.v_true(q);
    beta_q  = params.alpha(q);
    
    u = sind(theta_q) * cosd(phi_q);
    v = sind(theta_q) * sind(phi_q);
    
    % b: 接收阵列导向矢量 (负指数) — 论文公式(5)
    a_rx_x = exp(-1j * kw * mx_vec * u);
    a_rx_y = exp(-1j * kw * my_vec * v);
    b_vec  = a_rx_x * a_rx_y.';                          % (Mx, My)
    
    % a: 发射阵列导向矢量 (正指数) — 论文公式(5)
    a_tx_x = exp(1j * kw * nx_vec * u);
    a_tx_y = exp(1j * kw * ny_vec * v);
    a_tx   = a_tx_x * a_tx_y.';                          % (Ntx, Nty)
    
    % a^H·x: 一次性内积, 替代逐天线循环 — 论文公式(6) 核心
    switch tx_mode
        case 'scalar'
            tx_eff_q = tx_signal;                        % (Ns, L)
        case 'mimo'
            tx_eff_q = squeeze(sum(conj(a_tx) .* tx_signal, [1 2]));  % (Ns, L)
    end
    
    % 距离/速度相位 — 论文公式(9)
    phase_r = exp(1j * (0:Ns-1).' * (-4*pi*delta_f*R_q / params.c));
    phase_v = exp(1j * (0:L-1)    * (4*pi*params.Ts*v_q*params.fc / params.c));
    echo_q  = beta_q * tx_eff_q .* (phase_r * phase_v);  % (Ns, L)
    
    % 叠加到空间维 — 逐符号循环 (12572 点/符号, 256 次, 内存友好)
    for l_idx = 1:L
        rx_cube(:, :, :, l_idx) = rx_cube(:, :, :, l_idx) + ...
            b_vec .* reshape(echo_q(:, l_idx), 1, 1, Ns);
    end
end

% =================== 自干扰注入 (公式 28) ==================================
target_sig_pow = mean(abs(rx_cube(:)).^2);
use_matrix = false;
beta_si = 0;

if isfield(params, 'enable_SI') && params.enable_SI
    beta_si = params.beta_SI;
    if beta_si == 0, beta_si = realmin; end
    
    use_matrix = isfield(params, 'H_SI_matrix') && ~isempty(params.H_SI_matrix);
    
    if use_matrix
        H_SI_mat = params.H_SI_matrix;
        % 逐符号矩阵乘 (Nr×Nt)×(Nt×Ns)=(Nr×Ns), 256 次, 每次 64×12672
        for l_idx = 1:L
            x_l = reshape(tx_signal(:, :, :, l_idx), Nt_total, Ns);
            y_si_l = beta_si * H_SI_mat * x_l;               % (Nr, Ns)
            rx_cube(:, :, :, l_idx) = rx_cube(:, :, :, l_idx) + ...
                reshape(y_si_l, Mx, My, Ns);
        end
    else
        % 点散射 SI
        u_si = sind(params.theta_SI) * cosd(params.phi_SI);
        v_si = sind(params.theta_SI) * sind(params.phi_SI);
        
        a_rx_x_si = exp(-1j * kw * mx_vec * u_si);
        a_rx_y_si = exp(-1j * kw * my_vec * v_si);
        b_si = a_rx_x_si * a_rx_y_si.';
        
        a_tx_x_si = exp(1j * kw * nx_vec * u_si);
        a_tx_y_si = exp(1j * kw * ny_vec * v_si);
        a_tx_si = a_tx_x_si * a_tx_y_si.';
        
        si_sig = squeeze(sum(conj(a_tx_si) .* tx_signal, [1 2]));
        
        if isfield(params, 'R_SI') && params.R_SI > 0
            r_phase = exp(1j*(0:Ns-1).'*(-4*pi*delta_f*params.R_SI/params.c));
        else
            r_phase = ones(Ns, 1);
        end
        if isfield(params, 'v_SI')
            v_phase = exp(1j*(0:L-1)*(4*pi*params.Ts*params.v_SI*params.fc/params.c));
        else
            v_phase = ones(1, L);
        end
        
        echo_si = beta_si * si_sig .* (r_phase * v_phase);
        for l_idx = 1:L
            rx_cube(:, :, :, l_idx) = rx_cube(:, :, :, l_idx) + ...
                b_si .* reshape(echo_si(:, l_idx), 1, 1, Ns);
        end
    end
end

% =================== 数字自干扰消除 (论文 IV.B, 公式 50) ===================
if isfield(params, 'enable_SIC') && params.enable_SIC && use_matrix
    % A nonzero value models coherent channel/calibration mismatch. For
    % example, 0.01 leaves 1% of the SI amplitude (40 dB power suppression).
    sic_residual_amplitude = 0;
    if isfield(params, 'sic_residual_amplitude') && ...
            ~isempty(params.sic_residual_amplitude)
        sic_residual_amplitude = params.sic_residual_amplitude;
    end
    if ~isscalar(sic_residual_amplitude) || ...
            ~isfinite(sic_residual_amplitude) || ...
            sic_residual_amplitude < 0 || sic_residual_amplitude > 1
        error('sic_residual_amplitude must be a finite scalar in [0, 1].');
    end
    cancellation_amplitude = 1 - sic_residual_amplitude;
    for l_idx = 1:L
        x_l = reshape(tx_signal(:, :, :, l_idx), Nt_total, Ns);
        y_sic_l = cancellation_amplitude * beta_si * H_SI_mat * x_l;
        rx_cube(:, :, :, l_idx) = rx_cube(:, :, :, l_idx) - ...
            reshape(y_sic_l, Mx, My, Ns);
    end
end

% =================== AWGN (公式 6 的 z_i[l]) ================================
SNR_linear = 10^(params.SNR / 10);
noise_pow  = target_sig_pow / SNR_linear;
noise_std  = sqrt(noise_pow / 2);
for l_idx = 1:L
    rx_cube(:, :, :, l_idx) = rx_cube(:, :, :, l_idx) + ...
        noise_std * (randn(Mx, My, Ns, 'like', rx_cube) + ...
                     1j * randn(Mx, My, Ns, 'like', rx_cube));
end
end
