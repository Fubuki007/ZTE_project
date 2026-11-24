function [coarse_pos, info] = nc_coarse_capture(q, scene, design_coarse, design_coarse_ris, rcs, seed, cfg, use_ris)
% NC_COARSE_CAPTURE  256-symbol split coarse acquisition (81 LoS + 175 NLoS) with
% two-stage strong-LoS clutter cancellation & 5x5 full-aperture 2-bit RIS codebook scan.
%
% Resource neutrality: total coarse symbols = 81 + 175 = 256 (unchanged from Stage 3).
% Targets are stationary (v_q = 0); full N = 12,672 subcarriers are used for range FFT.

q = q(:); pR = cfg.ris_pos(:);
rot = nc_geometry('world_to_local');
tx_off = nc_geometry('tx_offsets', cfg);
rx_off = nc_geometry('rx_offsets', cfg);
N = cfg.N;
n_vec = (0:N-1).';

% Exact Chebyshev-16 interpolation matrix for fast true-wideband evaluation across all N subcarriers
K_k = 16;
x_cheb = -cos(pi * (0:K_k-1).' / (K_k - 1));
n_knots = 0.5 * (x_cheb + 1) * (N - 1);
f_knots = cfg.fref + n_knots(:).' * cfg.delta_f;
x_all = 2 * ((0:N-1).' / (N - 1)) - 1;
InterpMat = cos((0:K_k-1) .* acos(x_all)) / cos((0:K_k-1) .* acos(x_cheb));

% Physical visibility for each target from BS q
los_vis = false(cfg.Q, 1);
for t = 1:cfg.Q
    los_vis(t) = ~nc_geometry('blocked', q, scene.targets(t, :).', cfg.buildings);
end

% Check if RIS path to target 2 is physically visible
ris_vis_bs = ~nc_geometry('blocked', q, pR, cfg.buildings);
ris_vis_t2 = ~nc_geometry('blocked', pR, scene.targets(2, :).', cfg.buildings);
rr_vis_t2 = use_ris && ris_vis_bs && ris_vis_t2;

% Generate 16QAM transmitted symbols for Stage A (64 sym) and Stage B (192 sym)
rng(seed, 'twister');
levels = [-3 -1 1 3] / sqrt(10);
W_c = design_coarse.W; % Nt x U

% ---- STAGE A: Direct-LoS Coarse Capture (64 symbols, full 12,672 subcarriers) ----
L_a = cfg.K_coarse_los;
S_a = levels(randi(4, cfg.U, N * L_a)) + 1j * levels(randi(4, cfg.U, N * L_a));

% Identify which targets are expected LoS from prior (strictly using prior, NOT truth!)
prior_los = false(cfg.Q, 1);
for t = 1:cfg.Q
    prior_los(t) = ~nc_geometry('blocked', q, scene.prior(t, :).', cfg.buildings);
end

% Build Stage-A DD received signal across subcarriers (beamformed toward prior LoS target(s))
% For each target expected LoS from prior, use a matched Rx beamformer toward its prior direction
% (no extra RF chains, coherent digital combining of existing 64 Rx elements).
coarse_pos = scene.prior; % fallback if uncaptured (strict failure still recorded!)
locked = false(cfg.Q, 1);
coarse_range_err = nan(cfg.Q, 1);
coarse_snr_db = nan(cfg.Q, 1);
los_est_params = struct('valid', false, 'pos', zeros(3,1), 'R', 0, 'u_loc', [0;0;1], 'alpha', 0);

% Precompute true DD echo per visible target on Stage A (for each target, 64 Rx snapshots at subsampled grid + beamformed full RD)
% First handle every target that is physically LoS (and detected in Stage A)
los_target_indices = find(prior_los);
if isempty(los_target_indices)
    los_target_indices = 1; % Always attempt Stage A on target 1
end

% Precompute true Stage-A per-target wideband Tx & Rx steering at knots
true_dd_amp = zeros(cfg.Q, 1);
true_dd_R = zeros(cfg.Q, 1);
true_dd_uloc = zeros(3, cfg.Q);
for t = 1:cfg.Q
    dvec = scene.targets(t, :).' - q;
    true_dd_R(t) = norm(dvec);
    true_dd_uloc(:, t) = rot * (dvec / max(true_dd_R(t), eps));
    if los_vis(t)
        true_dd_amp(t) = sqrt(cfg.power_w * rcs * scene.rel_rcs(t)) * cfg.lambda / ((4*pi)^1.5 * true_dd_R(t)^2) ...
                         * exp(1j * scene.scatter_phase(t));
    end
end

% Stage-A digital Rx beamformer: sum of unit-norm steering vectors toward prior LoS targets
w_rx_a = zeros(cfg.Mr, 1);
for idx_t = 1:numel(los_target_indices)
    t = los_target_indices(idx_t);
    dp = scene.prior(t, :).' - q;
    up = rot * (dp / max(norm(dp), eps));
    w_rx_a = w_rx_a + nc_geometry('wideband_rx', up, rx_off, cfg.fc, cfg);
end
w_rx_a = w_rx_a / max(norm(w_rx_a), eps);

% Synthesize exact Stage-A wideband beamformed RD matrix (N x L_a) + spatial subcube for full-array angle matching
Y_a_clean = zeros(N, L_a);
for t = 1:cfg.Q
    if ~los_vis(t), continue; end
    A_tx_k = nc_geometry('wideband_tx', true_dd_uloc(:, t), tx_off, f_knots, cfg); % Nt x K_k
    A_rx_k = nc_geometry('wideband_rx', true_dd_uloc(:, t), rx_off, f_knots, cfg); % Mr x K_k
    rx_g_k = (w_rx_a' * A_rx_k).';          % K_k x 1
    G_tx_k = A_tx_k' * W_c;                 % K_k x U
    % Interpolate G_tx * rx_g onto all N subcarriers (N x U)
    H_t = InterpMat * (G_tx_k .* rx_g_k);   % N x U
    del_t = exp(-1j * 4 * pi * cfg.delta_f / cfg.c * true_dd_R(t) * n_vec); % N x 1
    % Symbol illumination: sum_u H_t(n,u) * S_a(u, n, l)
    S_u1 = reshape(S_a(1, :), N, L_a);
    S_u2 = reshape(S_a(2, :), N, L_a);
    illum = H_t(:, 1) .* S_u1 + H_t(:, 2) .* S_u2;
    Y_a_clean = Y_a_clean + true_dd_amp(t) * (del_t .* illum);
end
noise_a = sqrt(cfg.noise_w / 2) * (randn(N, L_a) + 1j * randn(N, L_a));
Y_a = Y_a_clean + noise_a;

% Matched-filter range compression for each expected LoS target (coherent over L_a symbols)
% De-phase by dominant stream combination using prior Tx direction
for idx_t = 1:numel(los_target_indices)
    t = los_target_indices(idx_t);
    dp = scene.prior(t, :).' - q;
    up = rot * (dp / max(norm(dp), eps));
    a_tx_p = nc_geometry('wideband_tx', up, tx_off, cfg.fc, cfg);
    g_p = a_tx_p' * W_c; % 1 x U
    S_comb = reshape(g_p * S_a, N, L_a);
    % Matched filter over L_a symbols: sum_l Y_a(n,l) * conj(S_comb(n,l)) / sqrt(sum_l |S_comb(n,l)|^2)
    denom_mf = sqrt(max(sum(abs(S_comb).^2, 2), realmin));
    y_f = sum(Y_a .* conj(S_comb), 2) ./ denom_mf; % N x 1 (exact white noise variance = cfg.noise_w!)

    % Hann-windowed 1D unitary IFFT range spectrum
    win_h = 0.5 * (1 - cos(2 * pi * (0:N-1).' / (N - 1)));
    win_h = win_h / sqrt(mean(win_h.^2));
    spec = abs(sqrt(N) * ifft(y_f .* win_h, N, 1)).^2;

    % Search within +/-15 m around prior range (prevents confusing target 1 with target 2)
    r_prior = norm(dp);
    r_bins = (0:N-1).' * (cfg.c / (2 * cfg.B));
    mask_r = abs(r_bins - r_prior) <= max(15.0, 5 * cfg.prior_sigma_m);
    if ~any(mask_r), mask_r = true(N, 1); end
    spec_masked = spec; spec_masked(~mask_r) = -inf;
    [pk_val, pk_idx] = max(spec_masked);
    noise_floor = median(spec) / log(2); % exact exponential mean estimator from median!
    snr_pk_lin = pk_val / max(noise_floor, realmin);
    coarse_snr_db(t) = 10 * log10(max(snr_pk_lin, realmin));

    if snr_pk_lin > cfg.det_threshold_linear
        % 3-point parabolic interpolation for sub-bin range accuracy (<< 0.1 m)
        b0 = pk_idx - 1; % 0-based
        il = mod(b0 - 1, N) + 1; ir = mod(b0 + 1, N) + 1;
        Pl = spec(il); Pc = spec(pk_idx); Pr = spec(ir);
        den = Pl - 2*Pc + Pr;
        delta_b = 0;
        if abs(den) > eps
            delta_b = max(-0.5, min(0.5, 0.5 * (Pl - Pr) / den));
        end
        R_hat = (b0 + delta_b) * (cfg.c / (2 * cfg.B));

        % Spatial snapshot on 64 Rx elements (384 subcarriers x L_a symbols) -> full-array angle match
        n_sub = round(linspace(1, N, 384)).';
        del_focus = exp(+1j * 4 * pi * cfg.delta_f / cfg.c * R_hat * (n_sub - 1));
        snap_rx = zeros(cfg.Mr, 1);
        % Synthesize exact 64-element spatial snapshot at the detected range bin
        for tt = 1:cfg.Q
            if ~los_vis(tt), continue; end
            A_tx_s = nc_geometry('wideband_tx', true_dd_uloc(:, tt), tx_off, cfg.fref + (n_sub-1)*cfg.delta_f, cfg);
            A_rx_s = nc_geometry('wideband_rx', true_dd_uloc(:, tt), rx_off, cfg.fref + (n_sub-1)*cfg.delta_f, cfg);
            G_tx_s = A_tx_s' * W_c; % 384 x U
            del_tt = exp(-1j * 4 * pi * cfg.delta_f / cfg.c * true_dd_R(tt) * (n_sub - 1));
            S_sub1 = reshape(S_a(1, :), N, L_a); S_sub1 = S_sub1(n_sub, :);
            S_sub2 = reshape(S_a(2, :), N, L_a); S_sub2 = S_sub2(n_sub, :);
            illum_s = G_tx_s(:, 1) .* S_sub1 + G_tx_s(:, 2) .* S_sub2;
            % Project with S_comb(n_sub, :) and del_focus
            w_sub = conj(S_comb(n_sub, :)) ./ denom_mf(n_sub) .* del_focus;
            coeff_s = true_dd_amp(tt) * sum(illum_s .* del_tt .* w_sub, 2); % 384 x 1
            snap_rx = snap_rx + A_rx_s * coeff_s / sqrt(numel(n_sub));
        end
        % Add independent spatial thermal noise (exact variance cfg.noise_w per Rx element)
        snap_rx = snap_rx + sqrt(cfg.noise_w / 2) * (randn(cfg.Mr, 1) + 1j * randn(cfg.Mr, 1));

        % Full-array 2D matched spatial angle estimation (coarse_array_angles)
        p_ang = struct('Mx', cfg.Mx, 'My', cfg.My, 'd', cfg.d, 'lambda', cfg.lambda);
        [ang_hat, ~] = coarse_array_angles({snap_rx}, p_ang);
        th_loc = ang_hat(1, 1); ph_loc = ang_hat(1, 2);
        u_loc_hat = [sind(th_loc)*cosd(ph_loc); sind(th_loc)*sind(ph_loc); cosd(th_loc)];
        u_w_hat = rot.' * u_loc_hat; % rot is symmetric orthogonal
        pos_hat = q + R_hat * u_w_hat;

        coarse_pos(t, :) = pos_hat.';
        locked(t) = true;
        coarse_range_err(t) = abs(R_hat - true_dd_R(t));

        % Estimate complex amplitude alpha_hat of LoS Target 1 for Stage-B clutter cancellation!
        if t == 1
            % Compute matched template gain at (R_hat, u_loc_hat)
            A_tx_h = nc_geometry('wideband_tx', u_loc_hat, tx_off, f_knots, cfg);
            A_rx_h = nc_geometry('wideband_rx', u_loc_hat, rx_off, f_knots, cfg);
            H_h = InterpMat * ((A_tx_h' * W_c) .* (w_rx_a' * A_rx_h).');
            del_h = exp(-1j * 4 * pi * cfg.delta_f / cfg.c * R_hat * n_vec);
            S_u1 = reshape(S_a(1, :), N, L_a);
            S_u2 = reshape(S_a(2, :), N, L_a);
            tmpl_f = sum((del_h .* (H_h(:, 1) .* S_u1 + H_h(:, 2) .* S_u2)) .* conj(S_comb), 2) ./ denom_mf;
            alpha_hat_1 = (tmpl_f' * y_f) / max(real(tmpl_f' * tmpl_f), realmin);
            los_est_params = struct('valid', true, 'pos', pos_hat, 'R', R_hat, ...
                'u_loc', u_loc_hat, 'alpha', alpha_hat_1);
        end
    end
end

% ---- STAGE B: NLoS RIS Multi-Beam Codebook Capture (192 symbols = 16 beams x 12 sym) ----
% Only needed for target(s) NOT captured via direct LoS in Stage A (primarily Target 2 when NLoS)
stage_b_info = struct('ran', false, 'los_suppression_db', nan, 'peak_to_clutter_db', nan, ...
    'beam_misaligned', false, 'best_beam', 0, 'rr_coarse_err_m', nan);

if ~locked(2) && use_ris && ris_vis_bs
    stage_b_info.ran = true;
    W_b = design_coarse_ris.W; % Beamformer illuminating RIS while strictly satisfying comm SINR!
    Sc_side = cfg.S_coarse_side;
    S_c = cfg.S_coarse; % 5x5 = 25 beams
    L_b = cfg.K_coarse_nlos / S_c; % 7 symbols per beam

    % Build 5x5 full-aperture 2-bit RIS codebook centered on prior direction of Target 2
    sph_p2 = nc_geometry('ris_spherical', scene.prior(2, :).', pR);
    sph_t2 = nc_geometry('ris_spherical', scene.targets(2, :).', pR);
    half_idx = (Sc_side - 1) / 2;
    grid_1d = (-half_idx : 1 : half_idx) * cfg.coarse_beam_step_deg; % [-5.6, -2.8, 0, +2.8, +5.6] deg
    [g_th, g_ph] = ndgrid(grid_1d, grid_1d);
    beam_th = sph_p2.th_r + g_th(:);
    beam_ph = sph_p2.ph_r + g_ph(:);
    theta_cb = zeros(cfg.N_ris, S_c);
    for s = 1:S_c
        p_b = nc_geometry('from_ris_sph', sph_p2.r_r, max(1, min(179, beam_th(s))), beam_ph(s), pR);
        theta_cb(:, s) = nc_geometry('ris_steer_phase', q, p_b, cfg);
    end

    % Check beam misalignment (whether true Target 2 fell outside the 5x5 scan cone)
    dth_true = abs(sph_t2.th_r - sph_p2.th_r);
    dph_true = abs(mod(sph_t2.ph_r - sph_p2.ph_r + 180, 360) - 180);
    half_span = (half_idx + 0.5) * cfg.coarse_beam_step_deg; % 7.0 deg
    stage_b_info.beam_misaligned = (dth_true > half_span) || (dph_true > half_span);

    % Fixed digital Rx beamformer pointed at KNOWN RIS direction b_r (+18 dB gain!)
    u_ris_loc = rot * ((pR - q) / max(norm(pR - q), eps));
    w_rx_ris = nc_geometry('wideband_rx', u_ris_loc, rx_off, cfg.fc, cfg);
    w_rx_ris = w_rx_ris / norm(w_rx_ris);

    % Wideband Tx gain toward RIS at knots (using W_b which illuminates RIS!)
    A_tx_ris_k = nc_geometry('wideband_tx', u_ris_loc, tx_off, f_knots, cfg);
    A_rx_ris_k = nc_geometry('wideband_rx', u_ris_loc, rx_off, f_knots, cfg);
    rx_ris_g_k = (w_rx_ris' * A_rx_ris_k).'; % K_k x 1
    G_tx_ris_k = A_tx_ris_k' * W_b;          % K_k x U
    H_ris_all = InterpMat * (G_tx_ris_k .* rx_ris_g_k); % N x U

    % Compute exact wideband RR channel response for true Target 2 across all S_c beams
    if rr_vis_t2
        wb_t2_k = nc_geometry('wideband_ris', q, scene.targets(2, :).', theta_cb, f_knots, cfg);
        C2_all = InterpMat * (wb_t2_k.c.^2).'; % N x S_c
        alpha_rr_true = sqrt(cfg.power_w * rcs * scene.rel_rcs(2)) * cfg.lambda / ((4*pi)^1.5) ...
                        * exp(1j * scene.scatter_phase(2));
        dist_rr_true = 2 * (wb_t2_k.dbr + wb_t2_k.rr);
        del_rr_true = exp(-1j * 2 * pi * cfg.delta_f / cfg.c * dist_rr_true * n_vec);
    else
        C2_all = zeros(N, S_c); alpha_rr_true = 0; del_rr_true = ones(N, 1);
    end

    % Compute true LoS Target 1 interference leaked into w_rx_ris (for authentic clutter test!)
    if los_vis(1)
        A_tx_1k = nc_geometry('wideband_tx', true_dd_uloc(:, 1), tx_off, f_knots, cfg);
        A_rx_1k = nc_geometry('wideband_rx', true_dd_uloc(:, 1), rx_off, f_knots, cfg);
        rx_1_leak_k = (w_rx_ris' * A_rx_1k).'; % actual 64-element UPA spatial sidelobe suppression!
        H_1_leak = InterpMat * ((A_tx_1k' * W_b) .* rx_1_leak_k);
        del_1_true = exp(-1j * 4 * pi * cfg.delta_f / cfg.c * true_dd_R(1) * n_vec);
        stage_b_info.los_suppression_db = 20 * log10(sqrt(cfg.Mr) / max(abs(mean(rx_1_leak_k)), 1e-12));
    else
        H_1_leak = zeros(N, cfg.U); del_1_true = ones(N, 1);
    end

    % Stage-1 cancellation template from Stage-A estimate of LoS Target 1
    if los_est_params.valid
        A_tx_1hk = nc_geometry('wideband_tx', los_est_params.u_loc, tx_off, f_knots, cfg);
        A_rx_1hk = nc_geometry('wideband_rx', los_est_params.u_loc, rx_off, f_knots, cfg);
        H_1_est = InterpMat * ((A_tx_1hk' * W_b) .* (w_rx_ris' * A_rx_1hk).');
        del_1_est = exp(-1j * 4 * pi * cfg.delta_f / cfg.c * los_est_params.R * n_vec);
    end

    % Hann window for -40 dB range sidelobe suppression
    win_h = 0.5 * (1 - cos(2 * pi * (0:N-1).' / (N - 1)));
    win_h = win_h / sqrt(mean(win_h.^2));

    % Search range mask around prior 2*(dbr + rr_prior) +/- 20 m
    dbr = norm(q - pR);
    dist_prior = 2 * (dbr + sph_p2.r_r);
    dist_bins = (0:N-1).' * (cfg.c / cfg.B);
    mask_d = abs(dist_bins - dist_prior) <= max(20.0, 6 * cfg.prior_sigma_m);
    if ~any(mask_d), mask_d = true(N, 1); end

    a_tx_ris0 = nc_geometry('wideband_tx', u_ris_loc, tx_off, cfg.fc, cfg);
    g_ris = a_tx_ris0' * W_b; % 1 x U

    beam_peak_val = zeros(S_c, 1);
    beam_peak_bin = zeros(S_c, 1);
    beam_peak_delta = zeros(S_c, 1);
    beam_peak_snr = zeros(S_c, 1);
    beam_clutter_max = zeros(S_c, 1);
    beam_complex_pk = zeros(S_c, 1);

    for s = 1:S_c
        S_b = levels(randi(4, cfg.U, N * L_b)) + 1j * levels(randi(4, cfg.U, N * L_b));
        Sb1 = reshape(S_b(1, :), N, L_b);
        Sb2 = reshape(S_b(2, :), N, L_b);

        % True RR echo + true leaked LoS clutter + thermal noise
        illum_rr = H_ris_all(:, 1) .* Sb1 + H_ris_all(:, 2) .* Sb2;
        Y_rr = alpha_rr_true * (C2_all(:, s) .* del_rr_true) .* illum_rr;

        Y_clut_true = zeros(N, L_b);
        if los_vis(1)
            Y_clut_true = true_dd_amp(1) * del_1_true .* (H_1_leak(:, 1) .* Sb1 + H_1_leak(:, 2) .* Sb2);
        end

        % Stage-1 coherent frequency-domain cancellation of estimated LoS Target 1
        Y_clut_res = Y_clut_true;
        if los_est_params.valid
            Y_clut_hat = los_est_params.alpha * del_1_est .* (H_1_est(:, 1) .* Sb1 + H_1_est(:, 2) .* Sb2);
            Y_clut_res = Y_clut_true - Y_clut_hat;
        end

        noise_b = sqrt(cfg.noise_w / 2) * (randn(N, L_b) + 1j * randn(N, L_b));
        Y_b = Y_rr + Y_clut_res + noise_b;

        % Symbol matched filter across L_b=12 symbols toward RIS Tx direction
        S_comb = reshape(g_ris * S_b, N, L_b);
        denom_b = sqrt(max(sum(abs(S_comb).^2, 2), realmin));
        y_f = sum(Y_b .* conj(S_comb), 2) ./ denom_b;

        % Hann-windowed unitary IFFT
        Y_del = sqrt(N) * ifft(y_f .* win_h, N, 1);
        spec = abs(Y_del).^2;

        % Measure residual clutter power separately for Gate 2 audit!
        if s == 1
            y_clut_f = sum(Y_clut_res .* conj(S_comb), 2) ./ denom_b;
            spec_clut = abs(sqrt(N) * ifft(y_clut_f .* win_h, N, 1)).^2;
            beam_clutter_max(s) = max(spec_clut(mask_d));
        end

        spec_m = spec; spec_m(~mask_d) = -inf;
        [pk, b_idx] = max(spec_m);
        nfloor = median(spec) / log(2);
        b0_loc = b_idx - 1;
        Pl_b = spec(mod(b0_loc - 1, N) + 1);
        Pr_b = spec(mod(b0_loc + 1, N) + 1);
        den_b = Pl_b - 2 * pk + Pr_b;
        db_sub = 0.0;
        if abs(den_b) > eps
            db_sub = max(-0.5, min(0.5, 0.5 * (Pl_b - Pr_b) / den_b));
        end
        beam_peak_val(s) = pk;
        beam_peak_bin(s) = b_idx;
        beam_peak_delta(s) = db_sub;
        beam_peak_snr(s) = pk / max(nfloor, realmin);
        beam_complex_pk(s) = Y_del(b_idx);
    end

    [best_snr, s_best] = max(beam_peak_snr);
    coarse_snr_db(2) = 10 * log10(max(best_snr, realmin));
    stage_b_info.best_beam = s_best;
    if beam_clutter_max(1) > 0
        stage_b_info.peak_to_clutter_db = 10 * log10(beam_peak_val(s_best) / beam_clutter_max(1));
    else
        stage_b_info.peak_to_clutter_db = inf;
    end

    % Detection threshold adjusted for 16-beam union (P_fa_total = 1e-6 -> per-beam 1e-6/16)
    det_thresh_b = -log(cfg.pfa_target / S_c);
    if best_snr > det_thresh_b
        b0 = (beam_peak_bin(s_best) - 1) + beam_peak_delta(s_best);
        rr_hat = max(cfg.far_field_min_m * 0.5, 0.5 * (b0 * (cfg.c / cfg.B)) - dbr);

        % 2D centroid / parabolic angle interpolation across the Sc_side x Sc_side beam power map
        P_map = reshape(beam_peak_val, Sc_side, Sc_side);
        [r_b, c_b] = ind2sub([Sc_side, Sc_side], s_best);
        r_rng = max(1, r_b - 1) : min(Sc_side, r_b + 1);
        c_rng = max(1, c_b - 1) : min(Sc_side, c_b + 1);
        W_loc = sqrt(P_map(r_rng, c_rng));
        W_loc(W_loc < 0.20 * max(W_loc(:))) = 0;
        th_grid = reshape(beam_th, Sc_side, Sc_side);
        ph_grid = reshape(beam_ph, Sc_side, Sc_side);
        th_hat = sum(W_loc .* th_grid(r_rng, c_rng), 'all') / max(sum(W_loc, 'all'), realmin);
        ph_hat = sum(W_loc .* ph_grid(r_rng, c_rng), 'all') / max(sum(W_loc, 'all'), realmin);

        pos2_hat = nc_geometry('from_ris_sph', rr_hat, max(1, min(179, th_hat)), ph_hat, pR);
        coarse_pos(2, :) = pos2_hat.';
        locked(2) = true;
        coarse_range_err(2) = abs(rr_hat - sph_t2.r_r);
        stage_b_info.rr_coarse_err_m = coarse_range_err(2);
    end
end

info = struct('locked', locked, 'los_vis', los_vis, 'rr_vis_t2', rr_vis_t2, ...
    'coarse_snr_db', coarse_snr_db, 'coarse_range_err_m', coarse_range_err, ...
    'los_est_params', los_est_params, 'stage_b', stage_b_info);
end
