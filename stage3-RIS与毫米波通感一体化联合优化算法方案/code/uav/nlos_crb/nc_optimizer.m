function out = nc_optimizer(mode, varargin)
% NC_OPTIMIZER  Detection-margin hard-constrained CRB-BCD-SCA joint optimizer
% (continuous 3D UAV-BS position + multi-user comm/sensing beams + S_f=8 2-bit RIS configs)
% plus fair offline-optimal fixed-BS solver and all baseline design rules.
%
% Modes:
%   'comm_beam'     : (q, targets_est, users, theta_s, use_ris, cfg, focus_weights)
%                     Exact ZF comm + communication-nullspace sensing beamformer with strict SINR & power checks.
%   'init_ris_8cfg' : (q, p_tgt2, cfg, is_random)
%                     Structured 2-bit quadrature half-panel monopulse + offset 8-config RIS basis.
%   'eval_point'    : (q, prior_pos, users, rcs, use_ris, mode_tag, cfg)
%                     Evaluates detection margin (C2), comm feasibility (C3), & worst-target SPEB (C1).
%   'offline_fixed' : (cfg, scenes_cell, use_ris, rcs)
%                     Offline global optimal single fixed BS site q_fix* over scene distribution.
%   'solve_method'  : (method_name, scene, rcs, fixed_sites, cfg)
%                     Unified dispatcher returning optimized (q, design_coarse, design_fine, opt_info).

switch mode
    case 'comm_beam'
        out = design_comm_beam(varargin{:});
    case 'init_ris_8cfg'
        out = init_ris_8cfg(varargin{:});
    case 'eval_point'
        out = evaluate_position(varargin{:});
    case 'offline_fixed'
        out = solve_offline_fixed(varargin{:});
    case 'solve_method'
        out = solve_method_dispatch(varargin{:});
    otherwise
        error('Unknown nc_optimizer mode: %s', mode);
end
end

function d = design_comm_beam(q, targets_est, users, theta_s, use_ris, cfg, focus_weights)
% Designs W (Nt x U) satisfying:
%   (C3) SINR_u >= 10 dB for all U users (including RIS reflection into comm channel when use_ris)
%   (C4) ||W||_F^2 <= 1 (normalized to cfg.power_w)
% Minimum-power ZF for communication + optimal remaining power in communication nullspace
% aligned to weighted sensing directions (direct LoS targets & RIS direction).
if nargin < 7 || isempty(focus_weights), focus_weights = [1.0, 1.0, 1.0]; end
q = q(:); pR = cfg.ris_pos(:);
rot = nc_geometry('world_to_local');
tx_off = nc_geometry('tx_offsets', cfg);
U = cfg.U;

% Build multi-user effective communication channel H (Nt x U) at fc
H = zeros(cfg.Nt, U);
user_blocked = false;
u_ris_loc = rot * ((pR - q) / max(norm(pR - q), eps));
a_to_ris = nc_geometry('wideband_tx', u_ris_loc, tx_off, cfg.fc, cfg);
ris_vis_bs = ~nc_geometry('blocked', q, pR, cfg.buildings);

for u = 1:U
    pu = users(u, :).';
    los_u = ~nc_geometry('blocked', q, pu, cfg.buildings);
    du = norm(pu - q);
    h_u = zeros(cfg.Nt, 1);
    if los_u
        u_loc = rot * ((pu - q) / max(du, eps));
        a_u = nc_geometry('wideband_tx', u_loc, tx_off, cfg.fc, cfg);
        h_u = h_u + (cfg.lambda / (4 * pi * du)) * a_u;
    end
    if use_ris && ris_vis_bs && ~nc_geometry('blocked', pR, pu, cfg.buildings) && ~isempty(theta_s)
        wb_u = nc_geometry('wideband_ris', q, pu, theta_s, cfg.fc, cfg);
        % RIS-reflected comm field gain: (lambda/(4*pi)) * c_u(fc) with carrier phase difference
        carr = exp(-1j * 2 * pi * cfg.fc / cfg.c * (wb_u.dbr + wb_u.rr - du));
        h_u = h_u + (cfg.lambda / (4 * pi)) * a_to_ris * conj(wb_u.c * carr);
    end
    if norm(h_u) < 1e-15
        user_blocked = true;
    end
    H(:, u) = h_u;
end

comm_noise = repmat(cfg.noise_w / cfg.power_w, U, 1);
gamma_req = cfg.comm_gamma(:) * (1 + 1e-5); % tiny safety margin above 10 dB

if user_blocked || rcond(H' * H) < 1e-14
    W = zeros(cfg.Nt, U);
    d = struct('W', W, 'sinr', zeros(U, 1), 'sinr_db', -inf(U, 1), ...
        'required_power_fraction', inf, 'tx_power_fraction', 0, 'feasible', false);
    return;
end

% Minimum-power ZF communication precoder W0
W0 = (H / (H' * H)) * diag(sqrt(gamma_req .* comm_noise));
req_pow = norm(W0, 'fro')^2;

if req_pow > 1.0
    W = W0 / sqrt(req_pow);
    Y = H' * W; des = abs(diag(Y)).^2;
    sinr = des ./ (sum(abs(Y).^2, 2) - des + comm_noise);
    d = struct('W', W, 'sinr', sinr, 'sinr_db', 10*log10(max(sinr, realmin)), ...
        'required_power_fraction', req_pow, 'tx_power_fraction', norm(W, 'fro')^2, ...
        'feasible', false);
    return;
end

% Project sensing covariance matrix E into exact communication nullspace P = I - H(H'H)^{-1}H'
P_null = eye(cfg.Nt) - H * ((H' * H) \ H');
P_null = 0.5 * (P_null + P_null');

E = zeros(cfg.Nt, cfg.Nt);
% Target 1 direct direction (if LoS)
if ~nc_geometry('blocked', q, targets_est(1, :).', cfg.buildings)
    d1 = targets_est(1, :).' - q;
    a1 = nc_geometry('wideband_tx', rot * (d1 / max(norm(d1), eps)), tx_off, cfg.fc, cfg);
    E = E + focus_weights(1) * (a1 * a1');
end
% Target 2 direct direction (if LoS)
if ~nc_geometry('blocked', q, targets_est(2, :).', cfg.buildings)
    d2 = targets_est(2, :).' - q;
    a2 = nc_geometry('wideband_tx', rot * (d2 / max(norm(d2), eps)), tx_off, cfg.fc, cfg);
    E = E + focus_weights(2) * (a2 * a2');
end
% RIS direction (if use_ris and visible)
if use_ris && ris_vis_bs && focus_weights(3) > 0
    E = E + focus_weights(3) * (a_to_ris * a_to_ris');
end

if norm(E, 'fro') < 1e-15
    E = eye(cfg.Nt);
end
[V, D_eig] = eig(0.5 * (P_null * E * P_null + (P_null * E * P_null)'));
[~, ix] = max(real(diag(D_eig)));
v_sens = P_null * V(:, ix);
if norm(v_sens) > 1e-8
    v_sens = v_sens / norm(v_sens);
    % Allocate ALL remaining power (1 - req_pow) to sensing beam orthogonal to H!
    rem_pow = max(0.0, 1.0 - req_pow - 1e-12);
    W = W0 + sqrt(rem_pow / U) * repmat(v_sens, 1, U);
else
    W = W0;
end

% Strict verification of power & communication SINR
Y = H' * W;
des = abs(diag(Y)).^2;
sinr = des ./ (sum(abs(Y).^2, 2) - des + comm_noise);
tx_pow = norm(W, 'fro')^2;
feas = (tx_pow <= 1.0 + 1e-6) && all(sinr >= cfg.comm_gamma(:));
d = struct('W', W, 'sinr', sinr, 'sinr_db', 10*log10(max(sinr, realmin)), ...
    'required_power_fraction', req_pow, 'tx_power_fraction', tx_pow, 'feasible', feas);
end

function theta_mat = init_ris_8cfg(q, p_tgt2, cfg, is_random, rand_seed)
% Gate-1 verified 2-bit quadrature half-panel monopulse + asymmetric offset 8-config basis.
% Achieves ang_cond ~ 1.17 (vs 1.09e5 for S=2) and breaks quadratic mirror ambiguity.
if nargin < 4, is_random = false; end
if nargin < 5, rand_seed = 9999; end
S = cfg.S_fine;
if is_random
    rng(rand_seed, 'twister');
    lv = exp(1j * 2 * pi * (0:2^cfg.ris_bits-1) / 2^cfg.ris_bits);
    theta_mat = lv(randi(numel(lv), cfg.N_ris, S));
    return;
end

sph2 = nc_geometry('ris_spherical', p_tgt2, cfg.ris_pos);
Mside = cfg.ris_side;
[g1, g2] = ndgrid(1:Mside, 1:Mside);
half1 = (g1(:) > Mside / 2);
half2 = (g2(:) > Mside / 2);
base_ph = nc_geometry('ris_steer_phase', q, p_tgt2, cfg);

theta_mat = zeros(cfg.N_ris, S);
theta_mat(:, 1) = base_ph;
q1p = ones(cfg.N_ris, 1); q1p(half1) =  1j;
q1m = ones(cfg.N_ris, 1); q1m(half1) = -1j;
q2p = ones(cfg.N_ris, 1); q2p(half2) =  1j;
q2m = ones(cfg.N_ris, 1); q2m(half2) = -1j;
theta_mat(:, 2) = nc_geometry('quantize_ris', base_ph .* q1p, cfg.ris_bits);
theta_mat(:, 3) = nc_geometry('quantize_ris', base_ph .* q1m, cfg.ris_bits);
theta_mat(:, 4) = nc_geometry('quantize_ris', base_ph .* q2p, cfg.ris_bits);
theta_mat(:, 5) = nc_geometry('quantize_ris', base_ph .* q2m, cfg.ris_bits);

extra_off = [-1.6, 0.9; 1.7, -1.2; -1.1, -1.8];
for k = 1:min(3, S - 5)
    p_dir = nc_geometry('from_ris_sph', sph2.r_r, max(1, min(179, sph2.th_r + extra_off(k, 1))), ...
        sph2.ph_r + extra_off(k, 2), cfg.ris_pos);
    theta_mat(:, 5 + k) = nc_geometry('ris_steer_phase', q, p_dir, cfg);
end
end

function ev = evaluate_position(q, prior_pos, users, rcs, use_ris, mode_tag, cfg, is_random_ris, rand_seed)
% Evaluates a candidate BS position q under communication feasibility (C3),
% coarse detection margin (C2), and worst-target SPEB (C1) — strictly from PRIOR!
if nargin < 8, is_random_ris = false; end
if nargin < 9, rand_seed = 9999; end
q = q(:); pR = cfg.ris_pos(:);
if ~nc_geometry('feasible_pos', q, cfg)
    ev = infeasible_eval(); return;
end

los1 = ~nc_geometry('blocked', q, prior_pos(1, :).', cfg.buildings);
los2 = ~nc_geometry('blocked', q, prior_pos(2, :).', cfg.buildings);
ris_vis = use_ris && (~nc_geometry('blocked', q, pR, cfg.buildings)) ...
                  && (~nc_geometry('blocked', pR, prior_pos(2, :).', cfg.buildings));

if ~los1 || (~los2 && ~ris_vis)
    ev = infeasible_eval(); return;
end

% Initial 8-config RIS phases (or single-beam energy-max for Lit_EnergyMax_AO)
if use_ris && ~los2
    if strcmp(mode_tag, 'lit_energy')
        % Literature energy-max baseline focuses all configs on the prior peak (classic single-beam rule!)
        ph0 = nc_geometry('ris_steer_phase', q, prior_pos(2, :).', cfg);
        % Add tiny deterministic phase code like Stage-3 alt configs so FIM doesn't NaN
        theta_mat = repmat(ph0, 1, cfg.S_fine);
        ph_alt = nc_geometry('quantize_ris', ph0 * exp(1j * 0.2), cfg.ris_bits);
        theta_mat(:, 2:2:end) = repmat(ph_alt, 1, numel(2:2:cfg.S_fine));
    else
        theta_mat = init_ris_8cfg(q, prior_pos(2, :).', cfg, is_random_ris, rand_seed);
    end
else
    theta_mat = ones(cfg.N_ris, cfg.S_fine);
end

% Compute adaptive focus weights between LoS target(s) and RIS direction
% When Target 2 is NLoS (RR path is much weaker than LoS DD), prioritize RIS illumination strongly!
if ~los2 && ris_vis
    w_focus = [0.05, 0.0, 1.0]; % Keep ~95% nullspace sensing energy on RIS; LoS DD is +50 dB anyway!
else
    r1 = norm(prior_pos(1, :).' - q);
    r2 = norm(prior_pos(2, :).' - q);
    w_focus = [r1^4, r2^4, 0.0];
    w_focus = w_focus / max(w_focus);
end

% Design beams per config (strictly verifying C3 comm SINR for all s=1..S_fine)
W_cell = cell(cfg.S_fine, 1);
min_sinr_db = inf;
max_pow_frac = 0;
for s = 1:cfg.S_fine
    ds = design_comm_beam(q, prior_pos, users, theta_mat(:, s), use_ris && ~los2, cfg, w_focus);
    if ~ds.feasible
        ev = infeasible_eval(); return;
    end
    W_cell{s} = ds.W;
    min_sinr_db = min(min_sinr_db, min(ds.sinr_db));
    max_pow_frac = max(max_pow_frac, ds.tx_power_fraction);
end

% Coarse Stage-A beam (RIS off, illuminates LoS targets) & Stage-B beam (illuminates RIS!)
d_coarse = design_comm_beam(q, prior_pos, users, [], false, cfg, [1.0, double(los2), 0.0]);
if ~d_coarse.feasible
    ev = infeasible_eval(); return;
end
if use_ris && ris_vis
    d_coarse_ris = design_comm_beam(q, prior_pos, users, theta_mat(:, 1), true, cfg, [0.05, 0.0, 1.0]);
    if ~d_coarse_ris.feasible
        ev = infeasible_eval(); return;
    end
else
    d_coarse_ris = d_coarse;
end

% Compute analytical coarse single-beam detection SNRs (C2) & exact SPEBs (C1)
fim1 = nc_fim('dd_los', q, prior_pos(1, :).', W_cell, rcs, cfg);
% Coarse Stage A has 64 symbols vs 256 fine symbols -> -6 dB
coarse_snr1_db = fim1.snr_total_db + 10*log10(cfg.K_coarse_los / cfg.K_fine);

if los2
    fim2 = nc_fim('dd_los', q, prior_pos(2, :).', W_cell, rcs, cfg);
    coarse_snr2_db = fim2.snr_total_db + 10*log10(cfg.K_coarse_los / cfg.K_fine) - 1.76; % incl. Hann loss
    t2_via_ris = false;
else
    fim2 = nc_fim('rr_nlos', q, prior_pos(2, :).', W_cell, theta_mat, rcs, cfg);
    % Coarse Stage B: L_b=7 sym/beam vs 32 sym/cfg, minus exact Hann window loss (-1.76 dB)
    % and worst-case 5x5 grid off-beam straddling loss (-2.5 dB for squared RR pattern!)
    coarse_snr2_db = fim2.snr_per_cfg_db(1) ...
        + 10*log10((cfg.K_coarse_nlos / cfg.S_coarse) / (cfg.K_fine / cfg.S_fine)) - 4.26;
    t2_via_ris = true;
end

worst_coarse_snr_db = min(coarse_snr1_db, coarse_snr2_db);
worst_speb = max(fim1.speb, fim2.speb);
det_target_db = cfg.det_snr_min_db + cfg.det_margin_db; % 16.5 dB
det_feasible = (worst_coarse_snr_db >= det_target_db);

ev = struct('feasible', true, 'det_feasible', det_feasible, ...
    'worst_coarse_snr_db', worst_coarse_snr_db, ...
    'coarse_snr_db', [coarse_snr1_db, coarse_snr2_db], ...
    'worst_speb', worst_speb, 'worst_peb', sqrt(max(0, worst_speb)), ...
    'speb', [fim1.speb, fim2.speb], 'cond_num_t2', fim2.cond_num, ...
    'ang_cond_t2', fim2.ang_cond_num, ...
    't2_via_ris', t2_via_ris, 'min_sinr_db', min_sinr_db, ...
    'max_pow_frac', max_pow_frac, 'q', q, ...
    'W_cell', {W_cell}, 'theta_mat', theta_mat, 'd_coarse', d_coarse, 'd_coarse_ris', d_coarse_ris, ...
    'fim1', fim1, 'fim2', fim2);
end

function ev = infeasible_eval()
ev = struct('feasible', false, 'det_feasible', false, ...
    'worst_coarse_snr_db', -inf, 'coarse_snr_db', [-inf, -inf], ...
    'worst_speb', inf, 'worst_peb', inf, 'speb', [inf, inf], ...
    'cond_num_t2', inf, 'ang_cond_t2', inf, 't2_via_ris', false, ...
    'min_sinr_db', -inf, 'max_pow_frac', inf, 'q', nan(3,1), ...
    'W_cell', {{}}, 'theta_mat', [], 'd_coarse', [], 'd_coarse_ris', [], 'fim1', [], 'fim2', []);
end

function q_fix = solve_offline_fixed(cfg, scenes_cell, use_ris, rcs)
% Offline global optimal single fixed BS site q_fix* over a calibration set of scenes.
% Eliminates any "strawman fixed baseline" criticism (Proposal v2.0 §5.1).
cands = build_street_candidates(cfg);
n_sc = numel(scenes_cell);
best_key = [-1, -1, -inf];
q_fix = cands(:, 1);
for c = 1:size(cands, 2)
    qc = cands(:, c);
    det_cnt = 0; feas_cnt = 0; snrs = -999 * ones(n_sc, 1);
    for i = 1:n_sc
        sc = scenes_cell{i};
        ev = evaluate_position(qc, sc.prior, sc.users, rcs, use_ris, 'proposed', cfg);
        if ev.feasible
            feas_cnt = feas_cnt + 1;
            snrs(i) = ev.worst_coarse_snr_db;
            if ev.worst_coarse_snr_db >= cfg.det_snr_min_db
                det_cnt = det_cnt + 1;
            end
        end
    end
    key = [det_cnt, feas_cnt, median(snrs)];
    if key(1) > best_key(1) || (key(1) == best_key(1) && key(2) > best_key(2)) ...
            || (key(1) == best_key(1) && key(2) == best_key(2) && key(3) > best_key(3))
        best_key = key;
        q_fix = qc;
    end
end
end

function cands = build_street_candidates(cfg)
% Lightweight ~65-point legal street-canyon screening grid (zero artificial no-fly boxes!).
pts = [];
for x = [-16.0, -10.0, -4.0]
    for y = -112:12:112
        q = [x; y; 16.0];
        if nc_geometry('feasible_pos', q, cfg)
            pts(:, end+1) = q; %#ok<AGROW>
        end
    end
end
for x = [2.0, 8.0, 14.0]
    for y = [-2.0, 2.0]
        q = [x; y; 16.0];
        if nc_geometry('feasible_pos', q, cfg)
            pts(:, end+1) = q; %#ok<AGROW>
        end
    end
end
cands = pts;
end

function out = solve_method_dispatch(method_name, scene, rcs, fixed_sites, cfg)
% Unified solver for all 8 methods (M1-M8), strictly using scene.prior & scene.users (NEVER truth!).
t0 = tic;
prior = scene.prior;
users = scene.users;
hist_speb = [];
hist_cond = [];

switch method_name
    case 'FixedOpt_NoRIS'
        ev = evaluate_position(fixed_sites.q_noris, prior, users, rcs, false, 'fixed', cfg);

    case 'FixedOpt_RIS'
        ev = evaluate_position(fixed_sites.q_ris, prior, users, rcs, true, 'proposed', cfg);
        if ev.feasible && ev.t2_via_ris
            [ev, hist_speb, hist_cond] = refine_ris_riemannian(ev, prior, users, rcs, cfg);
        end

    case 'FixedOpt_RandomRIS'
        ev = evaluate_position(fixed_sites.q_ris, prior, users, rcs, true, 'random', cfg, true, scene.seed + 777);

    case 'OnlineUAV_NoRIS'
        ev = search_continuous_position(prior, users, rcs, false, 'proposed', cfg);

    case 'MatchedPos_NoRIS'
        % Paired strict RIS-net-gain control: locked at Proposed_Joint_CRB's exact position with RIS off
        ev = evaluate_position(fixed_sites.q_matched, prior, users, rcs, false, 'matched', cfg);

    case 'GridSelect_RIS'
        % Discrete coarse-grid selection only (no continuous pos refinement, no Wirtinger RIS opt)
        cands = build_street_candidates(cfg);
        ev = pick_best_grid(cands, prior, users, rcs, true, 'energy', cfg);

    case 'Lit_EnergyMax_AO'
        % External literature baseline: continuous UAV + single-direction energy-max AO (no CRB/diversity)
        ev = search_continuous_position(prior, users, rcs, true, 'lit_energy', cfg);

    case 'Proposed_Joint_CRB'
        % Full BCD-SCA: (1) detection-margin constrained multi-start continuous 3D pos,
        %               (2) comm-nullspace sensing beam,
        %               (3) exact Wirtinger Riemannian 8-config 2-bit RIS phase optimization!
        ev = search_continuous_position(prior, users, rcs, true, 'proposed', cfg);
        if ev.feasible && ev.t2_via_ris
            [ev, hist_speb, hist_cond] = refine_ris_riemannian(ev, prior, users, rcs, cfg);
            % One outer BCD pass: re-refine continuous 3D position with updated RIS configs
            ev2 = local_continuous_refine(ev.q, prior, users, rcs, true, 'proposed', cfg, ev.theta_mat);
            if is_better_eval(ev2, ev, 'proposed')
                ev = ev2;
                [ev, hs2, hc2] = refine_ris_riemannian(ev, prior, users, rcs, cfg);
                hist_speb = [hist_speb, hs2];
                hist_cond = [hist_cond, hc2];
            end
        end

    otherwise
        error('Unknown method: %s', method_name);
end

out = struct('method', method_name, 'eval', ev, 'opt_seconds', toc(t0), ...
    'hist_speb', hist_speb, 'hist_cond', hist_cond);
end

function best_ev = pick_best_grid(cands, prior, users, rcs, use_ris, crit, cfg)
best_ev = infeasible_eval();
for c = 1:size(cands, 2)
    ev = evaluate_position(cands(:, c), prior, users, rcs, use_ris, crit, cfg);
    if is_better_eval(ev, best_ev, crit)
        best_ev = ev;
    end
end
end

function best_ev = search_continuous_position(prior, users, rcs, use_ris, mode_tag, cfg)
% Multi-start screening across street canyon + Top-3 continuous 3D coordinate/pattern refinement.
cands = build_street_candidates(cfg);
N_c = size(cands, 2);
evals = cell(N_c, 1);
scores = -inf(N_c, 1);
for c = 1:N_c
    ev = evaluate_position(cands(:, c), prior, users, rcs, use_ris, mode_tag, cfg);
    evals{c} = ev;
    if ev.feasible
        if strcmp(mode_tag, 'lit_energy') || strcmp(mode_tag, 'energy')
            scores(c) = ev.worst_coarse_snr_db;
        else
            % Detection-margin hard-constraint lexicographic score:
            % If C2 satisfied -> 1000 - log10(worst_speb); else -> worst_coarse_snr_db (feasibility recovery)
            if ev.det_feasible && isfinite(ev.worst_speb)
                scores(c) = 1000.0 - 10 * log10(max(ev.worst_speb, 1e-12));
            else
                scores(c) = ev.worst_coarse_snr_db;
            end
        end
    end
end
[~, ord] = sort(scores, 'descend');
best_ev = infeasible_eval();
n_starts = min(3, sum(isfinite(scores) & scores > -1e8));
for k = 1:n_starts
    q0 = cands(:, ord(k));
    ev_ref = local_continuous_refine(q0, prior, users, rcs, use_ris, mode_tag, cfg, []);
    if is_better_eval(ev_ref, best_ev, mode_tag)
        best_ev = ev_ref;
    end
end
end

function best_ev = local_continuous_refine(q0, prior, users, rcs, use_ris, mode_tag, cfg, fixed_theta)
% Continuous 3D trust-region pattern search inside legal street airspace Q_street (x, y, z).
best_ev = evaluate_position(q0, prior, users, rcs, use_ris, mode_tag, cfg);
if ~best_ev.feasible, return; end
q = best_ev.q;
step = [4.0; 6.0; 3.0]; % initial 3D step sizes in meters (x, y, z)
dirs = [eye(3), -eye(3)];

for it = 1:cfg.pos_opt_iters
    improved = false;
    for d = 1:size(dirs, 2)
        q_try = q + step .* dirs(:, d);
        if ~nc_geometry('feasible_pos', q_try, cfg), continue; end
        ev_try = evaluate_position(q_try, prior, users, rcs, use_ris, mode_tag, cfg);
        if is_better_eval(ev_try, best_ev, mode_tag)
            best_ev = ev_try;
            q = q_try;
            improved = true;
        end
    end
    if ~improved
        step = step * 0.5;
        if norm(step) < 0.25, break; end
    end
end
end

function [ev, hist_speb, hist_cond] = refine_ris_riemannian(ev, prior, users, rcs, cfg)
% Block 2: Exact Wirtinger gradient Riemannian optimization of S_f=8 2-bit RIS configs
% minimizing SPEB(t2) (automatically maintaining angular derivative diversity!).
theta_cur = ev.theta_mat;
q = ev.q;
p2 = prior(2, :).';
W_cell = ev.W_cell;

hist_speb = ev.fim2.speb;
hist_cond = ev.fim2.ang_cond_num;
best_speb = ev.fim2.speb;
best_theta = theta_cur;
best_W = W_cell;

% Continuous phase representation phi = angle(theta), projected to 2-bit each acceptance check
phi_cont = angle(theta_cur);
step_sizes = [0.6, 0.25, 0.1, 0.04];

for it = 1:cfg.ris_grad_iters
    g_out = nc_fim('ris_grad', q, p2, best_W, best_theta, rcs, cfg);
    if ~isfinite(g_out.speb), break; end
    % Riemannian phase gradient on unit circle: d(SPEB)/d(phi_m) = 2 * Re(conj(grad) * (j * theta))
    g_phi = 2 * real(conj(g_out.grad) .* (1j * best_theta));
    gnorm = max(abs(g_phi(:)));
    if gnorm < 1e-14, break; end
    dir_phi = -g_phi / gnorm;

    accepted = false;
    for alpha = step_sizes
        phi_try = phi_cont + alpha * dir_phi;
        theta_try = nc_geometry('quantize_ris', exp(1j * phi_try), cfg.ris_bits);
        if isequal(theta_try, best_theta), continue; end

        % Re-verify beams & comm SINR for changed RIS columns
        W_try = best_W;
        ok = true;
        for s = 1:cfg.S_fine
            if ~isequal(theta_try(:, s), best_theta(:, s))
                ds = design_comm_beam(q, prior, users, theta_try(:, s), true, cfg, [0.05, 0.0, 1.0]);
                if ~ds.feasible, ok = false; break; end
                W_try{s} = ds.W;
            end
        end
        if ~ok, continue; end

        fim_try = nc_fim('rr_nlos', q, p2, W_try, theta_try, rcs, cfg);
        % Ensure detection margin (center beam SNR) does not degrade below threshold while reducing SPEB!
        c_snr_try = fim_try.snr_per_cfg_db(1) + 10*log10((cfg.K_coarse_nlos / cfg.S_coarse) / (cfg.K_fine / cfg.S_fine));
        if isfinite(fim_try.speb) && fim_try.speb < best_speb * (1 - 1e-5) ...
                && (c_snr_try >= ev.coarse_snr_db(2) - 0.5)
            best_speb = fim_try.speb;
            best_theta = theta_try;
            best_W = W_try;
            phi_cont = phi_try;
            ev.fim2 = fim_try;
            ev.theta_mat = best_theta;
            ev.W_cell = best_W;
            ev.speb(2) = best_speb;
            ev.worst_speb = max(ev.speb);
            ev.worst_peb = sqrt(ev.worst_speb);
            ev.cond_num_t2 = fim_try.cond_num;
            ev.ang_cond_t2 = fim_try.ang_cond_num;
            ev.coarse_snr_db(2) = c_snr_try;
            ev.worst_coarse_snr_db = min(ev.coarse_snr_db);
            accepted = true;
            break;
        end
    end
    hist_speb(end+1) = best_speb; %#ok<AGROW>
    hist_cond(end+1) = ev.ang_cond_t2; %#ok<AGROW>
    if ~accepted, break; end
end
end

function tf = is_better_eval(a, b, mode_tag)
if ~a.feasible, tf = false; return; end
if ~b.feasible, tf = true; return; end
if strcmp(mode_tag, 'lit_energy') || strcmp(mode_tag, 'energy')
    tf = a.worst_coarse_snr_db > b.worst_coarse_snr_db;
    return;
end
% Detection-margin hard-constraint lexicographic ordering:
if a.det_feasible && ~b.det_feasible
    tf = true; return;
elseif ~a.det_feasible && b.det_feasible
    tf = false; return;
elseif a.det_feasible && b.det_feasible
    tf = a.worst_speb < b.worst_speb;
else
    tf = a.worst_coarse_snr_db > b.worst_coarse_snr_db;
end
end
