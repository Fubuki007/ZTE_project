function [phi_best, info] = codebook_random_search(h_direct, h_ris, tau, K, params)
%CODEBOOK_RANDOM_SEARCH  全局随机配置码表搜索
%
% 码表方案二:
%   从 tau^N_ris 个离散配置中随机抽取 K 个码字
%       Phi_k = exp(j*2*pi*idx_k/tau), idx_k in {0,...,tau-1}^N
%   然后选择使残余 SI 最小的码字。
%
% 实际硬件中如果 CSI 不可用，可以用已知发射导频，测量每个码字下的
% 接收 SI 功率，再选最小；本函数用等效信道直接计算该功率。

if nargin < 5 || isempty(params)
    params = ris_sic_params();
end

N = size(h_ris,1);

idx = randi([0, tau-1], N, K);
Phi = exp(1j * 2*pi * idx / tau);          % N x K

H = h_ris' * Phi;                           % M x K
J_all = sum(params.weights .* abs(h_direct(:) + H).^2, 1);

[Jbest, best_k] = min(J_all);
phi_best = Phi(:, best_k);

info = struct();
info.J = Jbest;
info.best_k = best_k;
info.J_all = J_all;
info.tau = tau;
info.K = K;
end
