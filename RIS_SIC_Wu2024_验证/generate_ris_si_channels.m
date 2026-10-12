function ch = generate_ris_si_channels(params)
%GENERATE_RIS_SI_CHANNELS  按论文式(1)-(10)生成近场 SI 信道
%
% 输出 ch:
%   ch.freq       : Mx1 子载波频率
%   ch.lambda_m   : Mx1 子载波波长
%   ch.h_direct   : Mx1 直达 SI 信道 h_{m,1}
%   ch.h_ris      : N_ris x M RIS 级联 SI 信道 h_{m,R}
%                   满足 h_eff(phi) = h_direct(m) + h_ris(:,m)'*phi
%
% 约定:
%   物理级联信道 g_cas,n = g_tx,n * g_rx,n
%   为了让 MATLAB 的 Hermitian 内积与论文 h_R^H*phi 对齐，代码存
%   h_ris = conj(g_cas)。因此 h_ris(:,m)'*phi = g_cas.'*phi。

M = params.M;
N = params.N_ris;
sN = round(sqrt(N));
x_t = params.x_t;
y_t = params.y_t;
d   = params.d;

t_tx = [x_t;  y_t; d];
t_rx = [-x_t; y_t; d];

% 直达路径：论文式(10)说明用 p_r=(x_t,y_t,0) 和 d=2x_t
t_direct = [x_t; y_t; params.d_direct];
p_direct = [x_t; y_t; 0];

h_direct = zeros(M,1);
h_ris    = zeros(N,M);
cell_pos_center = zeros(3,N);

for m = 1:M
    lam = params.lambda_m(m);
    side = lam / 5;                 % 论文仿真: 单元边长 lambda_m/5
    Rcell = side^2;                 % 式(3)中的 R_m

    idx = (0:N-1).';
    xn = -(sN-1)*side/2 + side * mod(idx, sN);      % 式(1)
    yn =  (sN-1)*side/2 - side * floor(idx/sN);     % 式(2)
    P  = [xn.'; yn.'; zeros(1,N)];

    if m == 1
        cell_pos_center = P;
    end

    % TX -> RIS
    xi_tx  = nearfield_xi_cells(t_tx, P, Rcell);
    dist_tx = sqrt(sum((P - t_tx).^2, 1));
    g_tx = sqrt(xi_tx) .* exp(-1j * 2*pi * dist_tx / lam);

    % RIS -> RX (互易)
    xi_rx  = nearfield_xi_cells(t_rx, P, Rcell);
    dist_rx = sqrt(sum((P - t_rx).^2, 1));
    g_rx = sqrt(xi_rx) .* exp(-1j * 2*pi * dist_rx / lam);

    % 物理级联 SI 信道
    g_cas = g_tx .* g_rx * sqrt(params.eta);

    % 存成 h_ris，使 h_ris'*phi 与 h_R^H*phi 对齐
    h_ris(:,m) = conj(g_cas.');

    % 直达 SI
    xi_d = nearfield_xi_cells(t_direct, p_direct, Rcell);
    h_direct(m) = sqrt(xi_d) * exp(-1j * 2*pi * params.d_direct / lam);
end

ch = struct();
ch.freq = params.freq(:);
ch.lambda_m = params.lambda_m(:);
ch.h_direct = h_direct;
ch.h_ris = h_ris;
ch.cell_pos_center = cell_pos_center;
ch.g_tx = [];    % 如需调试可在此保存
ch.g_rx = [];
ch.model = 'nearfield_paper_eq3_10';
end
