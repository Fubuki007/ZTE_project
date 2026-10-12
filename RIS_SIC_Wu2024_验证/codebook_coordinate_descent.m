function [phi_best, info] = codebook_coordinate_descent(h_direct, h_ris, tau, phi_init, params)
%CODEBOOK_COORDINATE_DESCENT  单元素相位码表 + 坐标下降
%
% 码表方案一:
%   每个 RIS 单元的候选相位构成一个小码表
%       C = {0, 2*pi/tau, ..., 2*pi*(tau-1)/tau}
%   固定其余单元，逐个单元遍历码表，选择使残余 SI 最小的相位。
%   反复扫描直到不再改善。
%
% 该方案需要 CSI（h_direct, h_ris），但复杂度远低于全局码表穷举。

if nargin < 4 || isempty(phi_init)
    N = size(h_ris,1);
    phi_init = ones(N,1);
end
if nargin < 5 || isempty(params)
    params = ris_sic_params();
end

N = size(h_ris,1);
phi = phase_quantize_npp(phi_init, tau);
grid = 2*pi * (0:tau-1) / tau;

Jfun = @(x) sum(params.weights .* abs(h_direct(:) + h_ris' * x).^2);
Jbest = Jfun(phi);
hist = Jbest;

max_sweeps = params.codebook.cd_sweeps;
for sweep = 1:max_sweeps
    improved = false;
    order = randperm(N);
    for n = order
        best_local = inf;
        best_phase = phi(n);
        for q = 1:tau
            trial = phi;
            trial(n) = exp(1j * grid(q));
            Jt = Jfun(trial);
            if Jt < best_local - 1e-14
                best_local = Jt;
                best_phase = trial(n);
            end
        end
        if best_local < Jbest - 1e-12
            phi(n) = best_phase;
            Jbest = best_local;
            improved = true;
        end
    end
    hist(end+1) = Jbest; %#ok<AGROW>
    if ~improved
        break;
    end
end

phi_best = phi;
info = struct();
info.J = Jbest;
info.f_history = hist;
info.sweeps = numel(hist)-1;
info.tau = tau;
end
