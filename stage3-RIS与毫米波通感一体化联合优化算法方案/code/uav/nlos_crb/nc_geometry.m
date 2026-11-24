function out = nc_geometry(action, varargin)
% NC_GEOMETRY  3D street-canyon geometry, AABB blockage, & true wideband steering.
% Actions:
%   'blocked'          : (p0, p1, buildings) -> logical
%   'feasible_pos'     : (q, cfg) -> logical (legal street airspace + far-field)
%   'scene'            : (cfg, trial) -> struct with targets, users, priors, phases
%   'ris_offsets'      : (cfg) -> struct with x_vec, y_vec, e1, e2, offsets (3 x N_ris)
%   'tx_offsets'       : (cfg) -> 3 x Nt array positions in local frame
%   'rx_offsets'       : (cfg) -> 3 x Mr array positions in local frame
%   'world_to_local'   : () -> 3x3 proper rotation diag([1, -1, -1]) (local +z down)
%   'wideband_ris'     : (q, p_tgt, phase_mat, freqs, cfg) -> S x Nf complex gain c_s(f)
%                        and optional derivatives wrt RIS spherical angles (r_r, th_r, ph_r)
%   'ris_spherical'    : (p_tgt, p_ris) -> [r_r, th_r_deg, ph_r_deg, u_r(3x1)]
%   'from_ris_sph'     : (r_r, th_r_deg, ph_r_deg, p_ris) -> 3x1 world point

switch action
    case 'world_to_local'
        out = diag([1, -1, -1]);

    case 'blocked'
        out = is_blocked(varargin{1}, varargin{2}, varargin{3});

    case 'feasible_pos'
        out = is_feasible_pos(varargin{1}, varargin{2});

    case 'scene'
        out = make_scene(varargin{1}, varargin{2});

    case 'ris_offsets'
        out = ris_panel_offsets(varargin{1});

    case 'tx_offsets'
        cfg = varargin{1};
        [gx, gy] = ndgrid(0:cfg.Ntx-1, 0:cfg.Nty-1);
        out = cfg.d * [gx(:).'; gy(:).'; zeros(1, cfg.Nt)];

    case 'rx_offsets'
        cfg = varargin{1};
        [gx, gy] = ndgrid(0:cfg.Mx-1, 0:cfg.My-1);
        out = cfg.d * [gx(:).'; gy(:).'; zeros(1, cfg.Mr)];

    case 'ris_spherical'
        out = to_ris_spherical(varargin{1}, varargin{2});

    case 'from_ris_sph'
        out = from_ris_spherical(varargin{1}, varargin{2}, varargin{3}, varargin{4});

    case 'wideband_ris'
        out = eval_wideband_ris(varargin{:});

    case 'wideband_tx'
        out = eval_wideband_array(varargin{1}, varargin{2}, varargin{3}, varargin{4}, +1);

    case 'wideband_rx'
        out = eval_wideband_array(varargin{1}, varargin{2}, varargin{3}, varargin{4}, -1);

    case 'quantize_ris'
        out = quantize_phase(varargin{1}, varargin{2});

    case 'ris_steer_phase'
        out = steer_ris_phase(varargin{1}, varargin{2}, varargin{3});

    otherwise
        error('Unknown nc_geometry action: %s', action);
end
end

function tf = is_blocked(p0, p1, buildings)
p0 = p0(:); p1 = p1(:);
tf = false;
for b = 1:numel(buildings)
    if seg_aabb(p0, p1, buildings(b).bmin(:), buildings(b).bmax(:))
        tf = true;
        return;
    end
end
end

function hit = seg_aabb(p0, p1, bmin, bmax)
% Exact Kay-Kajiya slab intersection for segment t in [0, 1].
tmin = 0.0; tmax = 1.0;
for i = 1:3
    di = p1(i) - p0(i);
    if abs(di) < 1e-12
        if p0(i) < bmin(i) || p0(i) > bmax(i)
            hit = false; return;
        end
    else
        t1 = (bmin(i) - p0(i)) / di;
        t2 = (bmax(i) - p0(i)) / di;
        if t1 > t2, tmp = t1; t1 = t2; t2 = tmp; end
        tmin = max(tmin, t1);
        tmax = min(tmax, t2);
        if tmin > tmax
            hit = false; return;
        end
    end
end
hit = true;
end

function tf = is_feasible_pos(q, cfg)
q = q(:);
if q(3) < cfg.z_bounds(1) - 1e-9 || q(3) > cfg.z_bounds(2) + 1e-9
    tf = false; return;
end
if norm(q - cfg.ris_pos) < cfg.far_field_min_m - 1e-9
    tf = false; return;
end
% Legal street corridor: Main Avenue x in [-18, -2], y in [-140, 140]
% OR Side Alley x in [-2, 22], y in [-4, 4] (2 m clearance from 30 m walls)
clr = cfg.wall_clearance_m;
in_main = (q(1) >= -20 + clr - 1e-9) && (q(1) <= 0 - clr + 1e-9) && ...
          (q(2) >= -140 - 1e-9) && (q(2) <= 140 + 1e-9);
in_alley = (q(1) >= -20 + clr - 1e-9) && (q(1) <= 22 + 1e-9) && ...
           (q(2) >= -6 + clr - 1e-9) && (q(2) <= 6 - clr + 1e-9);
tf = in_main || in_alley;
end

function scene = make_scene(cfg, trial)
seed = cfg.seed + 10000 * trial;
rng(seed, 'twister');
side = 2 * (rand() >= 0.5) - 1; % -1 (South block) or +1 (North block)

users = zeros(cfg.U, 3);
% User 1 (near-block, West curb) & User 2 (far-block, East curb) -> natural 3D elevation/azimuth separation
y1 = side * (cfg.user1_y_abs_range(1) + diff(cfg.user1_y_abs_range) * rand());
y2 = side * (cfg.user2_y_abs_range(1) + diff(cfg.user2_y_abs_range) * rand());
users(1, :) = [-18.0 + 6.0 * rand(), y1, 0.0];
users(2, :) = [-8.0  + 6.0 * rand(), y2, 0.0];
yc = y2;

targets = zeros(cfg.Q, 3);
% Target 1: LoS target on Main Avenue in the active block
yt1 = side * (cfg.t1_y_abs_range(1) + diff(cfg.t1_y_abs_range) * rand());
targets(1, :) = [cfg.user_x_range(1) + diff(cfg.user_x_range) * rand(), yt1, 0.0];
% Target 2: Side-alley recessed target (naturally NLoS when UAV is tethered away from alley mouth)
targets(2, 1) = cfg.t2_x_range(1) + diff(cfg.t2_x_range) * rand();
targets(2, 2) = cfg.t2_y_range(1) + diff(cfg.t2_y_range) * rand();
targets(2, 3) = 0.0;

% External noisy horizontal prior (same prior supplied to all online methods)
prior = targets;
prior(:, 1:2) = targets(:, 1:2) + cfg.prior_sigma_m * randn(cfg.Q, 2);

scene = struct();
scene.trial = trial;
scene.seed = seed;
scene.side = side;
scene.yc = yc;
scene.users = users;
scene.targets = targets;
scene.prior = prior;
scene.scatter_phase = 2 * pi * rand(1, cfg.Q);
scene.rel_rcs = [1.0, 1.0]; % Equal nominal RCS so neither target is artificially favored
end

function panel = ris_panel_offsets(cfg)
% RIS planar UPA local tangent axes (e1, e2) orthonormal to ris_normal.
% For ris_normal = [1;0;0]: e1 = [0;1;0] (horizontal y), e2 = [0;0;1] (vertical z).
nR = cfg.ris_normal(:) / norm(cfg.ris_normal);
if abs(nR(2)) < 0.9
    e1 = [0; 1; 0] - nR(2) * nR; e1 = e1 / norm(e1);
else
    e1 = [1; 0; 0] - nR(1) * nR; e1 = e1 / norm(e1);
end
e2 = cross(nR, e1); e2 = e2 / norm(e2);
v = ((0:cfg.ris_side-1) - (cfg.ris_side-1)/2) * cfg.d;
[g1, g2] = ndgrid(v, v);
panel = struct('v', v(:), 'e1', e1, 'e2', e2, 'nR', nR, ...
    'offsets', e1 * g1(:).' + e2 * g2(:).');
end

function s = to_ris_spherical(p_tgt, p_ris)
% RIS-centered spherical coords:
%   r_r > 0, th_r in (0, 180) deg from +z (world up), ph_r in (-180, 180] deg from +x.
dvec = p_tgt(:) - p_ris(:);
r_r = norm(dvec);
u_r = dvec / max(r_r, eps);
th_r = acosd(max(-1, min(1, u_r(3))));
ph_r = atan2d(u_r(2), u_r(1));
s = struct('r_r', r_r, 'th_r', th_r, 'ph_r', ph_r, 'u_r', u_r);
end

function p = from_ris_spherical(r_r, th_r, ph_r, p_ris)
u_r = [sind(th_r)*cosd(ph_r); sind(th_r)*sind(ph_r); cosd(th_r)];
p = p_ris(:) + r_r * u_r;
end

function res = eval_wideband_ris(q, p_tgt, phase_mat, freqs, cfg)
% EVAL_WIDEBAND_RIS  Exact separable Kronecker wideband RIS response c_s(f_n).
% Inputs:
%   q         : 3x1 BS position
%   p_tgt     : 3x1 target position
%   phase_mat : N_ris x S complex RIS phase matrix (unit-modulus entries)
%   freqs     : 1 x Nf vector of subcarrier frequencies (Hz)
%   cfg       : config struct (if ~cfg.wideband, evaluates all freqs at cfg.fc)
% Outputs struct:
%   c         : S x Nf complex single-hop RIS response c_s(f_n)
%               (absolute physical amplitude factor: d^2/lambda_n * sqrt(ci*co) / (dbr*rr) * sum_m theta_m exp(...))
%   dc_du1    : S x Nf derivative of c wrt psi1 = e1'*(u_r - u_in) (dimensionless)
%   dc_du2    : S x Nf derivative of c wrt psi2 = e2'*(u_r - u_in)
%   dbr, rr, ci, co, u_in, u_r, panel
q = q(:); p_tgt = p_tgt(:); pR = cfg.ris_pos(:);
panel = ris_panel_offsets(cfg);
v_in = q - pR;   dbr = norm(v_in); u_in = v_in / max(dbr, eps); % RIS -> BS
v_out = p_tgt - pR; rr = norm(v_out); u_r = v_out / max(rr, eps); % RIS -> Target

ci = max(0.0, panel.nR.' * u_in);
co = max(0.0, panel.nR.' * u_r);
Nf = numel(freqs);
S = size(phase_mat, 2);

if ci <= 0 || co <= 0
    res = struct('c', zeros(S, Nf), 'dc_dpsi1', zeros(S, Nf), 'dc_dpsi2', zeros(S, Nf), ...
        'dbr', dbr, 'rr', rr, 'ci', ci, 'co', co, 'u_in', u_in, 'u_r', u_r, 'panel', panel);
    return;
end

if cfg.wideband
    f_eval = freqs(:).';
else
    f_eval = repmat(cfg.fc, 1, Nf);
end

% Physical phase delay from BS->RIS->Target:
% Element offset o_m relative to RIS center shortens path to BS by o_m'*u_in
% and shortens path to Target by o_m'*u_r => total path change = -o_m'*(u_in + u_r).
% Therefore phase factor is exp(+j * 2*pi*f/c * o_m'*(u_in + u_r)).
% Note: matches channel_geometry.m where br = (pR - q)/dbr = -u_in => -(u_r - br) = -(u_r + u_in),
% wait: in channel_geometry.m: phase is exp(-j*2*pi/lam * o_m'*(u_r - br)) = exp(-j*2*pi/lam * o_m'*(u_r + u_in)).
% Sign convention (exp(-j*k*o_m'*(u_r+u_in))) is kept IDENTICAL to Stage-3 channel_geometry.m!
psi1 = panel.e1.' * (u_r + u_in);
psi2 = panel.e2.' * (u_r + u_in);

k_vec = 2 * pi * f_eval / cfg.c; % 1 x Nf
Mside = cfg.ris_side;
v = panel.v; % Mside x 1

% Separable 1D steering vectors: A1 (Mside x Nf), A2 (Mside x Nf)
A1 = exp(-1j * (v * (k_vec * psi1)));
A2 = exp(-1j * (v * (k_vec * psi2)));
dA1 = (-1j * (v * k_vec)) .* A1; % derivative wrt psi1
dA2 = (-1j * (v * k_vec)) .* A2; % derivative wrt psi2

% Reshape phase_mat (Mside^2 x S) -> (Mside, Mside, S) using ndgrid(v, v) order
% In ndgrid(v, v): dim 1 = e1 (psi1), dim 2 = e2 (psi2).
% For each config s: sum_{i,j} Theta(i,j,s) * A1(i,f) * A2(j,f) = sum_j (A1.' * Theta(:,:,s))_fj * A2(j,f)
c_raw = zeros(S, Nf);
dc1_raw = zeros(S, Nf);
dc2_raw = zeros(S, Nf);
for s = 1:S
    Th = reshape(phase_mat(:, s), Mside, Mside);
    T1 = Th.' * A1;    % Mside x Nf
    c_raw(s, :)   = sum(A2 .* T1, 1);
    dc1_raw(s, :) = sum(A2 .* (Th.' * dA1), 1);
    dc2_raw(s, :) = sum(dA2 .* T1, 1);
end

% Single-element physical aperture factor: (d^2 / lambda_n) * sqrt(ci * co) / (dbr * rr)
% Note: absolute single-hop field ratio vs 1 m reference is this factor directly.
scale_f = (cfg.d^2 .* f_eval / cfg.c) * sqrt(ci * co) / (dbr * rr); % 1 x Nf
res = struct();
res.c        = c_raw   .* scale_f;
res.dc_dpsi1 = dc1_raw .* scale_f;
res.dc_dpsi2 = dc2_raw .* scale_f;
res.scale_f  = scale_f;
res.dbr = dbr; res.rr = rr;
res.ci = ci;   res.co = co;
res.u_in = u_in; res.u_r = u_r;
res.psi1 = psi1; res.psi2 = psi2;
res.panel = panel;
end

function A = eval_wideband_array(u_local, offsets, freqs, cfg, sign_flag)
% EVAL_WIDEBAND_ARRAY  Wideband UPA steering matrix (M x Nf) for unit direction u_local (3x1).
% sign_flag = +1 for Tx (matches channel_geometry.m: exp(+j*2*pi/lam*pos*u))
% sign_flag = -1 for Rx (matches channel_geometry.m: exp(-j*2*pi/lam*pos*u))
Nf = numel(freqs);
if cfg.wideband
    k_vec = 2 * pi * (freqs(:).') / cfg.c;
else
    k_vec = repmat(2 * pi * cfg.fc / cfg.c, 1, Nf);
end
proj = offsets.' * u_local(:); % M x 1
A = exp(1j * sign_flag * (proj * k_vec));
end

function ph = quantize_phase(z_complex, bits)
% Quantize complex vector/matrix to unit-modulus 2^bits discrete phase levels.
L = 2^bits;
ang = angle(z_complex);
ph = exp(1j * (2 * pi / L) * round(ang * L / (2 * pi)));
end

function ph = steer_ris_phase(q, p_tgt, cfg)
% Coherent RIS phase steering vector (N_ris x 1) quantized to cfg.ris_bits at fc.
q = q(:); p_tgt = p_tgt(:); pR = cfg.ris_pos(:);
panel = ris_panel_offsets(cfg);
u_in = (q - pR) / max(norm(q - pR), eps);
u_r  = (p_tgt - pR) / max(norm(p_tgt - pR), eps);
k0 = 2 * pi * cfg.fc / cfg.c;
ideal = exp(+1j * k0 * (panel.offsets.' * (u_r + u_in))); % conjugates exp(-j*k0*o'*(u_r+u_in))
ph = quantize_phase(ideal, cfg.ris_bits);
end
