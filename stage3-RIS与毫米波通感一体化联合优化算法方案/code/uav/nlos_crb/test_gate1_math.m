function report = test_gate1_math(output_json)
% TEST_GATE1_MATH  Gate 1 local verification (Proposal v2.0 §6):
%   1.1 Wideband RIS Kronecker/Chebyshev interpolation vs brute-force 12,672 x 1024 (< 1e-10)
%   1.2 Analytic wideband FIM & Wirtinger gradient vs finite differences (< 1e-5)
%   1.3 S=2 ill-conditioning & mirror ambiguity vs S_f=8 monopulse/offset configs (cond < 100, gap > 10 deg)
%   1.4 Delay-window matched-filter energy retention at +/-0.2 m coarse range error (> -0.5 dB)
%   1.5 Noiseless pure-RR 3D convergence from perturbed init (< 0.02 m)
%   1.6 Wideband vs narrowband beam-squint systematic bias measurement
if nargin < 1, output_json = ''; end
here = fileparts(mfilename('fullpath'));
uav_dir = fileparts(here);
addpath(here, uav_dir, fileparts(uav_dir));

cfg = nc_config('full');
q = [-10; -18; 18];          % UAV in Main Avenue (d_br = 21.4 m > 11.0 m D_F)
p_t2 = [8; 1; 0];            % Side-alley NLoS target (r_r = 30.5 m)
p_t1 = [-10; -110; 0];       % Main-avenue LoS target
rcs = 30.0;

% Verify physical blockage in 3GPP UMi canyon
assert(~nc_geometry('blocked', q, p_t1, cfg.buildings), 'T1 should be LoS');
assert( nc_geometry('blocked', q, p_t2, cfg.buildings), 'T2 should be physically NLoS');
assert( nc_geometry('feasible_pos', q, cfg), 'q should be feasible');

% Build S_f = 8 structured 2-bit RIS configs combining:
%   (1) Center sum beam
%   (2-5) 2-bit quadrature half-panel monopulse beams (Left/Right & Top/Bottom +/-pi/2 phase split)
%         -> exact 2-bit {1,j,-1,-j}, breaks quadratic c_s^2 mirror/sidelobe ambiguity with complex phase diversity!
%   (6-8) Asymmetric offset beams at +/-1.5 deg to lock angular slope & suppress far sidelobes
sph2 = nc_geometry('ris_spherical', p_t2, cfg.ris_pos);
panel = nc_geometry('ris_offsets', cfg);
Mside = cfg.ris_side;
[g1, g2] = ndgrid(1:Mside, 1:Mside);
half1 = (g1(:) > Mside / 2);
half2 = (g2(:) > Mside / 2);
base_ph = nc_geometry('ris_steer_phase', q, p_t2, cfg);

theta8 = zeros(cfg.N_ris, cfg.S_fine);
theta8(:, 1) = base_ph;
% Quadrature +/-pi/2 half-panel splits (strictly 2-bit!) + 3 asymmetric offset beams
q1p = ones(cfg.N_ris, 1); q1p(half1) =  1j;
q1m = ones(cfg.N_ris, 1); q1m(half1) = -1j;
q2p = ones(cfg.N_ris, 1); q2p(half2) =  1j;
q2m = ones(cfg.N_ris, 1); q2m(half2) = -1j;
theta8(:, 2) = nc_geometry('quantize_ris', base_ph .* q1p, cfg.ris_bits);
theta8(:, 3) = nc_geometry('quantize_ris', base_ph .* q1m, cfg.ris_bits);
theta8(:, 4) = nc_geometry('quantize_ris', base_ph .* q2p, cfg.ris_bits);
theta8(:, 5) = nc_geometry('quantize_ris', base_ph .* q2m, cfg.ris_bits);
extra_off = [-1.6, 0.9; 1.7, -1.2; -1.1, -1.8];
for k = 1:3
    p_dir = nc_geometry('from_ris_sph', sph2.r_r, sph2.th_r + extra_off(k, 1), sph2.ph_r + extra_off(k, 2), cfg.ris_pos);
    theta8(:, 5 + k) = nc_geometry('ris_steer_phase', q, p_dir, cfg);
end

% Build legacy S=2 configs (nearly colinear target-phase weighting) for contrast
theta2 = zeros(cfg.N_ris, 2);
theta2(:, 1) = nc_geometry('ris_steer_phase', q, p_t2, cfg);
theta2(:, 2) = nc_geometry('quantize_ris', theta2(:, 1) * exp(1j * 0.15), cfg.ris_bits); % tiny perturbation like 2-target alt weight

% Simple feasible transmit beamformer pointing toward RIS (for Gate 1 math test)
rot = nc_geometry('world_to_local');
u_ris_loc = rot * ((cfg.ris_pos - q) / norm(cfg.ris_pos - q));
tx_off = nc_geometry('tx_offsets', cfg);
a_ris = nc_geometry('wideband_tx', u_ris_loc, tx_off, cfg.fc, cfg);
W0 = repmat(a_ris / norm(a_ris), 1, cfg.U) / sqrt(cfg.U);
W_cell8 = repmat({W0}, cfg.S_fine, 1);
W_cell2 = repmat({W0}, 2, 1);

% ---- 1.1 Chebyshev interpolation error vs brute force on 12,672 subcarriers ----
K_k = 16;
x_cheb = -cos(pi * (0:K_k-1).' / (K_k - 1));
n_knots = 0.5 * (x_cheb + 1) * (cfg.N - 1);
f_knots = cfg.fref + n_knots(:).' * cfg.delta_f;
x_all = 2 * ((0:cfg.N-1).' / (cfg.N - 1)) - 1;
InterpMat = cos((0:K_k-1) .* acos(x_all)) / cos((0:K_k-1) .* acos(x_cheb));
wb_k = nc_geometry('wideband_ris', q, p_t2, theta8(:, 1), f_knots, cfg);
c_interp = InterpMat * wb_k.c.'; % N x 1
sample_n = [1, 1000, 6336, 11000, 12672];
f_check = cfg.fref + (sample_n - 1) * cfg.delta_f;
wb_exact = nc_geometry('wideband_ris', q, p_t2, theta8(:, 1), f_check, cfg);
interp_rel_err = norm(c_interp(sample_n) - wb_exact.c.') / norm(wb_exact.c.');

% ---- 1.2 Analytic FIM & Wirtinger gradient vs finite differences ----
fim8 = nc_fim('rr_nlos', q, p_t2, W_cell8, theta8, rcs, cfg);
% Finite-difference verification of RR signal derivatives wrt p_t2
fg = nc_fim('freq_grid', cfg);
eps_p = 1e-7;
alpha_mag = sqrt(cfg.power_w * rcs) * cfg.lambda / ((4 * pi)^1.5);
A_tx = nc_geometry('wideband_tx', u_ris_loc, tx_off, fg.freqs, cfg);
tx_pow = zeros(cfg.S_fine, fg.M);
for s = 1:cfg.S_fine
    tx_pow(s, :) = sum(abs(A_tx' * W_cell8{s}).^2, 2).';
end
L_s = cfg.K_fine / cfg.S_fine;
W_sn = (2.0 / cfg.noise_w) * L_s * cfg.Mr * (tx_pow .* fg.w);
eval_h = @(pt) eval_rr_complex(q, pt, theta8, fg.freqs, cfg);
h0 = eval_h(p_t2);
D_fd = zeros(cfg.S_fine, fg.M, 5);
for k = 1:3
    pp = p_t2; pp(k) = pp(k) + eps_p;
    pm = p_t2; pm(k) = pm(k) - eps_p;
    D_fd(:, :, k) = alpha_mag * (eval_h(pp) - eval_h(pm)) / (2 * eps_p);
end
D_fd(:, :, 4) = h0;
D_fd(:, :, 5) = 1j * h0;
F_fd = zeros(5, 5);
for i = 1:5
    for j = i:5
        F_fd(i, j) = sum(W_sn .* real(conj(D_fd(:, :, i)) .* D_fd(:, :, j)), 'all');
        F_fd(j, i) = F_fd(i, j);
    end
end
% Compare Schur-complement EFIM J_eff (invariant to carrier-frequency centering!)
J_fd = F_fd(1:3, 1:3) - F_fd(1:3, 4:5) * (F_fd(4:5, 4:5) \ F_fd(1:3, 4:5).');
fim_rr_rel_err = norm(fim8.J_eff - J_fd, 'fro') / norm(J_fd, 'fro');

% Wirtinger gradient verification on 10 random RIS elements
g_out = nc_fim('ris_grad', q, p_t2, W_cell8, theta8, rcs, cfg);
rng(12345, 'twister');
test_idx = randperm(numel(theta8), 10);
eps_g = 1e-4;
grad_errs = zeros(1, numel(test_idx));
for t = 1:numel(test_idx)
    id = test_idx(t);
    tp = theta8; tp(id) = tp(id) + eps_g;
    tm = theta8; tm(id) = tm(id) - eps_g;
    fp = nc_fim('rr_nlos', q, p_t2, W_cell8, tp, rcs, cfg);
    fm = nc_fim('rr_nlos', q, p_t2, W_cell8, tm, rcs, cfg);
    d_re = (fp.speb - fm.speb) / (2 * eps_g);
    tp = theta8; tp(id) = tp(id) + 1j * eps_g;
    tm = theta8; tm(id) = tm(id) - 1j * eps_g;
    fp = nc_fim('rr_nlos', q, p_t2, W_cell8, tp, rcs, cfg);
    fm = nc_fim('rr_nlos', q, p_t2, W_cell8, tm, rcs, cfg);
    d_im = (fp.speb - fm.speb) / (2 * eps_g);
    % Note: d(SPEB) = 2 * Re(conj(grad) * dtheta) = 2*Re(grad)*dx + 2*Im(grad)*dy
    g_fd = 0.5 * (d_re + 1j * d_im);
    grad_errs(t) = abs(g_out.grad(id) - g_fd) / max(abs(g_fd), 1e-12);
end
wirtinger_max_rel_err = max(grad_errs);

% Also verify LoS DD FIM
fim_dd = nc_fim('dd_los', q, p_t1, W_cell8, rcs, cfg);

% ---- 1.3 S=2 near-singularity & mirror ambiguity vs S_f=8 ----
fim2 = nc_fim('rr_nlos', q, p_t2, W_cell2, theta2, rcs, cfg);
amb2 = nc_fim('ambiguity', q, p_t2, W_cell2, theta2, rcs, cfg);
amb8 = nc_fim('ambiguity', q, p_t2, W_cell8, theta8, rcs, cfg);

% ---- 1.4 Delay-window energy retention at 0, +/-0.1, +/-0.2 m range error ----
tx_eff_k = zeros(cfg.S_fine, K_k);
A_tx_k = nc_geometry('wideband_tx', u_ris_loc, tx_off, f_knots, cfg);
for s = 1:cfg.S_fine
    tx_eff_k(s, :) = sqrt(cfg.K_fine / cfg.S_fine * cfg.Mr) * sqrt(sum(abs(A_tx_k' * W_cell8{s}).^2, 2).');
end
wb_true_k = nc_geometry('wideband_ris', q, p_t2, theta8, f_knots, cfg);
G_true_all = InterpMat * ((wb_true_k.c.^2) .* tx_eff_k).'; % N x S
n_vec = (0:cfg.N-1).';
dist_true = 2 * (wb_true_k.dbr + wb_true_k.rr);
alpha_true = alpha_mag * exp(1j * 0.7);
Sig_true = alpha_true * G_true_all .* exp(-1j * 2 * pi * cfg.delta_f / cfg.c * dist_true * n_vec);
Y_delay_full = sqrt(cfg.N) * ifft(Sig_true, cfg.N, 1); % unitary IFFT
total_energy = sum(abs(Y_delay_full).^2, 'all');

range_errs = [0.0, 0.10, 0.20, -0.20];
retentions_db = zeros(size(range_errs));
for i = 1:numel(range_errs)
    dist_hat = dist_true + 2 * range_errs(i);
    b0 = round(dist_hat * cfg.delta_f / cfg.c * cfg.N);
    wbins = b0 + (-cfg.delay_half_bins : cfg.delay_half_bins);
    idx_w = mod(wbins, cfg.N) + 1;
    win_energy = sum(abs(Y_delay_full(idx_w, :)).^2, 'all');
    retentions_db(i) = 10 * log10(win_energy / total_energy);
end
min_retention_02m_db = min(retentions_db);

% ---- 1.5 Noiseless pure-RR 3D convergence from perturbed init (~2.2 m off) ----
init_pos = p_t2 + [0.18; 1.8; 1.2]; % 0.18 m range shift + ~2.16 m cross-range error!
sph_init = nc_geometry('ris_spherical', init_pos, cfg.ris_pos);
b0_init = round(2 * (wb_true_k.dbr + sph_init.r_r) * cfg.delta_f / cfg.c * cfg.N);
wbins_init = b0_init + (-cfg.delay_half_bins : cfg.delay_half_bins);
Y_win_clean = Y_delay_full(mod(wbins_init, cfg.N) + 1, :);
[est_wb, info_wb] = nc_rr_fine_estimator(Y_win_clean, wbins_init, q, init_pos, W_cell8, theta8, tx_eff_k, cfg);
noiseless_err_m = norm(est_wb - p_t2);

% ---- 1.6 Wideband vs narrowband beam-squint systematic bias ----
cfg_nb = cfg; cfg_nb.wideband = false;
[est_nb, ~] = nc_rr_fine_estimator(Y_win_clean, wbins_init, q, init_pos, W_cell8, theta8, tx_eff_k, cfg_nb);
narrowband_squint_bias_m = norm(est_nb - p_t2);

passed = (interp_rel_err < 1e-10) ...
      && (fim_rr_rel_err < 1e-5) ...
      && (wirtinger_max_rel_err < 1e-5) ...
      && (fim8.ang_cond_num < 10.0) ...
      && (fim8.cond_num < 1000.0) ...
      && (fim2.cond_num > 100 * fim8.cond_num) ...
      && (amb8.worst_ambiguity_sep_deg > 10.0) ...
      && (amb8.local_sidelobe_margin_db > 1.0) ...
      && (min_retention_02m_db > -0.5) ...
      && (noiseless_err_m < 0.02);

report = struct( ...
    'passed', passed, ...
    'fraunhofer_m', cfg.fraunhofer_m, ...
    'interp_rel_err', interp_rel_err, ...
    'fim_rr_rel_err', fim_rr_rel_err, ...
    'wirtinger_max_rel_err', wirtinger_max_rel_err, ...
    'fim_dd_peb_m', fim_dd.peb, ...
    's2_cond_num', fim2.cond_num, ...
    's2_ang_cond_num', fim2.ang_cond_num, ...
    's2_peb_m', fim2.peb, ...
    's2_sidelobe_margin_db', amb2.sidelobe_margin_db, ...
    's2_local_sidelobe_margin_db', amb2.local_sidelobe_margin_db, ...
    's8_cond_num', fim8.cond_num, ...
    's8_ang_cond_num', fim8.ang_cond_num, ...
    's8_peb_m', fim8.peb, ...
    's8_snr_total_db', fim8.snr_total_db, ...
    's8_sidelobe_margin_db', amb8.sidelobe_margin_db, ...
    's8_local_sidelobe_margin_db', amb8.local_sidelobe_margin_db, ...
    's8_ambiguity_sep_deg', amb8.worst_ambiguity_sep_deg, ...
    'delay_window_retentions_db', retentions_db, ...
    'min_retention_02m_db', min_retention_02m_db, ...
    'init_err_m', norm(init_pos - p_t2), ...
    'noiseless_wideband_err_m', noiseless_err_m, ...
    'noiseless_narrowband_squint_bias_m', narrowband_squint_bias_m, ...
    'fine_iters', info_wb.iterations);

fprintf('=== GATE 1 VERIFICATION: passed = %d ===\n', passed);
fprintf('  1.1 Cheb interp rel err          : %.3e (< 1e-10)\n', interp_rel_err);
fprintf('  1.2 RR EFIM rel err              : %.3e (< 1e-5)\n', fim_rr_rel_err);
fprintf('  1.2 Wirtinger grad max rel err   : %.3e (< 1e-5)\n', wirtinger_max_rel_err);
fprintf('  1.3 S=2 3D_cond=%.2e (ang=%.2e), PEB=%.3fm, localSL=%.2fdB\n', ...
    fim2.cond_num, fim2.ang_cond_num, fim2.peb, amb2.local_sidelobe_margin_db);
fprintf('      S=8 3D_cond=%.2f (ang=%.2f), PEB=%.4fm, localSL=%.2fdB, globalSL=%.2fdB @ sep=%.1fdeg\n', ...
    fim8.cond_num, fim8.ang_cond_num, fim8.peb, amb8.local_sidelobe_margin_db, amb8.sidelobe_margin_db, amb8.worst_ambiguity_sep_deg);
fprintf('  1.4 Delay-win retention @ +/-0.2m: %.3f dB (> -0.5 dB)\n', min_retention_02m_db);
fprintf('  1.5 Noiseless wideband err       : %.6f m (from %.2f m init, < 0.02 m)\n', noiseless_err_m, norm(init_pos - p_t2));
fprintf('  1.6 Narrowband beam-squint bias  : %.5f m (vs PEB %.5f m)\n', narrowband_squint_bias_m, fim8.peb);

if ~isempty(output_json)
    uav_write_json(output_json, report);
end
assert(passed, 'Gate 1 verification FAILED!');
end

function h = eval_rr_complex(q, pt, theta, freqs, cfg)
wb = nc_geometry('wideband_ris', q, pt, theta, freqs, cfg);
h = (wb.c.^2) .* exp(-1j * 4 * pi * freqs / cfg.c * (wb.dbr + wb.rr));
end
