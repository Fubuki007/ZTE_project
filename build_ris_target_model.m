function model = build_ris_target_model(params, tx, phi)
%BUILD_RIS_TARGET_MODEL  Single-bounce RIS target path for the main ISAC model
%
% The original project models a target echo as beta_q*a_q^H*x.  This helper
% adds the physically separate Tx-RIS-target path used in the Wu et al.
% paper: one RIS reflection, near-field Tx-to-RIS propagation, and a
% far-field RIS-to-target propagation.  The receive-side target steering is
% unchanged, so the model is a drop-in extension of the existing estimator.

if nargin < 3 || isempty(phi)
    phi = zeros(params.ris.N_ris, 1);
end
if ~isfield(params, 'ris') || ~isfield(params.ris, 'enable') || ~params.ris.enable
    model = [];
    return;
end
if size(tx.W, 2) ~= 1
    error('The integrated RIS target model currently requires K_stream=1');
end

Ns = params.N;
Q = params.num_targets;
Nris = params.ris.N_ris;
Nt = params.Ntx * params.Nty;
if params.ris.Nx * params.ris.Ny ~= Nris
    error('RIS.Nx * RIS.Ny must equal RIS.N_ris');
end

% Centered Tx array. The phase convention is converted to the same
% conj(a_tx) convention used by simulate_radar_channel_3d.
tx_pos = local_ura_positions(params.Ntx, params.Nty, params.d, params.d, 0, 0, 0);

lambda_c = params.lambda;
z_ris = -params.ris.d_sep;
cell_side = lambda_c / 5;
ix = (0:params.ris.Nx-1).';
iy = (0:params.ris.Ny-1).';
xn = (ix - (params.ris.Nx-1)/2) * cell_side;
yn = ((params.ris.Ny-1)/2 - iy) * cell_side;
[xx, yy] = meshgrid(xn, yn);
ris_pos = [xx(:).'; yy(:).'; z_ris * ones(1, Nris)];

% Target coordinates. theta is measured from broadside, matching the
% steering-vector convention in the existing simulator.
target_pos = zeros(3, Q);
for q = 1:Q
    u = sind(params.theta_true(q)) * cosd(params.phi_true(q));
    v = sind(params.theta_true(q)) * sind(params.phi_true(q));
    w = sqrt(max(0, 1 - u^2 - v^2));
    target_pos(:, q) = params.R_true(q) * [u; v; w];
end

freq = params.fc - params.B/2 + (0:Ns-1).' * (params.B / Ns);
lambda_m = params.c ./ freq;

% Existing direct transmit steering and the exact coefficient after W.
kw = 2*pi*params.d/params.lambda;
direct_coeff = zeros(Nt, Q);
for q = 1:Q
    u = sind(params.theta_true(q)) * cosd(params.phi_true(q));
    v = sind(params.theta_true(q)) * sind(params.phi_true(q));
    ax = exp(-1j * kw * (0:params.Ntx-1).' * u);
    ay = exp(-1j * kw * (0:params.Nty-1).' * v);
    A_q = ax * ay.';
    direct_coeff(:, q) = A_q(:);
end

direct_beam = zeros(Q, Ns);
ris_beam = zeros(Nris, Q, Ns);

% Distances which do not depend on subcarrier.
r_tx_ris = zeros(Nt, Nris);
for i = 1:Nt
    dvec = ris_pos - tx_pos(:, i);
    r_tx_ris(i, :) = sqrt(sum(dvec.^2, 1));
end
r_ris_target = zeros(Nris, Q);
r_tx_target = zeros(Nt, Q);
for q = 1:Q
    dvec = target_pos(:, q) - ris_pos;
    r_ris_target(:, q) = sqrt(sum(dvec.^2, 1));
    dvec = target_pos(:, q) - tx_pos;
    r_tx_target(:, q) = sqrt(sum(dvec.^2, 1));
end

% Unit-cell aperture factor for a lambda/5 cell. eta is the reflection
% efficiency and the square root is used because this is an amplitude model.
elem_gain = sqrt(4*pi) / 5;
eta_amp = sqrt(max(params.ris.eta, 0));

for m = 1:Ns
    lam = lambda_m(m);
    Wm = tx.W(:, 1, m);
    for q = 1:Q
        direct_beam(q, m) = direct_coeff(:, q).' * Wm;
        % Relative path phase makes phi=0 exactly recover the old target
        % model. The amplitude is the Friis two-hop/direct-path ratio.
        for n = 1:Nris
            c_n = zeros(Nt, 1);
            for i = 1:Nt
                amp_ratio = eta_amp * elem_gain * (lam/(4*pi)) * ...
                    r_tx_target(i, q) / (r_tx_ris(i, n) * r_ris_target(n, q));
                rel_phase = exp(-1j * 2*pi * ...
                    (r_tx_ris(i, n) + r_ris_target(n, q) - r_tx_target(i, q)) / lam);
                c_n(i) = direct_coeff(i, q) * amp_ratio * rel_phase;
            end
            ris_beam(n, q, m) = c_n.' * Wm;
        end
    end
end

model = struct();
model.enabled = true;
model.direct_beam = direct_beam;
model.ris_beam = ris_beam;
model.phi = phi(:);
model.tx_pos = tx_pos;
model.ris_pos = ris_pos;
model.target_pos = target_pos;
model.lambda_m = lambda_m;
model.N_ris = Nris;
model.description = 'single-bounce Tx-RIS-target path, lambda/5 cells';
end

function P = local_ura_positions(Nx, Ny, dx, dy, xc, yc, zc)
P = zeros(3, Nx*Ny);
k = 0;
for iy = 1:Ny
    for ix = 1:Nx
        k = k + 1;
        P(:, k) = [xc + (ix-(Nx+1)/2)*dx; ...
                   yc + (iy-(Ny+1)/2)*dy; zc];
    end
end
end
