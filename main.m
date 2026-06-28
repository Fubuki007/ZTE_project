% =========================================================================
% main.m  MIMO-OFDM ISAC 三维联合估计主流程 (基线)
% -------------------------------------------------------------------------
% SI 强度扫描已经拆出到独立脚本:  scan_si_effect.m
% 公共参数装配: build_default_params.m
% 公共评估函数: evaluate_estimation.m
% =========================================================================
clear; close all; clc;
t_total = tic;
warning('off', 'all');
fprintf('=================================================\n');
fprintf('  MIMO-OFDM ISAC 三维联合估计主流程\n');
fprintf('=================================================\n');

% ---- 1. 参数装配 ----
params = build_default_params();

fprintf('参数: 阵列=%dx%d, 单载波子载波=%d, 聚合后等效子载波=%d, 符号=%d, 目标数=%d\n', ...
    params.Mx, params.My, params.meta.N_per_cc, params.N, params.K, params.num_targets);
fprintf('距离分辨率=%.3fm, 最大不模糊距离=%.1fm\n', ...
    params.meta.range_resolution, params.meta.R_max);
fprintf('载波频率=%.2fGHz, 子载波间隔=%.3fkHz, OFDM符号周期=%.3fus\n', ...
    params.fc/1e9, params.meta.delta_f/1e3, params.Ts*1e6);
fprintf('3GPP单载波带宽=%.2fMHz, 聚合载波数=%d, 等效总带宽=%.2fMHz\n', ...
    params.meta.B_per_cc/1e6, params.meta.n_cc, params.B/1e6);
fprintf('验收指标: 目标分辨率=%.3fm, 实际分辨率=%.3fm, 距离覆盖需求=%.1fm, 实际Rmax=%.1fm\n', ...
    params.meta.target_range_resolution, params.meta.range_resolution, ...
    params.meta.required_Rmax, params.meta.R_max);

% ---- 2. 生成发射波形 (严格对齐作者 main_snr_rmse_quicklook.m 第 42-61 行) ----
%   信道 H → ZF 预编码 W → 16-QAM 通信符号 S → 发射信号 X = W·S
%   详见 generate_mimo_ofdm_waveform.m
%
% 预编码切换: params.precoder_type ∈ {'zf', 'nullspace', 'lagrange'}
%   'zf' (默认)  —— 作者原始实现, 不抑制自干扰
%   'nullspace' —— 公式 (17)
%   'lagrange'  —— 公式 (16)
% 非 'zf' 模式需要设置 params.H_SI (Nr × Nt).
if ~isfield(params, 'precoder_type') || isempty(params.precoder_type)
    params.precoder_type = 'nullspace';
end
if ~isfield(params, 'H_SI') || isempty(params.H_SI)
    % 自动构造一个与 params.theta_SI/phi_SI 匹配的 Rician H_SI
    % (ZF 模式下也构造, 用于计算 si_leak 诊断指标)
    Nt_total = params.Ntx * params.Nty;
    Nr_total = params.Mx  * params.My;
    hsi_cfg = struct( ...
        'model',    'ura_rician', ...
        'Nt_total', Nt_total, ...
        'Nr_total', Nr_total, ...
        'kappa_SI', 10, ...
        'Ntx', params.Ntx, 'Nty', params.Nty, ...
        'Mx',  params.Mx,  'My',  params.My, ...
        'd_lambda', 0.5, ...
        'theta_tx_deg', params.theta_SI, 'phi_tx_deg', params.phi_SI, ...
        'theta_rx_deg', params.theta_SI, 'phi_rx_deg', params.phi_SI);
    params.H_SI = generate_HSI(hsi_cfg);
end

tx_cfg = params;
tx_cfg.N         = params.N;
tx_cfg.K         = params.K;
tx_cfg.mod_order = params.mod_order;
tx_cfg.Ntx       = params.Ntx;
tx_cfg.Nty       = params.Nty;
tx_cfg.K_stream  = params.K_stream;
tx       = generate_mimo_ofdm_waveform(tx_cfg);
tx_signal = tx.X;     % (Ntx, Nty, Ns, L)
fprintf('预编码: %s, si_leak=%.3g, comm_err=%.3g\n', ...
    tx.precoder_info.method, tx.precoder_info.si_leak_avg, tx.precoder_info.comm_err_avg);

% ---- 3. 无 SI 基线回波 + 估计 ----
params_no_si = params;
params_no_si.enable_SI = false;

rx_cube = simulate_radar_channel_3d(tx_signal, params_no_si);

% --- 快速估计器 (目标 <1s 刷新率) ---
tic;
[theta_est, phi_est, R_est, v_est, info] = ...
    joint_estimator_fast(rx_cube, tx_signal, params_no_si);
base_runtime = toc;

% 与真实值对比 (evaluate_estimation 只做打印, 不耗时)
base_compare = evaluate_estimation(theta_est, phi_est, R_est, v_est, params_no_si, true);

base_result = struct( ...
    'label', '无SI', 'beta_SI', 0, 'beta_SI_abs', 0, ...
    'theta_est', theta_est, 'phi_est', phi_est, ...
    'R_est', R_est, 'v_est', v_est, ...
    'info', info, 'compare', base_compare, 'runtime', base_runtime);

% ---- 4. 保存基线结果 ----
out = struct();
out.base_result   = base_result;
out.params        = params;
out.total_runtime = toc(t_total);
save('ZTE_3D_baseline_results.mat', '-struct', 'out', '-v7.3');

fprintf('\n基线结果已保存到 ZTE_3D_baseline_results.mat\n');
fprintf('=================================================\n');
fprintf('快速估计器运行时间: %.3f 秒\n', base_runtime);
if base_runtime < 1.0
    fprintf('✓ 满足 <1s 实时刷新率要求!\n');
else
    fprintf('✗ 未满足 1s 要求\n');
end
fprintf('主流程总运行时间: %.3f 秒\n', out.total_runtime);
fprintf('=================================================\n');
fprintf('如需做 SI 强度扫描对比, 请单独运行:  run_si_comparison\n');
