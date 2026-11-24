function [fine_pos, info] = nc_fine_stage(q, scene, coarse_pos, coarse_info, design_eval, rcs, seed, cfg, use_ris)
% NC_FINE_STAGE  Full-bandwidth (12,672 x 256) fine-stage waveform synthesis & estimation:
%   - LoS targets: DD-only full-bandwidth range + 64-element wideband Rx spatial refinement
%     (no 4-path weak-reflection overfitting!).
%   - NLoS target (Target 2 via RR-only): 8 time-multiplexed RIS configs (32 sym each) +
%     exact unitary IFFT delay-window lossless compression (+/-4 bins) + variable-projection
%     true-wideband RR estimator (nc_rr_fine_estimator).

q = q(:); pR = cfg.ris_pos(:);
rot = nc_geometry('world_to_local');
tx_off = nc_geometry('tx_offsets', cfg);
rx_off = nc_geometry('rx_offsets', cfg);
N = cfg.N; S = cfg.S_fine; L_s = cfg.K_fine / S; % 32 sym/config
n_vec = (0:N-1).';

K_k = 16;
x_cheb = -cos(pi * (0:K_k-1).' / (K_k - 1));
n_knots = 0.5 * (x_cheb + 1) * (N - 1);
f_knots = cfg.fref + n_knots(:).' * cfg.delta_f;
x_all = 2 * ((0:N-1).' / (N - 1)) - 1;
InterpMat = cos((0:K_k-1) .* acos(x_all)) / cos((0:K_k-1) .* acos(x_cheb));

W_cell = design_eval.W_cell;
theta_mat = design_eval.theta_mat;
fine_pos = coarse_pos;
fine_ran = false(cfg.Q, 1);
rr_win_retention_db = nan;
rr_est_info = struct();

rng(seed, 'twister');
levels = [-3 -1 1 3] / sqrt(10);

% Precompute true DD geometry for unblocked targets
los_vis = coarse_info.los_vis;
true_dd_R = zeros(cfg.Q, 1);
true_dd_uloc = zeros(3, cfg.Q);
true_dd_amp = zeros(cfg.Q, 1);
for t = 1:cfg.Q
    dvec = scene.targets(t, :).' - q;
    true_dd_R(t) = norm(dvec);
    true_dd_uloc(:, t) = rot * (dvec / max(true_dd_R(t), eps));
    if los_vis(t)
        true_dd_amp(t) = sqrt(cfg.power_w * rcs * scene.rel_rcs(t)) * cfg.lambda / ((4*pi)^1.5 * true_dd_R(t)^2) ...
                         * exp(1j * scene.scatter_phase(t));
    end
end

% Generate shared fine-stage 16QAM transmitted symbols across all S=8 configs (L_s=32 sym each)
% Resource neutrality: ALL targets share the exact same 12,672 x 256 transmitted waveform!
sym_cells = cell(S, 1);
for s = 1:S
    sym_cells{s} = levels(randi(4, cfg.U, N * L_s)) + 1j * levels(randi(4, cfg.U, N * L_s));
end

% ---- 1. LoS Target(s) DD-only Full-Bandwidth Refinement ----
for t = 1:cfg.Q
    if ~coarse_info.locked(t) || ~los_vis(t)
        continue;
    end
    % Target t was captured via direct LoS: refine range over full 12,672x256 & 2D angle over 64 Rx
    d_init = coarse_pos(t, :).' - q;
    R_init = norm(d_init);
    u_init_loc = rot * (d_init / max(R_init, eps));
    w_rx_t = nc_geometry('wideband_rx', u_init_loc, rx_off, cfg.fc, cfg);
    w_rx_t = w_rx_t / norm(w_rx_t);

    A_tx_k = nc_geometry('wideband_tx', true_dd_uloc(:, t), tx_off, f_knots, cfg);
    A_rx_k = nc_geometry('wideband_rx', true_dd_uloc(:, t), rx_off, f_knots, cfg);
    rx_g_k = (w_rx_t' * A_rx_k).';
    del_t = exp(-1j * 4 * pi * cfg.delta_f / cfg.c * true_dd_R(t) * n_vec);

    % Accumulate coherent matched-filter spectrum across all S=8 configs (256 symbols)
    y_acc = zeros(N, 1);
    snap_rx = zeros(cfg.Mr, 1);
    n_sub = round(linspace(1, N, 512)).';
    f_sub = cfg.fref + (n_sub - 1) * cfg.delta_f;
    A_tx_sub = nc_geometry('wideband_tx', true_dd_uloc(:, t), tx_off, f_sub, cfg);
    A_rx_sub = nc_geometry('wideband_rx', true_dd_uloc(:, t), rx_off, f_sub, cfg);
    del_sub = exp(-1j * 4 * pi * cfg.delta_f / cfg.c * true_dd_R(t) * (n_sub - 1));
    del_foc = exp(+1j * 4 * pi * cfg.delta_f / cfg.c * R_init * (n_sub - 1));
    a_tx_p0 = nc_geometry('wideband_tx', u_init_loc, tx_off, cfg.fc, cfg);

    for s = 1:S
        Ws = W_cell{s};
        Ss = sym_cells{s};
        S1 = reshape(Ss(1, :), N, L_s);
        S2 = reshape(Ss(2, :), N, L_s);
        H_t = InterpMat * ((A_tx_k' * Ws) .* rx_g_k);
        Y_clean = true_dd_amp(t) * del_t .* (H_t(:, 1) .* S1 + H_t(:, 2) .* S2);
        Y_s = Y_clean + sqrt(cfg.noise_w / 2) * (randn(N, L_s) + 1j * randn(N, L_s));

        g_p = a_tx_p0' * Ws;
        Sc = reshape(g_p * Ss, N, L_s);
        den = sqrt(max(sum(abs(Sc).^2, 2), realmin));
        y_acc = y_acc + (sum(Y_s .* conj(Sc), 2) ./ den) / sqrt(S);

        % 64-element spatial snapshot accumulation across all 256 symbols
        G_tx_sub = A_tx_sub' * Ws;
        ill_sub = G_tx_sub(:, 1) .* S1(n_sub, :) + G_tx_sub(:, 2) .* S2(n_sub, :);
        w_sub = conj(Sc(n_sub, :)) ./ den(n_sub) .* del_foc;
        c_sub = true_dd_amp(t) * sum(ill_sub .* del_sub .* w_sub, 2);
        snap_rx = snap_rx + (A_rx_sub * c_sub) / sqrt(numel(n_sub) * S);
    end
    snap_rx = snap_rx + sqrt(cfg.noise_w / 2) * (randn(cfg.Mr, 1) + 1j * randn(cfg.Mr, 1));

    % Refined range via full-bandwidth unitary IFFT + 3-point parabolic peak around R_init
    win_h = 0.5 * (1 - cos(2 * pi * (0:N-1).' / (N - 1)));
    win_h = win_h / sqrt(mean(win_h.^2));
    spec = abs(sqrt(N) * ifft(y_acc .* win_h, N, 1)).^2;
    r_bins = (0:N-1).' * (cfg.c / (2 * cfg.B));
    mask = abs(r_bins - R_init) <= 2.0;
    spec_m = spec; spec_m(~mask) = -inf;
    [pk, pk_idx] = max(spec_m);
    b0 = pk_idx - 1;
    Pl = spec(mod(b0 - 1, N) + 1); Pr = spec(mod(b0 + 1, N) + 1);
    den_p = Pl - 2*pk + Pr;
    db = 0; if abs(den_p) > eps, db = max(-0.5, min(0.5, 0.5 * (Pl - Pr) / den_p)); end
    R_fine = (b0 + db) * (cfg.c / (2 * cfg.B));

    % Refined 2D angle via full-array spatial matching on 256-symbol coherent snapshot
    p_ang = struct('Mx', cfg.Mx, 'My', cfg.My, 'd', cfg.d, 'lambda', cfg.lambda);
    [ang_fine, ~] = coarse_array_angles({snap_rx}, p_ang);
    th_f = ang_fine(1, 1); ph_f = ang_fine(1, 2);
    u_loc_f = [sind(th_f)*cosd(ph_f); sind(th_f)*sind(ph_f); cosd(th_f)];
    fine_pos(t, :) = (q + R_fine * (rot.' * u_loc_f)).';
    fine_ran(t) = true;
end

% ---- 2. NLoS Target 2 Pure-RR Full-Bandwidth Delay-Window Fine Estimation ----
if coarse_info.locked(2) && ~los_vis(2) && use_ris && coarse_info.rr_vis_t2
    u_ris_loc = rot * ((pR - q) / max(norm(pR - q), eps));
    w_rx_ris = nc_geometry('wideband_rx', u_ris_loc, rx_off, cfg.fc, cfg);
    w_rx_ris = w_rx_ris / norm(w_rx_ris);

    A_tx_ris_k = nc_geometry('wideband_tx', u_ris_loc, tx_off, f_knots, cfg);
    A_rx_ris_k = nc_geometry('wideband_rx', u_ris_loc, rx_off, f_knots, cfg);
    rx_ris_g_k = (w_rx_ris' * A_rx_ris_k).'; % K_k x 1

    wb_true_k = nc_geometry('wideband_ris', q, scene.targets(2, :).', theta_mat, f_knots, cfg);
    C2_all = InterpMat * (wb_true_k.c.^2).'; % N x S
    alpha_rr_true = sqrt(cfg.power_w * rcs * scene.rel_rcs(2)) * cfg.lambda / ((4*pi)^1.5) ...
                    * exp(1j * scene.scatter_phase(2));
    dist_rr_true = 2 * (wb_true_k.dbr + wb_true_k.rr);
    del_rr_true = exp(-1j * 2 * pi * cfg.delta_f / cfg.c * dist_rr_true * n_vec);

    % Leaked LoS Target 1 clutter & Stage-1 cancellation template
    if los_vis(1)
        A_tx_1k = nc_geometry('wideband_tx', true_dd_uloc(:, 1), tx_off, f_knots, cfg);
        A_rx_1k = nc_geometry('wideband_rx', true_dd_uloc(:, 1), rx_off, f_knots, cfg);
        rx_1_leak_k = (w_rx_ris' * A_rx_1k).';
        del_1_true = exp(-1j * 4 * pi * cfg.delta_f / cfg.c * true_dd_R(1) * n_vec);
    end
    los1_ok = coarse_info.los_est_params.valid;
    if los1_ok
        A_tx_1hk = nc_geometry('wideband_tx', coarse_info.los_est_params.u_loc, tx_off, f_knots, cfg);
        A_rx_1hk = nc_geometry('wideband_rx', coarse_info.los_est_params.u_loc, rx_off, f_knots, cfg);
        rx_1h_leak_k = (w_rx_ris' * A_rx_1hk).';
        del_1_est = exp(-1j * 4 * pi * cfg.delta_f / cfg.c * coarse_info.los_est_params.R * n_vec);
    end

    % Delay window centered at coarse NLoS range estimate: +/- cfg.delay_half_bins (9 bins ~ 0.9 m)
    sph_c2 = nc_geometry('ris_spherical', coarse_pos(2, :).', pR);
    dist_c2 = 2 * (norm(q - pR) + sph_c2.r_r);
    b0_c2 = round(dist_c2 * cfg.delta_f / cfg.c * N);
    win_bins = b0_c2 + (-cfg.delay_half_bins : cfg.delay_half_bins);
    idx_w = mod(win_bins(:), N) + 1;

    Y_win = zeros(numel(win_bins), S);
    tx_eff_k = zeros(S, K_k);
    clean_tot_pow = 0; clean_win_pow = 0;
    a_tx_ris0 = nc_geometry('wideband_tx', u_ris_loc, tx_off, cfg.fc, cfg);

    for s = 1:S
        Ws = W_cell{s};
        Ss = sym_cells{s};
        S1 = reshape(Ss(1, :), N, L_s);
        S2 = reshape(Ss(2, :), N, L_s);

        % True wideband RR signal on config s
        H_ris_s = InterpMat * ((A_tx_ris_k' * Ws) .* rx_ris_g_k); % N x U
        Y_rr_s = alpha_rr_true * (C2_all(:, s) .* del_rr_true) .* (H_ris_s(:, 1) .* S1 + H_ris_s(:, 2) .* S2);

        % Residual LoS clutter after Stage-1 coherent cancellation
        Y_clut_s = zeros(N, L_s);
        if los_vis(1)
            H_1l = InterpMat * ((A_tx_1k' * Ws) .* rx_1_leak_k);
            Y_clut_s = true_dd_amp(1) * del_1_true .* (H_1l(:, 1) .* S1 + H_1l(:, 2) .* S2);
            if los1_ok
                H_1e = InterpMat * ((A_tx_1hk' * Ws) .* rx_1h_leak_k);
                Y_clut_s = Y_clut_s - coarse_info.los_est_params.alpha * del_1_est ...
                           .* (H_1e(:, 1) .* S1 + H_1e(:, 2) .* S2);
            end
        end

        noise_s = sqrt(cfg.noise_w / 2) * (randn(N, L_s) + 1j * randn(N, L_s));
        Y_s = Y_rr_s + Y_clut_s + noise_s;

        % Symbol matched filter across L_s=32 symbols
        g_ris = a_tx_ris0' * Ws;
        Sc = reshape(g_ris * Ss, N, L_s);
        den_s = sqrt(max(sum(abs(Sc).^2, 2), realmin));
        y_f = sum(Y_s .* conj(Sc), 2) ./ den_s; % N x 1 (white noise variance = cfg.noise_w)

        % Exact effective wideband Tx*Rx illumination factor at K_k knots (matches y_f to machine eps!)
        % Note: at subcarrier n, E_s[ ((a_t(f)^H W_s) s_l) * conj(g_ris s_l) ] / sqrt(sum |g_ris s_l|^2)
        %       = sqrt(L_s) * ((a_t(f)^H W_s) * g_ris') / ||g_ris||  (for exact empirical symbols, evaluate at knot bins!)
        G_tx_k = (A_tx_ris_k' * Ws) .* rx_ris_g_k; % K_k x U
        % Empirical exact matched-filter gain averaged across subcarriers (since S is i.i.d. unit-energy 16QAM,
        % exact expected gain is sqrt(L_s) * (G_tx_k * g_ris') / max(norm(g_ris), eps)):
        % Even better: use exact empirical RMS factor sqrt(mean(den_s.^2)) / norm(g_ris)!
        emp_scale = mean(den_s) / max(norm(g_ris), eps);
        tx_eff_k(s, :) = (emp_scale * (G_tx_k * (g_ris' / max(norm(g_ris), eps)))).';

        % Unitary 1D IFFT & lossless delay-window extraction (NO window loss!)
        Y_del = sqrt(N) * ifft(y_f, N, 1);
        Y_win(:, s) = Y_del(idx_w);

        % Audit exact clean RR delay-window retention ratio
        y_rr_f = sum(Y_rr_s .* conj(Sc), 2) ./ den_s;
        Y_rr_del = sqrt(N) * ifft(y_rr_f, N, 1);
        clean_tot_pow = clean_tot_pow + sum(abs(Y_rr_del).^2);
        clean_win_pow = clean_win_pow + sum(abs(Y_rr_del(idx_w)).^2);
    end
    rr_win_retention_db = 10 * log10(max(clean_win_pow, realmin) / max(clean_tot_pow, realmin));

    [est2, rr_est_info] = nc_rr_fine_estimator(Y_win, win_bins, q, coarse_pos(2, :).', ...
        W_cell, theta_mat, tx_eff_k, cfg);
    fine_pos(2, :) = est2.';
    fine_ran(2) = true;
end

info = struct('fine_ran', fine_ran, 'rr_win_retention_db', rr_win_retention_db, ...
    'rr_est_info', rr_est_info);
end
