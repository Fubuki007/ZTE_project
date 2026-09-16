function [H_SI, info] = generate_HSI(cfg)
%GENERATE_HSI Generate a near-field URA Rician SI matrix (Nr x Nt).
%   cfg requires Ntx, Nty, Mx, My and the matching Nt_total/Nr_total.
%   kappa_SI is the linear LoS-to-NLoS power ratio. cfg.d_sep_wl and
%   cfg.d_lambda are panel separation and element spacing in wavelengths.
%   H_LoS uses pairwise panel distances; H_NLoS is a simplified virtual
%   multipath model. Both terms are normalized to ||H||_F^2 = Nt*Nr before
%   Rician weighting. This is a simulation model, not a calibrated RF SI
%   channel. cfg.seed resets the MATLAB random stream if provided.
%   theta/phi_SI are not parameters of this matrix near-field LoS model.

if nargin < 1 || isempty(cfg), cfg = struct(); end

cfg = local_default(cfg, 'model',     'ura_rician');
cfg = local_default(cfg, 'kappa_SI',  10);
cfg = local_default(cfg, 'Nt_total',  16);
cfg = local_default(cfg, 'Nr_total',  64);
cfg = local_default(cfg, 'seed',      []);
if ~strcmpi(cfg.model, 'ura_rician')
    error('This delivery supports only the ura_rician matrix SI model.');
end

if ~isempty(cfg.seed)
    rng(cfg.seed);
end

Nt = cfg.Nt_total;
Nr = cfg.Nr_total;

cfg = local_default(cfg, 'Ntx', 4);
cfg = local_default(cfg, 'Nty', 4);
cfg = local_default(cfg, 'Mx',  8);
cfg = local_default(cfg, 'My',  8);
cfg = local_default(cfg, 'd_lambda', 0.5);
cfg = local_default(cfg, 'd_sep_wl', 10);
cfg = local_default(cfg, 'Ncl', 4);
cfg = local_default(cfg, 'Nray', 10);
cfg = local_default(cfg, 'std_phi', 0.1);
cfg = local_default(cfg, 'std_theta', 0.1);
cfg = local_default(cfg, 'Pr', 1);

if cfg.Ntx * cfg.Nty ~= Nt || cfg.Mx * cfg.My ~= Nr
    error('SI matrix dimensions must match TX and RX array sizes.');
end
if cfg.kappa_SI < 0 || cfg.d_sep_wl <= 0 || cfg.d_lambda <= 0
    error('kappa_SI must be nonnegative; SI array spacings must be positive.');
end
H_LoS = local_los_ura(cfg);
H_NLoS = local_nlos_sayeed(Nt, Nr, cfg.Ncl, cfg.Nray, ...
    cfg.std_phi, cfg.std_theta, cfg.Pr);

% -------------------------- 公式 (13) 合成 -------------------------------
kap = cfg.kappa_SI;
H_SI = sqrt(kap / (kap + 1)) * H_LoS + sqrt(1 / (kap + 1)) * H_NLoS;

% -------------------------- info -----------------------------------------
info = struct( ...
    'model',    cfg.model, ...
    'kappa_SI', kap, ...
    'H_LoS',    H_LoS, ...
    'H_NLoS',   H_NLoS, ...
    'fro_LoS',  norm(H_LoS, 'fro'), ...
    'fro_NLoS', norm(H_NLoS, 'fro'), ...
    'fro_SI',   norm(H_SI,  'fro'));
end

% Pairwise near-field LoS for two parallel URA panels.
function Hlos = local_los_ura(cfg)
% 收发面板平行正对, 间距 d_sep_wl (单位: 波长)
% TX: Ntx × Nty, 阵元间距 d_lambda
% RX: Mx  × My,  阵元间距 d_lambda
% 每个 TX-RX 天线对的距离 R 独立计算, 相位 exp(-j2πR/λ), 幅度 1/R

d_wl  = cfg.d_lambda;                        % 阵元间距 (波长)
d_sep = cfg.d_sep_wl;

Ntx = cfg.Ntx;  Nty = cfg.Nty;
Mx  = cfg.Mx;   My  = cfg.My;
Nt  = cfg.Nt_total;
Nr  = cfg.Nr_total;

% TX 展平索引: kron(ay,ax) → 元素 (ntx,nty) → idx = nty*Ntx + ntx + 1
% 为计算距离, 先把每个元素的物理坐标算出来 (单位: 波长)
tx_x = (0:Ntx-1) * d_wl;   % (1 × Ntx)
tx_y = (0:Nty-1) * d_wl;   % (1 × Nty)
rx_x = (0:Mx-1)  * d_wl;   % (1 × Mx)
rx_y = (0:My-1)  * d_wl;   % (1 × My)

% 逐天线对计算距离矩阵 R (Nr × Nt)
% 展平顺序与 kron(ay_t,ax_t) 一致: y 方向外层, x 方向内层
Hlos = zeros(Nr, Nt);
for nty = 0:Nty-1
    for ntx = 0:Ntx-1
        tx_idx = nty * Ntx + ntx + 1;   % MATLAB 1-indexed
        for my = 0:My-1
            for mx = 0:Mx-1
                rx_idx = my * Mx + mx + 1;
                % 三维距离: Δx, Δy 在面板平面, d_sep 在垂直方向
                dx = rx_x(mx+1) - tx_x(ntx+1);
                dy = rx_y(my+1) - tx_y(nty+1);
                R  = sqrt(d_sep^2 + dx^2 + dy^2);      % 距离 (波长)
                Hlos(rx_idx, tx_idx) = exp(-1j * 2 * pi * R) / R;
            end
        end
    end
end

% 归一化 (保留相对幅度结构, 对齐当前规范: ||H_LoS||_F² = Nt·Nr)
T = trace(Hlos * Hlos');
Hlos = Hlos * sqrt(Nt * Nr / (T + eps));
end

% Simplified clustered virtual NLoS channel.
function H = local_nlos_sayeed(Nt, Nr, Ncl, Nray, std_phi, std_theta, Pr)
phi_cl    = sin(2*pi*rand(Ncl, 1));
theta_cl  = sin(2*pi*rand(Ncl, 1));
phi_mat   = repmat(phi_cl,   [1 Nray]) + std_phi   * randn(Ncl, Nray);
theta_mat = repmat(theta_cl, [1 Nray]) + std_theta * randn(Ncl, Nray);

At = exp(1j * pi * ((0:Nt-1).' * phi_mat(:).'  )) / sqrt(Nt);
Ar = exp(1j * pi * ((0:Nr-1).' * theta_mat(:).')) / sqrt(Nr);

alpha = (sqrt(Pr)/2) * (randn(Ncl*Nray, 1) + 1j*randn(Ncl*Nray, 1));
[~, I] = sort(abs(alpha), 'descend');
alpha  = alpha(I);

H = Ar(:, I) * diag(alpha) * At(:, I)';
H = H * sqrt(Nt * Nr / (norm(H, 'fro')^2 + eps));
end

% ========================================================================
% 工具函数
% ========================================================================
function s = local_default(s, field, value)
if ~isfield(s, field) || isempty(s.(field))
    s.(field) = value;
end
end
