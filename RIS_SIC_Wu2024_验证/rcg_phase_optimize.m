function [phi, info] = rcg_phase_optimize(h_direct, h_ris, weights, params, phi_init)
%RCG_PHASE_OPTIMIZE  连续相位 RIS 的黎曼共轭梯度优化
%
% 目标:
%   min_phi  sum_m weights(m) * |h_direct(m) + h_ris(:,m)'*phi|^2
%   s.t.    |phi_n| = 1, n = 1,...,N_ris
%
% 可选 phi_init: 外部给定初值（例如码表坐标下降的结果）。

if nargin < 3 || isempty(weights)
    weights = ones(size(h_direct));
end
if nargin < 4 || isempty(params)
    params = ris_sic_params();
end
if nargin < 5
    phi_init = [];
end

h_direct = h_direct(:);
weights  = weights(:);
N = size(h_ris,1);
M = numel(h_direct);

% J(phi)=const + c^H*phi + phi^H*c + phi^H*A*phi
A = (h_ris .* weights.') * h_ris';
c = h_ris * (weights .* h_direct);
const = sum(weights .* abs(h_direct).^2);

Jfun = @(phi) real(const + c'*phi + phi'*c + phi'*A*phi);
Gfun = @(phi) 2 * (A*phi + c);

g_phys = conj(h_ris);

opts = params.rcg;
n_restarts = 16;
if isfield(opts,'n_restarts') && ~isempty(opts.n_restarts)
    n_restarts = opts.n_restarts;
end

best_phi = [];
best_J = inf;
best_hist = [];
best_restart = 0;

for r = 1:n_restarts
    if r == 1 && ~isempty(phi_init)
        phi0 = phi_init(:);
    elseif r == 1
        % 对齐初始化：让每个 RIS 单元的反射贡献在中心子载波上
        % 尽量与直达径反相。
        m0 = max(1, round(M/2));
        target = -h_direct(m0);
        phi0 = exp(1j * (angle(target) - angle(g_phys(:,m0))));
    elseif r == 2
        phi0 = ones(N,1);
    else
        phi0 = exp(1j * 2*pi * rand(N,1));
    end

    [phi_r, J_r, hist_r] = local_rcg(phi0, Jfun, Gfun, opts);

    if J_r < best_J
        best_J = J_r;
        best_phi = phi_r;
        best_hist = hist_r;
        best_restart = r;
    end
end

phi = best_phi;

info = struct();
info.A = A;
info.c = c;
info.const = const;
info.J = best_J;
info.f_history = best_hist;
info.num_iter = numel(best_hist);
info.best_restart = best_restart;
info.converged = false;
if ~isempty(best_hist)
    if numel(best_hist) > 1
        info.converged = abs(best_hist(end)-best_hist(end-1)) < opts.tol;
    else
        info.converged = true;
    end
end

end

% ========================================================================
% 局部函数
% ========================================================================
function [phi, J, hist] = local_rcg(phi0, Jfun, Gfun, opts)
phi = retract(phi0);
J = Jfun(phi);
hist = J;

g_e = Gfun(phi);
g_r = proj_tangent(g_e, phi);
gamma = -g_r;

for k = 1:opts.max_iter
    if norm(g_r)^2 <= opts.tol
        break;
    end

    delta = opts.step0;
    accepted = false;
    while ~accepted
        phi_try = retract(phi + delta * gamma);
        J_try = Jfun(phi_try);
        if J_try <= J - opts.alpha * delta * (norm(g_r)^2)
            accepted = true;
        else
            delta = delta * opts.beta;
            if delta < 1e-14
                accepted = true;
            end
        end
    end

    phi_old = phi;
    g_r_old = g_r;
    gamma_old = gamma;

    phi = retract(phi_old + delta * gamma_old);
    J = Jfun(phi);
    hist(end+1) = J; %#ok<AGROW>

    g_e = Gfun(phi);
    g_r = proj_tangent(g_e, phi);

    gamma_old_t = transport_tangent(gamma_old, phi);
    g_r_old_t   = transport_tangent(g_r_old, phi);

    denom = max(real(g_r_old' * g_r_old), eps);
    beta = max(0, real(g_r' * (g_r - g_r_old_t)) / denom);

    gamma = -g_r + beta * gamma_old_t;
end

end

function y = retract(x)
nx = abs(x);
y = x ./ max(nx, eps);
end

function p = proj_tangent(g, phi)
p = g - real(g .* conj(phi)) .* phi;
end

function v = transport_tangent(v_old, phi_new)
v = v_old - real(v_old .* conj(phi_new)) .* phi_new;
end
