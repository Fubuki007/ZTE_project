function [phi, info] = solve_ideal_amplitude_admm(a, B, params)
%SOLVE_IDEAL_AMPLITUDE_ADMM  求解论文 F1 理想幅相 QCQP
%
%   min_phi  || a + B.' * phi ||^2
%   s.t.     |phi_n| <= 1
%
% 这里用 ADMM 求解这个凸问题。返回的 phi 是复幅度，允许 |phi|<=1。

if nargin < 3 || isempty(params)
    params = struct();
end
rho = 1.0;
if isfield(params,'rho') && ~isempty(params.rho)
    rho = params.rho;
end
max_iter = 2000;
tol = 1e-9;
if isfield(params,'max_iter'), max_iter=params.max_iter; end
if isfield(params,'tol'), tol=params.tol; end

N = size(B,1);
C = B.';                         % Q x N
CtC = C' * C;                    % N x N
Cta = C' * a;                    % N x 1
factor = 2*CtC + rho*eye(N);     % N x N
phi = zeros(N,1);
z = zeros(N,1);
u = zeros(N,1);
J_hist = zeros(max_iter,1);

for it = 1:max_iter
    rhs = -2*Cta + rho*(z - u);
    phi = factor \ rhs;

    v = phi + u;
    z = v .* min(1, 1./max(abs(v),eps));
    u = u + phi - z;

    r = a + C*phi;
    J = mean(abs(r).^2);
    J_hist(it) = J;
    if it > 2 && abs(J_hist(it)-J_hist(it-1)) < tol*max(1,J_hist(it-1))
        J_hist = J_hist(1:it);
        break;
    end
end

info = struct();
info.J = J_hist(end);
info.f_history = J_hist;
info.max_abs_phi = max(abs(phi));
info.num_iter = numel(J_hist);
end
