% =========================================================================
% diag_tx_equalization.m
% 验证: 发射均衡信号对目标1/目标2的匹配程度
% 如果 tx_norm = sum(sum(X)) 和 a_tx^H(θ_2)*X 不相关 → 均衡失败
% =========================================================================
clear; close all; clc;

params = build_default_params();
params.num_targets = 2;
params.theta_true  = [25.83, 15.94];
params.phi_true    = [28.51, 13.58];
params.R_true      = [600.80, 600.20];
params.v_true      = [15.1, -5.4];
params.alpha       = [1.0, 0.8];
params.enable_SI   = false;
params.K = 256;
params.precoder_type = 'zf';
params.K_stream = 1;
params.user_theta_rad = deg2rad(params.theta_true(1));
params.user_phi_rad   = deg2rad(params.phi_true(1));
params.SNR = 200;

Ntx = params.Ntx; Nty = params.Nty; Nt = Ntx*Nty;
Ns = params.N; L = params.K;
d = params.d; lam = params.lambda;
kw = 2*pi*d/lam;

% 生成波形
tx = generate_mimo_ofdm_waveform(params);
X = tx.X;  % (Ntx, Nty, Ns, L)

% 两个目标的发射导向矢量
for q = 1:2
    u_q = sind(params.theta_true(q)) * cosd(params.phi_true(q));
    v_q = sind(params.theta_true(q)) * sind(params.phi_true(q));
    ax_q = exp(1j * kw * (0:Ntx-1).' * u_q);
    ay_q = exp(1j * kw * (0:Nty-1).' * v_q);
    a_tx_q = ax_q * ay_q.';  % (Ntx, Nty)
    
    % 方向相关的发射信号: a_tx^H * X
    tx_eff_dir = zeros(Ns, L);
    for ntx = 1:Ntx
        for nty = 1:Nty
            tx_eff_dir = tx_eff_dir + conj(a_tx_q(ntx, nty)) * squeeze(X(ntx, nty, :, :));
        end
    end
    
    % 标量发射信号: sum(sum(X))
    tx_eff_scalar = squeeze(sum(sum(X, 1), 2));
    
    % 相关性
    c = corrcoef(tx_eff_dir(:), tx_eff_scalar(:));
    corr_val = c(1,2);
    
    % 功率比
    pow_dir = mean(abs(tx_eff_dir(:)).^2);
    pow_scalar = mean(abs(tx_eff_scalar(:)).^2);
    
    fprintf('目标%d (θ=%.1f°, φ=%.1f°):\n', q, params.theta_true(q), params.phi_true(q));
    fprintf('  方向tx功率 / 标量tx功率 = %.2f (%.1f dB)\n', pow_dir/pow_scalar, 10*log10(pow_dir/pow_scalar));
    fprintf('  相关性 = %.4f\n', corr_val);
    fprintf('  如果相关性≪1, 标量均衡对目标%d失效\n\n', q);
end

% 比较: 目标1方向tx vs 目标2方向tx
u1 = sind(params.theta_true(1)) * cosd(params.phi_true(1));
v1 = sind(params.theta_true(1)) * sind(params.phi_true(1));
ax1 = exp(1j * kw * (0:Ntx-1).' * u1);
ay1 = exp(1j * kw * (0:Nty-1).' * v1);
a_tx_1 = ax1 * ay1.';
tx_eff_1 = zeros(Ns, L);
for ntx = 1:Ntx
    for nty = 1:Nty
        tx_eff_1 = tx_eff_1 + conj(a_tx_1(ntx, nty)) * squeeze(X(ntx, nty, :, :));
    end
end

u2 = sind(params.theta_true(2)) * cosd(params.phi_true(2));
v2 = sind(params.theta_true(2)) * sind(params.phi_true(2));
ax2 = exp(1j * kw * (0:Ntx-1).' * u2);
ay2 = exp(1j * kw * (0:Nty-1).' * v2);
a_tx_2 = ax2 * ay2.';
tx_eff_2 = zeros(Ns, L);
for ntx = 1:Ntx
    for nty = 1:Nty
        tx_eff_2 = tx_eff_2 + conj(a_tx_2(ntx, nty)) * squeeze(X(ntx, nty, :, :));
    end
end

c12 = corrcoef(tx_eff_1(:), tx_eff_2(:));
c1s = corrcoef(tx_eff_1(:), tx_eff_scalar(:));
c2s = corrcoef(tx_eff_2(:), tx_eff_scalar(:));
fprintf('tx_eff(θ1) vs tx_eff(θ2): 相关性=%.4f\n', c12(1,2));
fprintf('tx_eff(θ1) vs sum(sum(X)): 相关性=%.4f\n', c1s(1,2));
fprintf('tx_eff(θ2) vs sum(sum(X)): 相关性=%.4f\n', c2s(1,2));

fprintf('\n=== 诊断完成 ===\n');
