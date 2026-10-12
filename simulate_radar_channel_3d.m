function [rx_cube, sim_info] = simulate_radar_channel_3d(tx_signal, params)
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
sim_info = struct();

mx_vec = (0:Mx-1).';
my_vec = (0:My-1).';
nx_vec = (0:Ntx-1).';
ny_vec = (0:Nty-1).';

% =================== 目标回波 (公式 6) =====================================
% Optional RIS-assisted target path.  The model is deliberately injected
% before SI/noise so that the no-SI experiment measures a real sensing-gain
% effect instead of reusing the RIS-SIC objective.
ris_model = [];
if isfield(params, 'ris_target_model') && ~isempty(params.ris_target_model)
    ris_model = params.ris_target_model;
    if ~isfield(ris_model, 'direct_beam') || ~isfield(ris_model, 'ris_beam')
        error('params.ris_target_model must contain direct_beam and ris_beam');
    end
    if size(ris_model.direct_beam, 1) ~= Q || size(ris_model.direct_beam, 2) ~= Ns
        error('RIS target model direct_beam must be Q x Ns');
    end
end

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

    % RIS-assisted target path.  For the current single-stream waveform the
    % direct beam coefficient is known, hence the RIS path can be added as a
    % per-subcarrier beam-ratio without storing a 4-D antenna channel.
    if ~isempty(ris_model)
        if ~isfield(ris_model, 'phi') || isempty(ris_model.phi)
            phi_ris = zeros(size(ris_model.ris_beam, 1), 1);
        else
            phi_ris = ris_model.phi(:);
        end
        ris_q = squeeze(sum(ris_model.ris_beam(:, q, :) .* reshape(phi_ris, [], 1, 1), 1));
        ris_q = reshape(ris_q, Ns, 1);
        direct_q = reshape(ris_model.direct_beam(q, :).', Ns, 1);
        if any(abs(direct_q) < 1e-12)
            error('RIS target model has a near-zero direct beam coefficient');
        end
        tx_eff_q = tx_eff_q .* ((direct_q + ris_q) ./ direct_q);
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

% =================== SI injection (Eq. 28) ==================================
target_sig_pow = mean(abs(rx_cube(:)).^2);

% Noise level used for both data AWGN and the SIC pilot-based LS estimate.
SNR_linear = 10^(params.SNR / 10);
if isfield(params, 'noise_power_override') && ~isempty(params.noise_power_override)
    noise_pow = params.noise_power_override;
elseif isfield(params, 'noise_reference_target_power') && ...
        ~isempty(params.noise_reference_target_power)
    noise_pow = params.noise_reference_target_power / SNR_linear;
else
    noise_pow = target_sig_pow / SNR_linear;
end
noise_std  = sqrt(noise_pow / 2);
sim_info.target_signal_power = target_sig_pow;
sim_info.data_noise_power = noise_pow;
sim_info.sic = struct('applied', false);

% use_matrix is needed by the digital-SIC block even when SI injection is
% disabled, so define it before the enable_SI branch.
use_matrix = isfield(params, 'H_SI_matrix') && ~isempty(params.H_SI_matrix);
H_SI_mat   = [];
if use_matrix
    H_SI_mat = params.H_SI_matrix;
end
beta_si = 0;
if isfield(params, 'beta_SI')
    beta_si = params.beta_SI;
end

si_enabled = isfield(params, 'enable_SI') && params.enable_SI;
if si_enabled
    if beta_si == 0, beta_si = realmin; end

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

% =================== Digital SIC (paper IV.B, Eq. 50) =======================
% Same approach as SIC.m: estimate the effective SI channel
%   G_eff = beta_SI * H_SI
% with a known pilot using least squares (LS), then subtract G_hat * x.
% Set params.sic_use_true_channel = true to use the legacy perfect-SIC
% (genie-aided) behavior instead.
if isfield(params, 'enable_SIC') && params.enable_SIC && use_matrix && si_enabled
    G_true = beta_si * H_SI_mat;
    if isfield(params, 'sic_use_true_channel') && params.sic_use_true_channel
        G_sic = G_true;
        sic_info = struct( ...
            'mode', 'true_channel', ...
            'requested_nmse_db', -Inf, ...
            'achieved_nmse_db', -Inf, ...
            'pilot_noise_power', 0, ...
            'pilot_length', 0, ...
            'pilot_gram_rcond', NaN);
    else
        X0 = select_sic_pilot(params, Nt_total);
        target_nmse_db = [];
        if isfield(params, 'sic_error_db')
            target_nmse_db = params.sic_error_db;
        end
        [G_sic, sic_info] = estimate_si_channel_ls( ...
            G_true, X0, noise_std, target_nmse_db);
    end

    si_energy = 0;
    residual_energy = 0;
    for l_idx = 1:L
        x_l = reshape(tx_signal(:, :, :, l_idx), Nt_total, Ns);
        y_sic_l = G_sic * x_l;
        y_si_l = G_true * x_l;
        si_energy = si_energy + sum(abs(y_si_l(:)).^2);
        residual_energy = residual_energy + ...
            sum(abs(y_si_l(:) - y_sic_l(:)).^2);
        rx_cube(:, :, :, l_idx) = rx_cube(:, :, :, l_idx) - ...
            reshape(y_sic_l, Mx, My, Ns);
    end
    normalization = Nr_total * Ns * L;
    sic_info.applied = true;
    sic_info.si_power_before = si_energy / normalization;
    sic_info.si_power_after = residual_energy / normalization;
    sic_info.suppression_db = 10 * log10( ...
        max(sic_info.si_power_before, realmin) / ...
        max(sic_info.si_power_after, realmin));
    sim_info.sic = sic_info;
end

% =================== AWGN (z_i[l] in Eq. 6) =================================
% SNR=Inf is used to construct a reusable noise-free target cube. Skipping
% zero-valued random draws is exactly equivalent and avoids substantial work.
if noise_std > 0
    for l_idx = 1:L
        rx_cube(:, :, :, l_idx) = rx_cube(:, :, :, l_idx) + ...
            noise_std * (randn(Mx, My, Ns, 'like', rx_cube) + ...
                         1j * randn(Mx, My, Ns, 'like', rx_cube));
    end
end
end

function X0 = select_sic_pilot(params, Nt)
    if isfield(params, 'SIC_pilot_len') && ~isempty(params.SIC_pilot_len)
        Lp = max(Nt, round(params.SIC_pilot_len));
    else
        Lp = 64;    % same order as L=64 in SIC.m
    end

    % Use a pre-generated fixed pilot if supplied, otherwise draw a random
    % 16-QAM pilot (same modulation as SIC.m).
    if isfield(params, 'SIC_pilot') && ~isempty(params.SIC_pilot) && ...
       size(params.SIC_pilot, 1) == Nt && size(params.SIC_pilot, 2) >= Nt
        X0 = params.SIC_pilot(:, 1:min(Lp, size(params.SIC_pilot, 2)));
    elseif exist('qammod', 'file') == 2
        pilot_idx = randi([0 15], Nt, Lp);
        X0 = qammod(pilot_idx, 16, 'UnitAveragePower', true);
    else
        % Fallback without the Communications Toolbox: unit-power Gaussian.
        X0 = (randn(Nt, Lp) + 1j * randn(Nt, Lp)) / sqrt(2);
    end

end
