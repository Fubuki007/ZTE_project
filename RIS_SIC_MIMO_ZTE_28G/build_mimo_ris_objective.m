function [h_direct_flat, h_ris_flat, info] = build_mimo_ris_objective(ch, W)
%BUILD_MIMO_RIS_OBJECTIVE  把 MIMO 残余 SI 展平成论文式的标量目标
%
% 目标:
%   min_phi sum_{m,j,k} | [H_direct(:,:,m)+G_rx(:,:,m)diag(phi)G_tx(:,:,m)] W(:,:,m) |^2
%
% 展平后:
%   J(phi) = sum_q | a_q + b_q.' * phi |^2
%   h_direct_flat = a
%   h_ris_flat    = conj(B), 使得 h_ris_flat.' * phi = B.' * phi
%
% 输入:
%   ch : generate_ris_mimo_channels 的输出
%   W  : Nt x K x M 预编码矩阵

Nr = ch.Nr;
Nt = ch.Nt;
N  = ch.N_ris;
M  = ch.M;
K  = size(W,2);

Q = M * Nr * K;
h_direct_flat = zeros(Q,1);
B_all = zeros(N,Q);

for m = 1:M
    Wm = W(:,:,m);                        % Nt x K
    A  = ch.H_direct(:,:,m) * Wm;         % Nr x K
    q0 = (m-1) * Nr * K;

    % 直达部分
    for k = 1:K
        qq = q0 + (k-1)*Nr + (1:Nr);
        h_direct_flat(qq) = A(:,k);
    end

    % RIS 部分: 每个 RIS 单元的贡献
    for n = 1:N
        contrib = ch.G_rx(:,n,m) * (ch.G_tx(n,:,m) * Wm);  % Nr x K
        for k = 1:K
            qq = q0 + (k-1)*Nr + (1:Nr);
            B_all(n,qq) = contrib(:,k).';
        end
    end
end

% h_ris_flat' * phi = B_all.' * phi
h_ris_flat = conj(B_all);

info = struct();
info.Q = Q;
info.M = M;
info.K = K;
info.Nr = Nr;
info.N_ris = N;
info.B_all = B_all;
info.a_all = h_direct_flat;
end
