function rx_cube = simulate_radar_channel_3d(tx_signal, params)
%SIMULATE_RADAR_CHANNEL_3D Simulate target echoes, SI, SIC and AWGN.
%   TX_SIGNAL: (Ntx x Nty x N x K); RX_CUBE: (Mx x My x N x K).
%   Matrix SI uses a frequency-flat H_SI_matrix (Mx*My x Ntx*Nty), with
%   MATLAB column-major array flattening. beta_SI multiplies its amplitude.
%   With enable_SIC, an isolated, target-free pilot estimates beta_SI*H_SI
%   by LS before subtraction; sic_use_true_channel uses the ideal matrix.
%   Noise variance is based on target-only power, independent of SI power.

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
if strcmp(tx_mode, 'mimo') && (Ntx ~= params.Ntx || Nty ~= params.Nty)
    error('TX dimensions must match params.Ntx x params.Nty.');
end

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
    
    % RX 导向矢量使用负指数。
    a_rx_x = exp(-1j * kw * mx_vec * u);
    a_rx_y = exp(-1j * kw * my_vec * v);
    b_vec  = a_rx_x * a_rx_y.';                          % (Mx, My)
    
    % TX 导向矢量使用正指数，和发射波形函数的阵元顺序一致。
    a_tx_x = exp(1j * kw * nx_vec * u);
    a_tx_y = exp(1j * kw * ny_vec * v);
    a_tx   = a_tx_x * a_tx_y.';                          % (Ntx, Nty)
    
    % a^H*x 在 TX 阵元维求和，得到每个子载波/符号的目标回波幅度。
    switch tx_mode
        case 'scalar'
            tx_eff_q = tx_signal;                        % (Ns, L)
        case 'mimo'
            tx_eff_q = squeeze(sum(conj(a_tx) .* tx_signal, [1 2]));  % (Ns, L)
    end
    
    % 距离相位沿子载波变化，速度相位沿 OFDM 符号变化。
    phase_r = exp(1j * (0:Ns-1).' * (-4*pi*delta_f*R_q / params.c));
    phase_v = exp(1j * (0:L-1)    * (4*pi*params.Ts*v_q*params.fc / params.c));
    echo_q  = beta_q * tx_eff_q .* (phase_r * phase_v);  % (Ns, L)
    
    % 叠加到空间维 — 逐符号循环 (12572 点/符号, 256 次, 内存友好)
    for l_idx = 1:L
        rx_cube(:, :, :, l_idx) = rx_cube(:, :, :, l_idx) + ...
            b_vec .* reshape(echo_q(:, l_idx), 1, 1, Ns);
    end
end

% =================== SI injection (Eq. 28) ==================================
target_sig_pow = mean(abs(rx_cube(:)).^2);

% Noise level used for both data AWGN and the SIC pilot-based LS estimate.
SNR_linear = 10^(params.SNR / 10);
noise_pow  = target_sig_pow / SNR_linear;
noise_std  = sqrt(noise_pow / 2);

use_matrix = isfield(params, 'H_SI_matrix') && ~isempty(params.H_SI_matrix);
H_SI_mat   = [];
if use_matrix
    H_SI_mat = params.H_SI_matrix;
    if ~strcmp(tx_mode, 'mimo') || ~isequal(size(H_SI_mat), [Mx*My, Nt_total])
        error('H_SI_matrix must be (Mx*My) x (Ntx*Nty) in MIMO mode.');
    end
end
beta_si = 0;
if isfield(params, 'beta_SI')
    beta_si = params.beta_SI;
end

if isfield(params, 'enable_SI') && params.enable_SI
    if use_matrix
        % Per-symbol matrix multiply (Nr x Nt)*(Nt x Ns)=(Nr x Ns).
        for l_idx = 1:L
            x_l = reshape(tx_signal(:, :, :, l_idx), Nt_total, Ns);
            y_si_l = beta_si * H_SI_mat * x_l;               % (Nr, Ns)
            rx_cube(:, :, :, l_idx) = rx_cube(:, :, :, l_idx) + ...
                reshape(y_si_l, Mx, My, Ns);
        end
    else
        % Point-scatterer SI model.
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

% =================== Digital SIC ===========================================
% A target-free pilot estimates G_eff = beta_SI*H_SI. No subtraction is
% performed on the no-SI baseline, and SIC requires the matrix SI model.
if isfield(params, 'enable_SIC') && params.enable_SIC && ...
        isfield(params, 'enable_SI') && params.enable_SI
    if ~use_matrix
        error('Digital SIC requires H_SI_matrix (matrix SI model).');
    end
    if isfield(params, 'sic_use_true_channel') && params.sic_use_true_channel
        G_sic = beta_si * H_SI_mat;
    else
        G_sic = estimate_si_channel_ls(params, H_SI_mat, beta_si, noise_std);
    end

    for l_idx = 1:L
        x_l = reshape(tx_signal(:, :, :, l_idx), Nt_total, Ns);
        y_sic_l = G_sic * x_l;
        rx_cube(:, :, :, l_idx) = rx_cube(:, :, :, l_idx) - ...
            reshape(y_sic_l, Mx, My, Ns);
    end
end

% =================== AWGN (z_i[l] in Eq. 6) =================================
for l_idx = 1:L
    rx_cube(:, :, :, l_idx) = rx_cube(:, :, :, l_idx) + ...
        noise_std * (randn(Mx, My, Ns, 'like', rx_cube) + ...
                     1j * randn(Mx, My, Ns, 'like', rx_cube));
end
end

% Pilot-only LS estimate: Y0 = beta_SI*H_SI*X0 + AWGN.
function G_hat = estimate_si_channel_ls(params, H_SI_mat, beta_si, noise_std)
    Nt = size(H_SI_mat, 2);
    Nr = size(H_SI_mat, 1);

    if isfield(params, 'SIC_pilot_len') && ~isempty(params.SIC_pilot_len)
        Lp = max(Nt, round(params.SIC_pilot_len));
    else
        Lp = 64;
    end

    % A supplied pilot overrides the generated 16-QAM pilot.
    if isfield(params, 'SIC_pilot') && ~isempty(params.SIC_pilot)
        if size(params.SIC_pilot, 1) ~= Nt || size(params.SIC_pilot, 2) < Nt
            error('SIC_pilot must have Nt rows and at least Nt columns.');
        end
        X0 = params.SIC_pilot(:, 1:min(Lp, size(params.SIC_pilot, 2)));
        Lp = size(X0, 2);
    elseif exist('qammod', 'file') == 2
        pilot_idx = randi([0 15], Nt, Lp);
        X0 = qammod(pilot_idx, 16, 'UnitAveragePower', true);
    else
        % Fallback without the Communications Toolbox: unit-power Gaussian.
        X0 = (randn(Nt, Lp) + 1j * randn(Nt, Lp)) / sqrt(2);
    end

    % The calibration pilot contains SI only, without target echoes.
    Y0 = beta_si * (H_SI_mat * X0) + ...
         noise_std * (randn(Nr, Lp) + 1j * randn(Nr, Lp));

    % LS estimate of the effective SI channel.
    if rcond(X0 * X0') < 1e-12
        G_hat = Y0 / X0;    % QR-based fallback for ill-conditioned pilot
    else
        G_hat = Y0 * X0' / (X0 * X0');
    end
end
