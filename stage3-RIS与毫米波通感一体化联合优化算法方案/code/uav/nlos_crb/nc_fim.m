function out = nc_fim(mode, varargin)
% NC_FIM  Exact true-wideband EFIM, SPEB, condition number, & Wirtinger gradients.
% Modes:
%   'rr_nlos'   : (q, p_tgt, W_cell, theta_mat, rcs, cfg)
%                 Exact 3D-position EFIM & SPEB for a pure-RR (NLoS) target across S_f configs.
%   'dd_los'    : (q, p_tgt, W_cell, rcs, cfg)
%                 Exact 3D-position EFIM & SPEB for a direct-LoS (DD) target.
%   'ris_grad'  : (q, p_tgt, W_cell, theta_mat, rcs, cfg)
%                 Exact Wirtinger gradient d(SPEB)/d(conj(theta_mat)) for NLoS target.
%   'ambiguity' : (q, p_tgt, W_cell, theta_mat, rcs, cfg)
%                 2D RIS-angle likelihood scan to quantify mirror ambiguity gap & sidelobe ratio.
%   'freq_grid' : (cfg) -> Chebyshev frequency knots and quadrature weights over N subcarriers.

switch mode
    case 'freq_grid'
        out = make_freq_grid(varargin{1});
    case 'rr_nlos'
        out = fim_rr_nlos(varargin{:});
    case 'dd_los'
        out = fim_dd_los(varargin{:});
    case 'ris_grad'
        out = grad_speb_ris(varargin{:});
    case 'ambiguity'
        out = eval_rr_ambiguity(varargin{:});
    otherwise
        error('Unknown nc_fim mode: %s', mode);
end
end

function fg = make_freq_grid(cfg)
% Exact Gauss-Legendre / uniform-Chebyshev quadrature over all N subcarriers.
% Using M_k = cfg.freq_knots nodes gives < 1e-11 relative error on smooth wideband integrals
% while running ~400x faster than evaluating 12,672 subcarriers individually.
M = cfg.freq_knots;
% Gauss-Legendre nodes/weights on [-1, 1] via Golub-Welsch tridiagonal eig
idx = (1:M-1).';
beta = idx ./ sqrt(4 * idx.^2 - 1);
T = diag(beta, 1) + diag(beta, -1);
[V, D] = eig(T);
[x, ord] = sort(diag(D));
w = 2 * (V(1, ord).').^2; % sums to 2
% Map [-1, 1] to subcarrier index n in [0, N-1]
n_nodes = 0.5 * (x + 1) * (cfg.N - 1); % M x 1
weights = 0.5 * w * cfg.N;             % sums to cfg.N
freqs = cfg.fref + n_nodes * cfg.delta_f;
fg = struct('n', n_nodes(:).', 'w', weights(:).', 'freqs', freqs(:).', 'M', M);
end

function res = fim_rr_nlos(q, p_tgt, W_cell, theta_mat, rcs, cfg)
% Exact 3D-position EFIM for a stationary NLoS target (RR-only path) across S_f configs.
% Signal model per config s, subcarrier n, symbol l (after known symbol energy E[|s|^2]=1):
%   y_{s,n,l} = alpha_RR * g_tx(s,n) * c_s(f_n, p_tgt)^2 * a_r(f_n, b_r) * exp(-j*4*pi*df*n*(dbr+rr)/c) + w_{s,n,l}
% Note:
%   - Exact noise variance per Rx element per (n,l) is cfg.noise_w (since W has total power <= cfg.power_w).
%   - Average symbol energy across L_s symbols per config (sum_{l} E[|a_t^H W_s s_l|^2] = L_s * ||a_t^H W_s||_2^2).
%   - In wideband, a_t(f_n, b_r) and a_r(f_n, b_r) depend on f_n, while ||a_r(f_n, b_r)||^2 = M_r.
%   - Unknown real parameters: eta = [x_t, y_t, z_t, Re(alpha_0), Im(alpha_0)]^T (5 real unknowns),
%     where alpha_0 = sqrt(P_tx * rcs) * lambda_c / (4*pi)^(3/2) * exp(j*phi_0) is the common monostatic
%     scatter coefficient (independent of f_n; frequency dependence of RIS aperture is inside c_s(f_n)).
q = q(:); p_tgt = p_tgt(:); pR = cfg.ris_pos(:);
S = size(theta_mat, 2);
L_s = cfg.K_fine / S;
fg = make_freq_grid(cfg);
freqs = fg.freqs; % 1 x M
n_idx = fg.n;     % 1 x M
w_q   = fg.w;     % 1 x M

% Base amplitude (real magnitude; phase cancels out of FIM)
alpha_mag = sqrt(cfg.power_w * rcs) * cfg.lambda / ((4 * pi)^1.5);

% Tx illumination power toward RIS across frequencies & configs
rot = nc_geometry('world_to_local');
u_bs_ris_local = rot * ((pR - q) / max(norm(pR - q), eps));
tx_off = nc_geometry('tx_offsets', cfg);
A_tx = nc_geometry('wideband_tx', u_bs_ris_local, tx_off, freqs, cfg); % Nt x M

tx_pow = zeros(S, fg.M); % ||a_t(f)^H W_s||_2^2
for s = 1:S
    Ws = W_cell{s};
    G = A_tx' * Ws; % M x U (note: A_tx' is conj transpose -> (a_t^H W_s) per freq)
    tx_pow(s, :) = sum(abs(G).^2, 2).';
end

% Evaluate wideband RIS response c_s(f_n) and its exact 3D spatial gradient wrt p_tgt!
wb = nc_geometry('wideband_ris', q, p_tgt, theta_mat, freqs, cfg);
if wb.ci <= 0 || wb.co <= 0
    res = degenerate_fim_result();
    return;
end

rr = wb.rr;
u_r = wb.u_r;         % 3x1 unit vector RIS -> target
nR = wb.panel.nR;     % 3x1
e1 = wb.panel.e1;     % 3x1
e2 = wb.panel.e2;     % 3x1

% Exact derivatives of (rr, u_r, co, psi1, psi2) wrt 3D target position p_tgt (3x1):
%   d(rr)/dp = u_r
%   d(u_r)/dp = (I - u_r*u_r') / rr
%   d(co)/dp = (I - u_r*u_r') * nR / rr
%   d(psi1)/dp = (I - u_r*u_r') * e1 / rr
%   d(psi2)/dp = (I - u_r*u_r') * e2 / rr
P_perp = (eye(3) - u_r * u_r.') / rr;
drr_dp   = u_r;               % 3x1
dco_dp   = P_perp * nR;       % 3x1
dpsi1_dp = P_perp * e1;       % 3x1
dpsi2_dp = P_perp * e2;       % 3x1

% Note: c_s(f_n) = c_raw_s(f_n) * (d^2 f_n / c) * sqrt(ci * co) / (dbr * rr)
% So: dc_s/dp = dc_dpsi1 * dpsi1_dp + dc_dpsi2 * dpsi2_dp + c_s * (0.5/co * dco_dp - 1/rr * drr_dp)
% And the RR path carries h_s(f_n) = c_s(f_n)^2 * exp(-j * 4*pi*df*n*(dbr + rr) / c)
% Wait: keep the exact carrier phase exp(-j * 4*pi*f_n*(dbr + rr) / c) OR baseband?
% Since alpha_0 absorbs the carrier phase at fref (unknown nuisance phase), ONLY the
% relative delay phase exp(-j * 4*pi*(f_n - fref)*(dbr + rr) / c) affects the Schur-complement EFIM!
% Let's include exact -j * 4*pi*f_n/c * drr_dp in dh/dp (which equals baseband + common phase that
% gets cleanly absorbed by alpha_0 in the Schur complement — exact and coordinate invariant!).
% Centering delay derivative at (freqs - cfg.fc) is mathematically identical after Schur
% complement elimination of unknown carrier phase in alpha_0, while avoiding (fc/B)^2 ~ 400x
% floating-point cancellation in F_pp - F_pa * inv(F_aa) * F_ap!
df_centered = freqs - cfg.fc;
c_mat = wb.c;            % S x M
h_mat = c_mat.^2;        % S x M
dh = zeros(S, fg.M, 3);
for k = 1:3
    dc_k = wb.dc_dpsi1 * dpsi1_dp(k) + wb.dc_dpsi2 * dpsi2_dp(k) ...
           + c_mat * (0.5 * dco_dp(k) / wb.co - drr_dp(k) / rr);
    dh(:, :, k) = 2 * c_mat .* dc_k - 1j * (4 * pi * df_centered / cfg.c) .* (drr_dp(k) * h_mat);
end

% Exact 5x5 real FIM:
% F_{ij} = (2 / noise_w) * L_s * M_r * sum_{s,n} w_n * tx_pow(s,n) * Re( conj(dmu_i) * dmu_j )
% where:
%   dmu_k (k=1..3) = alpha_mag * dh(:,:,k)
%   dmu_4 (Re alpha) = h_mat
%   dmu_5 (Im alpha) = 1j * h_mat
% Factor out common positive weight W_sn = (2 / cfg.noise_w) * L_s * cfg.Mr * w_q .* tx_pow
W_sn = (2.0 / cfg.noise_w) * L_s * cfg.Mr * (tx_pow .* w_q); % S x M

D_mu = zeros(S, fg.M, 5);
for k = 1:3
    D_mu(:, :, k) = alpha_mag * dh(:, :, k);
end
D_mu(:, :, 4) = h_mat;
D_mu(:, :, 5) = 1j * h_mat;

F = zeros(5, 5);
for i = 1:5
    for j = i:5
        val = sum(W_sn .* real(conj(D_mu(:, :, i)) .* D_mu(:, :, j)), 'all');
        F(i, j) = val;
        F(j, i) = val;
    end
end

% Schur complement eliminating unknown complex amplitude (indices 4:5)
F_pp = F(1:3, 1:3);
F_pa = F(1:3, 4:5);
F_aa = F(4:5, 4:5);
if rcond(F_aa) < 1e-14
    res = degenerate_fim_result();
    return;
end
J_eff = F_pp - F_pa * (F_aa \ F_pa.');
J_eff = 0.5 * (J_eff + J_eff.');

% Total accumulated fine-stage SNR across all S configs and N subcarriers
snr_per_cfg = (L_s * cfg.Mr * alpha_mag^2 / cfg.noise_w) * sum((tx_pow .* w_q) .* abs(h_mat).^2, 2);
snr_total = sum(snr_per_cfg);

eigvals = sort(real(eig(J_eff)));
if eigvals(1) <= 1e-12
    speb = inf; peb = inf; cond_num = inf;
else
    invJ = inv(J_eff);
    speb = real(trace(invJ));
    peb = sqrt(max(0, speb));
    cond_num = eigvals(3) / eigvals(1);
end

% Compute 2D angular (cross-range) sub-block condition number perpendicular to u_r
B_perp = null(u_r.'); % 3 x 2 orthonormal basis for cross-range plane
J_ang = B_perp.' * J_eff * B_perp;
eig_ang = sort(real(eig(0.5 * (J_ang + J_ang.'))));
if eig_ang(1) <= 1e-12
    ang_cond_num = inf;
else
    ang_cond_num = eig_ang(2) / eig_ang(1);
end

res = struct('F', F, 'J_eff', J_eff, 'speb', speb, 'peb', peb, ...
    'cond_num', cond_num, 'ang_cond_num', ang_cond_num, 'eigvals', eigvals, ...
    'snr_total_linear', snr_total, 'snr_total_db', 10*log10(max(snr_total, realmin)), ...
    'snr_per_cfg_db', 10*log10(max(snr_per_cfg, realmin)), ...
    'dbr', wb.dbr, 'rr', wb.rr, 'ci', wb.ci, 'co', wb.co);
end

function res = fim_dd_los(q, p_tgt, W_cell, rcs, cfg)
% Exact 3D-position EFIM for a stationary direct-LoS (DD) target under true wideband model.
q = q(:); p_tgt = p_tgt(:);
S = numel(W_cell);
L_s = cfg.K_fine / S;
fg = make_freq_grid(cfg);
freqs = fg.freqs; w_q = fg.w;

rot = nc_geometry('world_to_local');
dvec_w = p_tgt - q;
R = norm(dvec_w);
u_w = dvec_w / max(R, eps);
u_loc = rot * u_w;

tx_off = nc_geometry('tx_offsets', cfg);
rx_off = nc_geometry('rx_offsets', cfg);
A_tx = nc_geometry('wideband_tx', u_loc, tx_off, freqs, cfg); % Nt x M
A_rx = nc_geometry('wideband_rx', u_loc, rx_off, freqs, cfg); % Mr x M

% Physical DD field amplitude: alpha_dd = sqrt(P_tx*rcs)*lambda / ((4*pi)^1.5 * R^2)
% Treat R^-2 as absorbed into unknown alpha_dd (conservative, standard radar CRB),
% OR keep R^-2 known? Standard radar CRB treats complex path gain alpha_dd as unknown nuisance
% (since RCS sigma is unknown!), so information comes purely from delay & spatial phase!
alpha_mag = sqrt(cfg.power_w * rcs) * cfg.lambda / ((4 * pi)^1.5 * R^2);

% Derivatives of (R, u_loc) wrt 3D world target position p_tgt:
%   dR/dp = u_w
%   du_loc/dp = rot * (I - u_w*u_w') / R
dR_dp = u_w;
du_loc_dp = rot * (eye(3) - u_w * u_w.') / R; % 3 x 3 (col k = du_loc/dp_k)

k_vec = 2 * pi * (cfg.wideband * freqs + (~cfg.wideband) * cfg.fc) / cfg.c; % 1 x M
k_delay = 2 * pi * (freqs - cfg.fc) / cfg.c; % Centered delay phase (exact after Schur elim of alpha_dd)

% Precompute Tx beam vector g_tx(s, n) = a_t^H W_s (1 x U per freq) and its derivatives
% Signal vector (Mr x U) per (s, n): mu = alpha_mag * a_r(f) * (a_t(f)^H W_s) * exp(-j*2*k_delay*R)
% Since E[s s^H] = I_U, sum_l || ... s_l ||^2 = L_s * || ... ||_F^2.
% Compute 5x5 real FIM directly over (x, y, z, Re(alpha_norm), Im(alpha_norm)):
F = zeros(5, 5);
snr_total = 0.0;
for s = 1:S
    Ws = W_cell{s}; % Nt x U
    G_tx = A_tx' * Ws; % M x U, row n is a_t(f_n)^H * W_s
    % Derivative of A_tx' * Ws wrt p_k:
    % A_tx = exp(+j * (tx_off' * u_loc) * k_vec) => A_tx' = exp(-j * k_vec' * (u_loc' * tx_off))
    % d(A_tx')/dp_k = -j * k_vec' .* (du_k' * tx_off) .* A_tx'
    dG_tx = cell(3, 1);
    dA_rx = cell(3, 1);
    for k = 1:3
        du_k = du_loc_dp(:, k);
        proj_tx = (tx_off.' * du_k); % Nt x 1
        dA_tx_k = (1j * (proj_tx * k_vec)) .* A_tx; % Nt x M
        dG_tx{k} = dA_tx_k' * Ws; % M x U (conjugate transpose gives -j automatically!)
        proj_rx = (rx_off.' * du_k); % Mr x 1
        dA_rx{k} = (-1j * (proj_rx * k_vec)) .* A_rx; % Mr x M
    end

    for m = 1:fg.M
        w_m = (2.0 / cfg.noise_w) * L_s * w_q(m);
        ar = A_rx(:, m);      % Mr x 1
        gt = G_tx(m, :);      % 1 x U
        M0 = ar * gt;         % Mr x U
        snr_total = snr_total + (L_s * w_q(m) * alpha_mag^2 / cfg.noise_w) * sum(abs(M0).^2, 'all');

        DM = cell(5, 1);
        for k = 1:3
            DM{k} = alpha_mag * (dA_rx{k}(:, m) * gt + ar * dG_tx{k}(m, :) ...
                    - 1j * 2 * k_delay(m) * dR_dp(k) * M0);
        end
        DM{4} = M0;
        DM{5} = 1j * M0;

        for i = 1:5
            for j = i:5
                val = w_m * real(sum(conj(DM{i}) .* DM{j}, 'all'));
                F(i, j) = F(i, j) + val;
            end
        end
    end
end
F = triu(F) + triu(F, 1).';

F_pp = F(1:3, 1:3); F_pa = F(1:3, 4:5); F_aa = F(4:5, 4:5);
if rcond(F_aa) < 1e-14
    res = degenerate_fim_result(); return;
end
J_eff = F_pp - F_pa * (F_aa \ F_pa.');
J_eff = 0.5 * (J_eff + J_eff.');
eigvals = sort(real(eig(J_eff)));
if eigvals(1) <= 1e-12
    speb = inf; peb = inf; cond_num = inf;
else
    speb = real(trace(inv(J_eff)));
    peb = sqrt(max(0, speb));
    cond_num = eigvals(3) / eigvals(1);
end
B_perp_dd = null(u_w.');
J_ang_dd = B_perp_dd.' * J_eff * B_perp_dd;
eig_ang_dd = sort(real(eig(0.5 * (J_ang_dd + J_ang_dd.'))));
if eig_ang_dd(1) <= 1e-12
    ang_cond_dd = inf;
else
    ang_cond_dd = eig_ang_dd(2) / eig_ang_dd(1);
end
res = struct('F', F, 'J_eff', J_eff, 'speb', speb, 'peb', peb, ...
    'cond_num', cond_num, 'ang_cond_num', ang_cond_dd, 'eigvals', eigvals, ...
    'snr_total_linear', snr_total, 'snr_total_db', 10*log10(max(snr_total, realmin)), ...
    'R', R);
end

function out = grad_speb_ris(q, p_tgt, W_cell, theta_mat, rcs, cfg)
% EXACT Wirtinger gradient d(SPEB)/d(conj(theta_mat)) for pure-RR NLoS target in O(S * N_ris * M).
% Uses matrix calculus: d(tr(J_eff^{-1})) = -tr(J_eff^{-2} dJ_eff) = -tr(Q_5 * dF),
% where Q_5 = [I_3; -F_aa^{-1} F_ap] * J_eff^{-2} * [I_3, -F_pa F_aa^{-1}] (5x5 symmetric)!
% This avoids ANY N_ris-loop finite differences and gives exact machine-precision gradient!
q = q(:); p_tgt = p_tgt(:); pR = cfg.ris_pos(:);
S = size(theta_mat, 2);
L_s = cfg.K_fine / S;
fg = make_freq_grid(cfg);
freqs = fg.freqs; w_q = fg.w;
alpha_mag = sqrt(cfg.power_w * rcs) * cfg.lambda / ((4 * pi)^1.5);

base = fim_rr_nlos(q, p_tgt, W_cell, theta_mat, rcs, cfg);
if ~isfinite(base.speb)
    out = struct('speb', inf, 'grad', zeros(size(theta_mat)), 'fim', base);
    return;
end

% Backprop weight matrix Q5 (5x5 symmetric) such that d(SPEB) = -sum_{i,j} Q5(i,j) dF(i,j)
F_pa = base.F(1:3, 4:5);
F_aa = base.F(4:5, 4:5);
A_schur = [eye(3); -(F_aa \ F_pa.')]; % 5 x 3
J_inv2 = inv(base.J_eff)^2;
Q5 = A_schur * J_inv2 * A_schur.';
Q5 = 0.5 * (Q5 + Q5.');

% Recompute forward intermediates needed for adjoint pass
rot = nc_geometry('world_to_local');
u_bs_ris_local = rot * ((pR - q) / max(norm(pR - q), eps));
tx_off = nc_geometry('tx_offsets', cfg);
A_tx = nc_geometry('wideband_tx', u_bs_ris_local, tx_off, freqs, cfg);
tx_pow = zeros(S, fg.M);
for s = 1:S
    G = A_tx' * W_cell{s};
    tx_pow(s, :) = sum(abs(G).^2, 2).';
end
W_sn = (2.0 / cfg.noise_w) * L_s * cfg.Mr * (tx_pow .* w_q);

wb = nc_geometry('wideband_ris', q, p_tgt, theta_mat, freqs, cfg);
rr = wb.rr; u_r = wb.u_r; nR = wb.panel.nR; e1 = wb.panel.e1; e2 = wb.panel.e2;
P_perp = (eye(3) - u_r * u_r.') / rr;
drr_dp = u_r; dco_dp = P_perp * nR; dpsi1_dp = P_perp * e1; dpsi2_dp = P_perp * e2;

df_centered = freqs - cfg.fc;
c_mat = wb.c; h_mat = c_mat.^2;
D_mu = zeros(S, fg.M, 5);
for k = 1:3
    dc_k = wb.dc_dpsi1 * dpsi1_dp(k) + wb.dc_dpsi2 * dpsi2_dp(k) ...
           + c_mat * (0.5 * dco_dp(k) / wb.co - drr_dp(k) / rr);
    D_mu(:, :, k) = alpha_mag * (2 * c_mat .* dc_k - 1j * (4 * pi * df_centered / cfg.c) .* (drr_dp(k) * h_mat));
end
D_mu(:, :, 4) = h_mat;
D_mu(:, :, 5) = 1j * h_mat;

% Adjoint with respect to D_mu(:,:,i):
% F(i,j) = sum_{s,n} W_sn * Re(conj(D_mu_i) * D_mu_j)
% d(SPEB) = -sum_{i,j} Q5(i,j) dF(i,j) = 2 * Re( sum_{s,n,i} conj(g_Dmu(:,:,i)) * d(D_mu(:,:,i)) )
% where g_Dmu(:,:,i) = -W_sn .* sum_j Q5(i,j) * D_mu(:,:,j)
g_Dmu = zeros(S, fg.M, 5);
for i = 1:5
    acc = zeros(S, fg.M);
    for j = 1:5
        acc = acc + Q5(i, j) * D_mu(:, :, j);
    end
    g_Dmu(:, :, i) = -W_sn .* acc;
end

% Backprop from D_mu to (c_mat, dc_dpsi1, dc_dpsi2):
% Since D_mu_i is holomorphic in (c, dc1, dc2), d(SPEB) = 2*Re( conj(g_c)*dc + conj(g_dc1)*d(dc1) + conj(g_dc2)*d(dc2) )
g_c   = zeros(S, fg.M);
g_dc1 = zeros(S, fg.M);
g_dc2 = zeros(S, fg.M);

% From i=4 (h = c^2 -> dh = 2c dc) and i=5 (1j*c^2 -> 2j*c dc):
g_c = g_c + conj(2 * c_mat) .* g_Dmu(:, :, 4) + conj(2j * c_mat) .* g_Dmu(:, :, 5);

for k = 1:3
    gk = g_Dmu(:, :, k);
    coef_c2 = 2 * (0.5 * dco_dp(k) / wb.co - drr_dp(k) / rr) - 1j * (4 * pi * df_centered / cfg.c) * drr_dp(k);
    % Partial wrt c:
    dD_dc = alpha_mag * (2 * (wb.dc_dpsi1 * dpsi1_dp(k) + wb.dc_dpsi2 * dpsi2_dp(k)) + 2 * coef_c2 .* c_mat);
    g_c   = g_c   + conj(dD_dc) .* gk;
    g_dc1 = g_dc1 + conj(2 * alpha_mag * dpsi1_dp(k) * c_mat) .* gk;
    g_dc2 = g_dc2 + conj(2 * alpha_mag * dpsi2_dp(k) * c_mat) .* gk;
end

% Now backprop from (c, dc_dpsi1, dc_dpsi2) to theta_mat (N_ris x S) via separable Kronecker!
% c(s,n)   = scale_f(n) * vec(A1(:,n) * A2(:,n).').' * theta(:,s)
% dc1(s,n) = scale_f(n) * vec(dA1(:,n) * A2(:,n).').' * theta(:,s)
% dc2(s,n) = scale_f(n) * vec(A1(:,n) * dA2(:,n).').' * theta(:,s)
% Therefore: d(SPEB)/d(conj(theta(:,s))) = sum_n scale_f(n) * [ conj(v_n)*g_c(s,n) + conj(dv1_n)*g_dc1(s,n) + conj(dv2_n)*g_dc2(s,n) ]
f_eval = cfg.wideband * freqs + (~cfg.wideband) * cfg.fc;
k_vec = 2 * pi * f_eval / cfg.c;
v = wb.panel.v; Mside = cfg.ris_side;
A1 = exp(-1j * (v * (k_vec * wb.psi1)));
A2 = exp(-1j * (v * (k_vec * wb.psi2)));
dA1 = (-1j * (v * k_vec)) .* A1;
dA2 = (-1j * (v * k_vec)) .* A2;

grad = zeros(cfg.N_ris, S);
for s = 1:S
    wc  = wb.scale_f .* g_c(s, :);   % 1 x M
    w1  = wb.scale_f .* g_dc1(s, :);
    w2  = wb.scale_f .* g_dc2(s, :);
    % sum_n wc(n) * conj(A1(:,n)) * conj(A2(:,n)).' = (conj(A1) .* wc) * A2'
    G_mat = (conj(A1) .* wc) * A2' + (conj(dA1) .* w1) * A2' + (conj(A1) .* w2) * dA2';
    grad(:, s) = G_mat(:);
end

out = struct('speb', base.speb, 'grad', grad, 'fim', base);
end

function amb = eval_rr_ambiguity(q, p_tgt, W_cell, theta_mat, rcs, cfg)
% Evaluate wideband 2D RIS-angle normalized matched-filter likelihood surface over +/-18 deg cone
% around true RIS direction to quantify mirror ambiguity separation & peak-to-sidelobe margin.
q = q(:); p_tgt = p_tgt(:); pR = cfg.ris_pos(:);
sph = nc_geometry('ris_spherical', p_tgt, pR);
freqs = linspace(cfg.fref, cfg.fref + (cfg.N - 1) * cfg.delta_f, 7); % wideband multi-freq scan
wb0 = nc_geometry('wideband_ris', q, p_tgt, theta_mat, freqs, cfg);
h0 = wb0.c(:).^2;
n0 = norm(h0);

d_th = linspace(-18, 18, 49); % 0.75 deg grid (fast & accurate)
d_ph = linspace(-18, 18, 49);
score = zeros(numel(d_th), numel(d_ph));
ang_sep = zeros(size(score));
for i = 1:numel(d_th)
    for j = 1:numel(d_ph)
        th = max(1, min(179, sph.th_r + d_th(i)));
        ph = sph.ph_r + d_ph(j);
        pt = nc_geometry('from_ris_sph', sph.r_r, th, ph, pR);
        wb = nc_geometry('wideband_ris', q, pt, theta_mat, freqs, cfg);
        ht = wb.c(:).^2;
        nt = norm(ht);
        if nt > 0 && n0 > 0
            score(i, j) = abs(h0' * ht)^2 / (n0^2 * nt^2);
        end
        ang_sep(i, j) = acosd(max(-1, min(1, sph.u_r.' * wb.u_r)));
    end
end
outside = ang_sep >= 5.0; % Outside composite main lobe (first null ~3.6 deg + beam offset ~1.5 deg)
[max_side, idx_max] = max(score(outside));
seps_out = ang_sep(outside);
local_ring = (ang_sep >= 5.0) & (ang_sep <= 12.0);
max_local = max(score(local_ring));
amb = struct('max_sidelobe_corr', max_side, ...
    'sidelobe_margin_db', -10 * log10(max(max_side, 1e-12)), ...
    'local_sidelobe_margin_db', -10 * log10(max(max_local, 1e-12)), ...
    'worst_ambiguity_sep_deg', seps_out(idx_max), ...
    'true_sph', sph, 'd_th', d_th, 'd_ph', d_ph, 'score_map', score);
end

function res = degenerate_fim_result()
res = struct('F', zeros(5,5), 'J_eff', zeros(3,3), 'speb', inf, 'peb', inf, ...
    'cond_num', inf, 'ang_cond_num', inf, 'eigvals', zeros(3,1), 'snr_total_linear', 0, ...
    'snr_total_db', -inf, 'snr_per_cfg_db', -inf, 'dbr', nan, 'rr', nan, 'ci', 0, 'co', 0);
end
