function [phi, info] = optimize_ris_target_phase(model, params, tau, phi_init)
%OPTIMIZE_RIS_TARGET_PHASE  Coordinate ascent for RIS target enhancement
%
% Maximizes sum_{q,m} w_q |a_{q,m}+b_{q,m}^T phi|^2 under |phi_n|=1.
% tau=Inf gives continuous phase; finite tau gives the Wu et al. phase grid.

if nargin < 3 || isempty(tau), tau = Inf; end
if nargin < 4 || isempty(phi_init)
    phi_init = ones(model.N_ris, 1);
else
    phi_init = phi_init(:);
end
if numel(phi_init) ~= model.N_ris
    error('phi_init length must equal model.N_ris');
end

Ns = size(model.direct_beam, 2);
Q = size(model.direct_beam, 1);
weights_q = ones(Q, 1);
if isfield(params, 'ris') && isfield(params.ris, 'target_weights') && ...
        ~isempty(params.ris.target_weights)
    weights_q = params.ris.target_weights(:);
end
if numel(weights_q) ~= Q
    error('RIS target_weights must contain one weight per target');
end

a = reshape(model.direct_beam.', [], 1);       % m-major, then q
B = zeros(model.N_ris, Ns*Q);
weights = zeros(Ns*Q, 1);
for q = 1:Q
    cols = (q-1)*Ns + (1:Ns);
    B(:, cols) = squeeze(model.ris_beam(:, q, :));
    weights(cols) = weights_q(q);
end

max_sweeps = 20;
if isfield(params, 'ris') && isfield(params.ris, 'max_sweeps') && ...
        ~isempty(params.ris.max_sweeps)
    max_sweeps = params.ris.max_sweeps;
end
if isfinite(tau)
    tau = max(2, round(tau));
    grid = 2*pi*(0:tau-1)/tau;
    n_starts = 6;
    starts = cell(n_starts, 1);
    starts{1} = local_quantize(phi_init, grid);
    starts{2} = ones(model.N_ris, 1);
    starts{3} = local_quantize(exp(1j*2*pi*rand(model.N_ris,1)), grid);
    starts{4} = local_quantize(exp(1j*2*pi*rand(model.N_ris,1)), grid);
    starts{5} = local_quantize(exp(1j*2*pi*rand(model.N_ris,1)), grid);
    starts{6} = local_quantize(exp(1j*2*pi*rand(model.N_ris,1)), grid);
else
    n_starts = 2;
    starts = {exp(1j*angle(phi_init)), ones(model.N_ris,1)};
end

best_obj = -Inf;
best_phi = starts{1};
best_history = [];
for s = 1:n_starts
    [phi_s, obj_s, hist_s] = local_coordinate_ascent( ...
        starts{s}, B, a, weights, tau, max_sweeps);
    if obj_s > best_obj
        best_obj = obj_s;
        best_phi = phi_s;
        best_history = hist_s;
    end
end

phi = best_phi(:);
direct_power = real(sum(weights .* abs(a).^2));
info = struct();
info.objective = best_obj;
info.history = best_history(:);
info.sweeps = max(0, numel(best_history)-1);
info.tau = tau;
info.n_starts = n_starts;
info.direct_power = direct_power;
info.ris_power = best_obj;
info.gain_db = 10*log10(max(best_obj, eps) / max(direct_power, eps));
info.max_abs_phi = max(abs(phi));
info.a = a;
info.B = B;
end

function [phi, obj, history] = local_coordinate_ascent(phi, B, a, weights, tau, max_sweeps)
if isfinite(tau)
    grid = 2*pi*(0:tau-1)/tau;
else
    grid = [];
end
r = a + B.' * phi;
obj = real(sum(weights .* abs(r).^2));
history = obj;
N = numel(phi);
for sweep = 1:max_sweeps
    old_obj = obj;
    for n = 1:N
        b = B(n, :).';
        r0 = r - b * phi(n);
        c = sum(weights .* conj(r0) .* b);
        if abs(c) < 1e-15
            continue;
        end
        if isfinite(tau)
            scores = real(exp(1j*grid(:)) * c);
            [~, k] = max(scores);
            phi_new = exp(1j*grid(k));
        else
            phi_new = exp(-1j*angle(c));
        end
        if phi_new ~= phi(n)
            phi(n) = phi_new;
            r = r0 + b * phi(n);
        end
    end
    obj = real(sum(weights .* abs(r).^2));
    history(end+1) = obj; %#ok<AGROW>
    if abs(obj-old_obj) <= 1e-10*max(1, abs(old_obj))
        break;
    end
end
end

function phi_q = local_quantize(phi, grid)
ang = angle(phi(:));
D = abs(angle(exp(1j*(ang-grid))));
[~, idx] = min(D, [], 2);
phi_q = exp(1j*grid(idx)).';
end
