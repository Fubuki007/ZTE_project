% =========================================================================
% diag_k256_quick.m
% 快速诊断: K=256 下速度/角度 RMSE 是否正常 (方案 A)
% 只跑 SNR=10dB 一个点, 3 预编码 × 5 MC
% =========================================================================
clear; close all; clc;
t_all = tic;
warning('off', 'all');

fprintf('============================================================\n');
fprintf('  诊断: K=256 单 SNR 点快速验证\n');
fprintf('============================================================\n\n');

% ---- 1. 基础参数 (复用 task5 配置) ----
override_cfg = struct(...
    'user_theta_rad', deg2rad([10, 20, 30, 40]'), ...
    'user_phi_rad',   deg2rad([15, 25, 35, 45]'), ...
    'K_stream', 4);
params = build_default_params(override_cfg);
params.K_stream = 4;

% --- ★ K=256 (解决速度/角度 RMSE 过高) ---
params.K = 256;
params.joint_fft_3d.Nv = 256;
params.joint_4d.memory_cap_gb = 4;
params.fast_estimator.n_pad_v = 256;  % 保持256 (512有副作用:检测阶段丢目标)

% --- ★ 开启 SI ---
params.enable_SI = true;
params.beta_SI   = 0.02;

% --- 构造 H_SI ---
Nt_total = params.Ntx * params.Nty;
Nr_total = params.Mx  * params.My;
hsi_cfg = struct( ...
    'model',    'ura_rician', ...
    'Nt_total', Nt_total, ...
    'Nr_total', Nr_total, ...
    'kappa_SI', 100, ...
    'Ntx', params.Ntx, 'Nty', params.Nty, ...
    'Mx',  params.Mx,  'My',  params.My, ...
    'd_lambda', 0.5, ...
    'theta_tx_deg', params.theta_SI, 'phi_tx_deg', params.phi_SI, ...
    'theta_rx_deg', params.theta_SI, 'phi_rx_deg', params.phi_SI, ...
    'seed', 2026);
H_SI = generate_HSI(hsi_cfg);
H_SI = H_SI / norm(H_SI, 'fro') * sqrt(Nt_total * Nr_total);

fprintf('规模: Nt=%d, Nr=%d, Ns=%d, K=%d, K_stream=%d\n', ...
    Nt_total, Nr_total, params.N, params.K, params.K_stream);
fprintf('目标: R=[%.1f %.1f]m, v=[%.1f %.1f]m/s\n', ...
    params.R_true, params.v_true);

% ---- 2. 实验: SNR=10dB 单点 ----
precoders = {'zf', 'nullspace', 'lagrange'};
snr_val   = 10;
n_mc      = 5;
n_prec    = numel(precoders);

fprintf('\nSNR = %d dB, MC = %d\n', snr_val, n_mc);
fprintf('预估耗时: ~%.0f 分钟\n\n', n_prec * n_mc * 28 / 60);

% ---- 3. 生成波形 ----
fprintf('--- 生成波形 ---\n');
tx_signals = cell(1, n_prec);
for prec_i = 1:n_prec
    pt = precoders{prec_i};
    tx_cfg = params;
    tx_cfg.precoder_type = pt;
    tx_cfg.H_SI = H_SI;
    tx = generate_mimo_ofdm_waveform(tx_cfg);
    tx_signals{prec_i} = tx;
    fprintf('  %-10s: si_leak=%.3g, comm_err=%.3g\n', pt, ...
        tx.precoder_info.si_leak_avg, tx.precoder_info.comm_err_avg);
end
fprintf('\n');

% ---- 4. 主循环 ----
rmse_R     = zeros(n_prec, n_mc);
rmse_theta = zeros(n_prec, n_mc);
rmse_v     = zeros(n_prec, n_mc);

for prec_i = 1:n_prec
    pt = precoders{prec_i};
    tx_signal = tx_signals{prec_i}.X;

    p = params;
    p.SNR = snr_val;
    p.enable_SI = true;
    p.H_SI_matrix = H_SI;
    p.beta_SI = 0.02;
    p.R_SI = 0;

    for mc_i = 1:n_mc
        if mc_i > 1
            rng('shuffle');
        end

        t_est = tic;
        rx_cube = simulate_radar_channel_3d(tx_signal, p);
        [th, ph, R, v, ~] = joint_estimator_fast(rx_cube, tx_signal, p);
        rt = toc(t_est);

        cmp = evaluate_estimation(th, ph, R, v, p, false);

        if isfield(cmp, 'rmse_R') && ~isnan(cmp.rmse_R)
            rmse_R(prec_i, mc_i)     = cmp.rmse_R;
            rmse_theta(prec_i, mc_i) = cmp.rmse_theta;
            rmse_v(prec_i, mc_i)     = cmp.rmse_v;
        else
            rmse_R(prec_i, mc_i)     = NaN;
            rmse_theta(prec_i, mc_i) = NaN;
            rmse_v(prec_i, mc_i)     = NaN;
        end

        clear rx_cube;
        fprintf('  %-10s mc=%d: R_rmse=%.3f, th_rmse=%.3f°, v_rmse=%.3f m/s  [%.1fs]\n', ...
            pt, mc_i, cmp.rmse_R, cmp.rmse_theta, cmp.rmse_v, rt);
    end
end

% ---- 5. 打印对比 ----
fprintf('\n=== 结果对比 (SNR=%ddB, K=%d) ===\n', snr_val, params.K);
fprintf('              距离RMSE   角度RMSE   速度RMSE\n');
fprintf('               (m)        (°)       (m/s)\n');
fprintf('            --------------------------------\n');
for prec_i = 1:n_prec
    r_med = median(rmse_R(prec_i, :), 'omitnan');
    t_med = median(rmse_theta(prec_i, :), 'omitnan');
    v_med = median(rmse_v(prec_i, :), 'omitnan');
    fprintf('  %-10s  %8.3f   %8.3f   %8.3f\n', precoders{prec_i}, r_med, t_med, v_med);
end

% 计算理论分辨率
delta_v = params.c / (2 * params.fc * params.Ts * params.K);
fprintf('\n理论速度分辨率 Δv=%.2f m/s\n', delta_v);
fprintf('总耗时: %.1f 分钟\n', toc(t_all)/60);
