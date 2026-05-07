function rx_cube = simulate_radar_channel_3d(tx_signal, params)
Mx = params.Mx;
My = params.My;
Ns = params.N;
L = params.K;
Q = params.num_targets;
rx_cube = zeros(Mx, My, Ns, L);
delta_f = params.B / Ns;

% 可选：接收阵列幅相失配（用于形成高SNR误差地板）
g_rx = ones(Mx, My);
if isfield(params, 'array_mismatch') && isfield(params.array_mismatch, 'enable') && params.array_mismatch.enable
    amp_sigma_db = 0.0;
    phase_sigma_deg = 0.0;
    if isfield(params.array_mismatch, 'amp_sigma_db')
        amp_sigma_db = params.array_mismatch.amp_sigma_db;
    end
    if isfield(params.array_mismatch, 'phase_sigma_deg')
        phase_sigma_deg = params.array_mismatch.phase_sigma_deg;
    end

    amp_err_db = amp_sigma_db * randn(Mx, My);
    amp_err_lin = 10.^(amp_err_db / 20);
    phase_err = deg2rad(phase_sigma_deg * randn(Mx, My));
    g_rx = amp_err_lin .* exp(1j * phase_err);
end

for q = 1:Q
    u = sind(params.theta_true(q)) * cosd(params.phi_true(q));
    vdir = sind(params.theta_true(q)) * sind(params.phi_true(q));
    omega_ax = -2 * pi * params.d * u / params.lambda;
    omega_ay = -2 * pi * params.d * vdir / params.lambda;
    omega_r = -4 * pi * delta_f * params.R_true(q) / params.c;
    omega_v = 4 * pi * params.Ts * params.v_true(q) * params.fc / params.c;
    a_rx_x = exp(1j * (0:Mx-1).' * omega_ax);
    a_rx_y = exp(1j * (0:My-1) * omega_ay);
    a_rx = a_rx_x * a_rx_y;
    phase_n = exp(1j * (0:Ns-1).' * omega_r);
    phase_l = exp(1j * (0:L-1) * omega_v);
    phase = phase_n * phase_l;
    echo_q = params.alpha(q) * (tx_signal .* phase);
    a_rx_mismatch = a_rx .* g_rx;
    rx_cube = rx_cube + reshape(a_rx_mismatch, Mx, My, 1, 1) .* reshape(echo_q, 1, 1, Ns, L);
end

% 可选SI项：按用户要求加入约10lambda距离、10°/10°角度的近端散射
if isfield(params, 'enable_SI') && params.enable_SI
    u_si = sind(params.theta_SI) * cosd(params.phi_SI);
    v_si = sind(params.theta_SI) * sind(params.phi_SI);
    omega_ax_si = -2 * pi * params.d * u_si / params.lambda;
    omega_ay_si = -2 * pi * params.d * v_si / params.lambda;
    omega_r_si = -4 * pi * delta_f * params.R_SI / params.c;
    omega_v_si = 4 * pi * params.Ts * params.v_SI * params.fc / params.c;
    a_rx_x_si = exp(1j * (0:Mx-1).' * omega_ax_si);
    a_rx_y_si = exp(1j * (0:My-1) * omega_ay_si);
    a_rx_si = a_rx_x_si * a_rx_y_si;
    phase_n_si = exp(1j * (0:Ns-1).' * omega_r_si);
    phase_l_si = exp(1j * (0:L-1) * omega_v_si);
    phase_si = phase_n_si * phase_l_si;

    beta_si_abs = params.beta_SI;
    if isfield(params, 'beta_SI_abs')
        beta_si_abs = params.beta_SI_abs;
    end
    if beta_si_abs == 0
        beta_si_abs = realmin;
    end
    echo_si = beta_si_abs * (tx_signal .* phase_si);
    rx_cube = rx_cube + reshape(a_rx_si .* g_rx, Mx, My, 1, 1) .* reshape(echo_si, 1, 1, Ns, L);
end
SNR_linear = 10^(params.SNR / 10);
sig_pow = mean(abs(rx_cube(:)).^2);
noise_pow = sig_pow / SNR_linear;
noise = sqrt(noise_pow / 2) * (randn(size(rx_cube)) + 1j * randn(size(rx_cube)));
rx_cube = rx_cube + noise;
end
