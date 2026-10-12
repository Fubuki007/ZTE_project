function ch = generate_ris_mimo_channels(params)
%GENERATE_RIS_MIMO_CHANNELS  生成企业 28 GHz MIMO 配置下的近场 RIS SI 信道
%
% 输出:
%   ch.H_direct : Nr x Nt x M   直达 SI 信道
%   ch.G_tx     : N_ris x Nt x M  Tx -> RIS 信道
%   ch.G_rx     : Nr x N_ris x M  RIS -> Rx 信道
%   ch.tx_pos   : 3 x Nt
%   ch.rx_pos   : 3 x Nr
%   ch.ris_pos  : 3 x N_ris (中心频点)
%
% RIS 有效 SI 信道:
%   H_ris(phi,m) = G_rx(:,:,m) * diag(phi) * G_tx(:,:,m)
% 因此:
%   H_eff(phi,m) = H_direct(:,:,m) + H_ris(phi,m)

Nr = params.Mx * params.My;
Nt = params.Ntx * params.Nty;
N  = params.N_ris;
M  = params.M;
d  = params.d;

% ---------------- 阵列位置，展平顺序与主项目一致 ----------------
tx_pos = build_ura_positions(params.Ntx, params.Nty, d, d, ...
    params.x_c, 0, params.d_sep);          % 列主序
rx_pos = build_ura_positions(params.Mx, params.My, d, d, ...
    -params.x_c, 0, params.d_sep);         % 列主序

% ---------------- RIS 单元位置，以中心频点给出参考 ----------------
sN = params.Nx_ris;
side_c = params.lambda / 5;
idx = (0:N-1).';
xn_c = -(sN-1)*side_c/2 + side_c * mod(idx, sN);
yn_c =  (sN-1)*side_c/2 - side_c * floor(idx/sN);
ris_pos = [xn_c.'; yn_c.'; zeros(1,N)];

% ---------------- 直达路径距离矩阵 ----------------
Rmat = zeros(Nr, Nt);
for j = 1:Nr
    for i = 1:Nt
        Rmat(j,i) = norm(rx_pos(:,j) - tx_pos(:,i));
    end
end

H_direct = zeros(Nr, Nt, M);
G_tx = zeros(N, Nt, M);
G_rx = zeros(Nr, N, M);

for m = 1:M
    lam = params.lambda_m(m);
    Rcell = (lam/5)^2;

    % 直达 SI：用宽边式(3)近似，距离取真实收发阵元间距离
    H_direct(:,:,m) = sqrt(nearfield_xi_broadside(Rmat, Rcell)) .* ...
        exp(-1j * 2*pi * Rmat / lam);

    % RIS 单元位置随子载波波长缩放，与论文 R_m=(lambda_m/5)^2 一致
    side = lam / 5;
    xn = -(sN-1)*side/2 + side * mod(idx, sN);
    yn =  (sN-1)*side/2 - side * floor(idx/sN);
    P  = [xn.'; yn.'; zeros(1,N)];

    % Tx -> RIS
    for i = 1:Nt
        t = tx_pos(:,i);
        xi = nearfield_xi_cells(t, P, Rcell);
        dist = sqrt(sum((P - t).^2, 1));
        G_tx(:,i,m) = sqrt(xi(:)) .* exp(-1j * 2*pi * dist(:) / lam);
    end

    % RIS -> Rx
    for j = 1:Nr
        t = rx_pos(:,j);
        xi = nearfield_xi_cells(t, P, Rcell);
        dist = sqrt(sum((P - t).^2, 1));
        G_rx(j,:,m) = sqrt(xi(:).') .* exp(-1j * 2*pi * dist(:).' / lam);
    end
end

% 反射效率: H_ris = G_rx * diag(phi) * G_tx
G_tx = G_tx * sqrt(params.eta);

ch = struct();
ch.H_direct = H_direct;
ch.G_tx = G_tx;
ch.G_rx = G_rx;
ch.tx_pos = tx_pos;
ch.rx_pos = rx_pos;
ch.ris_pos = ris_pos;
ch.Rmat = Rmat;
ch.Nr = Nr;
ch.Nt = Nt;
ch.N_ris = N;
ch.M = M;
end

% ========================================================================
function P = build_ura_positions(Nx, Ny, dx, dy, xc, yc, zc)
% 列主序展平: index = ix + (iy-1)*Nx
P = zeros(3, Nx*Ny);
idx = 0;
for iy = 1:Ny
    for ix = 1:Nx
        idx = idx + 1;
        P(:,idx) = [xc + (ix - (Nx+1)/2)*dx; ...
                    yc + (iy - (Ny+1)/2)*dy; ...
                    zc];
    end
end
end
