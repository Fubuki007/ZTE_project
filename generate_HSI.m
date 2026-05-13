function [H_SI, info] = generate_HSI(cfg)
% =========================================================================
% GENERATE_HSI  生成自干扰信道 H_SI (Nr_total × Nt_total)
% -------------------------------------------------------------------------
% 严格按《毫米波通感实时感知与预警算法方案》公式 (13) 的莱斯模型:
%   H_SI = sqrt(κ/(κ+1)) * H_LoS + sqrt(1/(κ+1)) * H_NLoS
%
% 提供两种 LoS 生成方式, 便于和师兄 bf.m 结论对齐以及系统级注入:
%
%   cfg.model = 'ula_simple'  —— 师兄 bf.m 风格的简化 ULA 外积 (便于复现
%       "20 dB / 100 dB" 的参考结果):
%       H_LoS = ULA(Nr, theta_rx_deg) * ULA(Nt, theta_tx_deg)'
%       H_NLoS = 1/sqrt(2)*(randn(Nr,Nt)+1j*randn(Nr,Nt))    (瑞利)
%
%   cfg.model = 'ura_rician'  —— 系统级 URA 版:
%       H_LoS 用收发 URA 的二维导向矢量外积
%         a_rx(θ_rx, φ_rx) * a_tx(θ_tx, φ_tx)'
%       H_NLoS 用 Sayeed 虚信道 (多簇多径)
%
% 归一化:
%   ||H_LoS||_F^2  = Nt_total · Nr_total
%   ||H_NLoS||_F^2 = Nt_total · Nr_total
%   然后按公式 (13) 加权合成, 不再二次归一化, 保持 Rician κ 的物理含义.
%
% 输入 cfg 必需字段:
%   Nt_total, Nr_total  —— 发射/接收总天线数 (展平后)
%   kappa_SI            —— Rician K 因子 (线性), >=0. 很大 → 近 LoS;
%                           0 → 纯瑞利.
%   model               —— 'ula_simple' | 'ura_rician'
%
% 输入 cfg 可选字段:
%   seed                —— 随机种子; 为空则不重置随机流
%
%   model='ula_simple' 专用:
%     theta_tx_deg  (默认  65°)   发射 ULA 的 LoS 方向
%     theta_rx_deg  (默认 -65°)   接收 ULA 的 LoS 方向
%
%   model='ura_rician' 专用:
%     Ntx, Nty, Mx, My           —— URA 维度
%     d_lambda       (默认 0.5)  —— 阵元间距 / 波长
%     theta_tx_deg, phi_tx_deg   —— 发射阵 LoS (默认 45°, 30°)
%     theta_rx_deg, phi_rx_deg   —— 接收阵 LoS (默认 45°, 30°)
%     Ncl, Nray, std_phi, std_theta, Pr  —— NLoS 簇参数
%
% 输出:
%   H_SI  (Nr_total × Nt_total) 复矩阵
%   info  struct: 包含 H_LoS, H_NLoS, kappa_SI, model 等诊断信息
% =========================================================================

if nargin < 1 || isempty(cfg), cfg = struct(); end

cfg = local_default(cfg, 'model',     'ura_rician');
cfg = local_default(cfg, 'kappa_SI',  10);
cfg = local_default(cfg, 'Nt_total',  16);
cfg = local_default(cfg, 'Nr_total',  64);
cfg = local_default(cfg, 'seed',      []);

if ~isempty(cfg.seed)
    rng(cfg.seed);
end

Nt = cfg.Nt_total;
Nr = cfg.Nr_total;

% -------------------------- LoS + NLoS 生成 ------------------------------
switch lower(cfg.model)
    case 'ula_simple'
        cfg = local_default(cfg, 'theta_tx_deg',  65);
        cfg = local_default(cfg, 'theta_rx_deg', -65);
        H_LoS  = local_los_ula(Nt, Nr, cfg.theta_tx_deg, cfg.theta_rx_deg);
        H_NLoS = local_nlos_rayleigh(Nt, Nr);

    case 'ura_rician'
        cfg = local_default(cfg, 'Ntx', 4);
        cfg = local_default(cfg, 'Nty', 4);
        cfg = local_default(cfg, 'Mx',  8);
        cfg = local_default(cfg, 'My',  8);
        cfg = local_default(cfg, 'd_lambda',    0.5);
        cfg = local_default(cfg, 'theta_tx_deg', 45);
        cfg = local_default(cfg, 'phi_tx_deg',   30);
        cfg = local_default(cfg, 'theta_rx_deg', 45);
        cfg = local_default(cfg, 'phi_rx_deg',   30);
        cfg = local_default(cfg, 'Ncl',    4);
        cfg = local_default(cfg, 'Nray',   10);
        cfg = local_default(cfg, 'std_phi',   0.1);
        cfg = local_default(cfg, 'std_theta', 0.1);
        cfg = local_default(cfg, 'Pr',    1);

        if cfg.Ntx * cfg.Nty ~= Nt
            error('URA 发射: Ntx*Nty=%d, 但 Nt_total=%d', cfg.Ntx*cfg.Nty, Nt);
        end
        if cfg.Mx * cfg.My ~= Nr
            error('URA 接收: Mx*My=%d, 但 Nr_total=%d', cfg.Mx*cfg.My, Nr);
        end

        H_LoS = local_los_ura(cfg);
        H_NLoS = local_nlos_sayeed(Nt, Nr, cfg.Ncl, cfg.Nray, ...
            cfg.std_phi, cfg.std_theta, cfg.Pr);

    otherwise
        error('未知 model: %s (可选 ula_simple | ura_rician)', cfg.model);
end

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

% ========================================================================
% 内部: 师兄 bf.m 风格 ULA LoS
% ========================================================================
function Hlos = local_los_ula(Nt, Nr, theta_tx_deg, theta_rx_deg)
% H_LoS = a_rx(theta_rx_deg) * a_tx(theta_tx_deg)'
% ULA 导向矢量 a(M, θ) = 1/sqrt(M) * exp(j·π·sin(θ)·(0:M-1)')
a_tx = exp(1j * pi * sind(theta_tx_deg) * (0:Nt-1).') / sqrt(Nt);
a_rx = exp(1j * pi * sind(theta_rx_deg) * (0:Nr-1).') / sqrt(Nr);
Hlos = a_rx * a_tx';
Hlos = Hlos * sqrt(Nt * Nr / (norm(Hlos, 'fro')^2 + eps));
end

% ========================================================================
% 内部: URA LoS (二维导向矢量外积)
% ========================================================================
function Hlos = local_los_ura(cfg)
kw  = 2 * pi * cfg.d_lambda;  % d/λ 为单位, 相位常数
% 发射 URA
u_t = sind(cfg.theta_tx_deg) * cosd(cfg.phi_tx_deg);
v_t = sind(cfg.theta_tx_deg) * sind(cfg.phi_tx_deg);
ax_t = exp(1j * kw * (0:cfg.Ntx-1).' * u_t) / sqrt(cfg.Ntx);
ay_t = exp(1j * kw * (0:cfg.Nty-1).' * v_t) / sqrt(cfg.Nty);
a_tx = kron(ay_t, ax_t);       % (Nt_total × 1), x 先 y 后 与 permute 约定一致
% 接收 URA
u_r = sind(cfg.theta_rx_deg) * cosd(cfg.phi_rx_deg);
v_r = sind(cfg.theta_rx_deg) * sind(cfg.phi_rx_deg);
ax_r = exp(1j * kw * (0:cfg.Mx-1).' * u_r) / sqrt(cfg.Mx);
ay_r = exp(1j * kw * (0:cfg.My-1).' * v_r) / sqrt(cfg.My);
a_rx = kron(ay_r, ax_r);       % (Nr_total × 1)

Hlos = a_rx * a_tx';
Hlos = Hlos * sqrt(cfg.Nt_total * cfg.Nr_total / (norm(Hlos, 'fro')^2 + eps));
end

% ========================================================================
% 内部: 瑞利 NLoS (bf.m 风格)
% ========================================================================
function Hnlos = local_nlos_rayleigh(Nt, Nr)
Hnlos = 1/sqrt(2) * (randn(Nr, Nt) + 1j * randn(Nr, Nt));
Hnlos = Hnlos * sqrt(Nt * Nr / (norm(Hnlos, 'fro')^2 + eps));
end

% ========================================================================
% 内部: Sayeed 虚信道 NLoS
% ========================================================================
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
