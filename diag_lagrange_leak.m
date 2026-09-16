% =========================================================================
% diag_lagrange_leak.m
%   诊断：Lagrange 预编码为何在 beta_SI=1 时就把雷达感知打崩
%   用真实代码路径生成波形（zf / nullspace / lagrange），计算：
%     1. 目标方向照射功率  |a_tx^H x|^2（雷达回波强度）
%     2. SI 注入功率       ||H_SI x||^2（自干扰强度）
%     3. 有效 SINR（噪声随回波功率自动缩放，同 simulate_radar_channel_3d）
%   物理配置与 task_si_strength_lagrange_sic_fullsize_mc10.m 完全一致，
%   仅把 N、L 调小加速。
% =========================================================================
function diag_lagrange_leak()
clear; close all; clc; warning('off','all');

baseParams = build_default_params();
baseParams.theta_true = [24.63, 15.94];
baseParams.phi_true   = [30.99, 13.58];
baseParams.R_true     = [200.6, 210.4];
baseParams.v_true     = [15.1, -5.4];
baseParams.alpha      = [1.0, 0.8];
baseParams.enable_SI  = true;
baseParams.beta_SI    = 100;
baseParams.enable_SIC = false;
baseParams.SIC_pilot_len = 128;
baseParams.SNR        = 0;
baseParams.K          = 32;
baseParams.K_stream   = 2;
baseParams.N          = 512;
baseParams.B          = 512 * 120e3;
baseParams.user_theta_rad = deg2rad(baseParams.theta_true(:));
baseParams.user_phi_rad   = deg2rad(baseParams.phi_true(:));
baseParams.Mx = 8;
baseParams.My = 8;
baseParams.joint_fft_3d.Na_x = 8;
baseParams.joint_fft_3d.Na_y = 8;

Nt_total = baseParams.Ntx * baseParams.Nty;
Nr_total = baseParams.Mx * baseParams.My;

% ---- H_SI 与服务器脚本完全一致（seed 20260731）----
rng(20260731);
hsi_cfg = struct( ...
    'model','ura_rician', 'Nt_total',Nt_total, 'Nr_total',Nr_total, ...
    'kappa_SI',10, 'Ntx',baseParams.Ntx, 'Nty',baseParams.Nty, ...
    'Mx',8, 'My',8, 'd_lambda',0.5, ...
    'theta_tx_deg',baseParams.theta_SI, 'phi_tx_deg',baseParams.phi_SI, ...
    'theta_rx_deg',baseParams.theta_SI, 'phi_rx_deg',baseParams.phi_SI, ...
    'seed', 20260731);
H_SI = generate_HSI(hsi_cfg);

% ---- R_raw 特征谱与正则化系数 ----
R_raw = H_SI' * H_SI;
ev = sort(eig(R_raw), 'descend');
lambda_lg = 1e-3 * trace(R_raw) / Nt_total;
fprintf('\n[1] H_SI: %dx%d, ||H_SI||_F^2 = %.4g\n', size(H_SI,1), size(H_SI,2), norm(H_SI,'fro')^2);
fprintf('    R_raw 特征值 max=%.4g min=%.4g, lambda_lg=%.4g\n', ev(1), ev(end), lambda_lg);
fprintf('    最大4: %.3g %.3g %.3g %.3g | 最小4: %.3g %.3g %.3g %.3g\n', ...
    ev(1), ev(2), ev(3), ev(4), ev(end-3), ev(end-2), ev(end-1), ev(end));

% ---- 目标方向发射导向矢量（展平顺序：x 最快）----
kw = 2*pi*baseParams.d/baseParams.lambda;
u1 = sind(baseParams.theta_true(1)) * cosd(baseParams.phi_true(1));
v1 = sind(baseParams.theta_true(1)) * sind(baseParams.phi_true(1));
a_tx_1 = kron(exp(1j*kw*(0:baseParams.Nty-1).'*v1), exp(1j*kw*(0:baseParams.Ntx-1).'*u1));
u2 = sind(baseParams.theta_true(2)) * cosd(baseParams.phi_true(2));
v2 = sind(baseParams.theta_true(2)) * sind(baseParams.phi_true(2));
a_tx_2 = kron(exp(1j*kw*(0:baseParams.Nty-1).'*v2), exp(1j*kw*(0:baseParams.Ntx-1).'*u2));
A_tx = [a_tx_1, a_tx_2];   % 16x2

methods = {'zf', 'nullspace', 'lagrange'};
labels  = {'ZF', 'Null-space', 'Lagrange'};

fprintf('\n[2] 各预编码波形统计（Ns=%d, L=%d）\n', baseParams.N, baseParams.K);
fprintf('%-12s %12s %12s %12s %12s %12s\n', 'method', 'echo_pow', 'si_pow', 'si/echo', 'g_min/max', 'si_min/max');
for mi = 1:numel(methods)
    p = baseParams;
    p.precoder_type = methods{mi};
    p.H_SI = H_SI;
    p.H_SI_matrix = H_SI;
    rng(20260801);
    tx = generate_mimo_ofdm_waveform(p);
    X = tx.X;   % (Ntx, Nty, Ns, L)
    clear tx;
    Ns = size(X,3); Lx = size(X,4);

    % 逐子载波统计（先对 L 取平均）
    g1 = zeros(Ns,1); g2 = zeros(Ns,1); sip = zeros(Ns,1);
    for i = 1:Ns
        x_i = reshape(X(:,:,i,:), Nt_total, Lx);   % (16, L)
        g1(i) = mean(abs(a_tx_1' * x_i).^2);
        g2(i) = mean(abs(a_tx_2' * x_i).^2);
        sip(i) = mean(sum(abs(H_SI * x_i).^2, 1));
    end
    echo_pow = mean(g1 + g2);
    si_pow   = mean(sip);
    fprintf('%-12s %12.4g %12.4g %12.4g %12.3g %12.3g\n', labels{mi}, ...
        echo_pow, si_pow, si_pow/echo_pow, min(g1+g2)/max(g1+g2), min(sip)/max(sip));

    % SINR vs beta（噪声 = echo/SNR，同模拟器）
    SNR_lin = 10^(p.SNR/10);
    noise_pow = echo_pow / SNR_lin;
    fprintf('             beta=   1    10    100   1000  10000 -> SINR(dB): ');
    for beta = [1 10 100 1000 10000]
        sinr = echo_pow / (beta^2 * si_pow + noise_pow);
        fprintf('%5.1f ', 10*log10(max(sinr, 1e-30)));
    end
    fprintf('\n');
    clear X;
end

% ---- 小规模端到端复核：beta=1 与 beta=100, MC=1 ----
fprintf('\n[3] 端到端复核（N=%d, L=%d, MC=1）：\n', baseParams.N, baseParams.K);
p0 = baseParams;
p0.fast_estimator.n_samp_l = min(32, max(8, floor(p0.K/2)));
p0.fast_estimator.R_max_gate = 600;
check_methods = {'zf', 'lagrange', 'lagrange'};
check_sic     = [false, false, true];
check_labels  = {'ZF', 'Lagrange', 'Lagrange+SIC'};
for beta = [1, 100]
    for mi = 1:numel(check_methods)
        p = p0;
        p.precoder_type = check_methods{mi};
        p.H_SI = H_SI; p.H_SI_matrix = H_SI;
        p.beta_SI = beta;
        p.enable_SIC = check_sic(mi);
        rng(20260801 + mi + 100*beta);
        tx = generate_mimo_ofdm_waveform(p);
        X_tx = tx.X;
        rx_cube = simulate_radar_channel_3d(X_tx, p);
        [th, ph, R, v, ~] = joint_estimator_fast(rx_cube, X_tx, p);
        cmp = evaluate_estimation(th, ph, R, v, p, false);
        fprintf('  beta=%-5d %-14s R=%.4f m, th=%.4f deg, v=%.4f m/s\n', ...
            beta, check_labels{mi}, cmp.rmse_R, cmp.rmse_theta, cmp.rmse_v);
        clear tx X_tx rx_cube;
    end
end

fprintf('\nDone.\n');
end
