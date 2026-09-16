% =========================================================================
% main.m  MIMO-OFDM ISAC 自干扰版交付入口
% 版本: v1.0 (2026-09-16)
% 环境: MATLAB R2024a
% 修改配置只需编辑下面的 config；接口和单位见 README.md。
% =========================================================================
clearvars; close all; clc;

project_dir = fileparts(mfilename('fullpath'));
if isempty(project_dir)
    project_dir = pwd;
end
addpath(project_dir);

fprintf('=================================================\n');
fprintf('  MIMO-OFDM ISAC 自干扰版 v1.0\n');
fprintf('=================================================\n');
t_total = tic;

% ---- 用户配置区 ---------------------------------------------------------
config = struct();
config.rng_seed             = 20260916;   % 固定种子，确保结果可复现
config.param_overrides      = struct();   % 阵列、目标和 OFDM 等独立参数
config.precoder_type        = 'nullspace'; % zf | nullspace | lagrange
config.enable_SI            = true;       % 是否注入自干扰
config.beta_SI              = 100;        % SI 幅度系数；相对幅度 100 倍约为 40 dB 功率比
config.enable_SIC           = false;      % 是否启用基于导频 LS 信道估计的数字 SIC
config.sic_use_true_channel = false;      % true 仅用于理想信道上界，不建议工程评估使用
config.SIC_pilot_len        = 64;         % SIC 导频长度，至少应不小于发射天线总数
config.kappa_SI             = 10;         % Rician K 因子
config.d_sep_wl             = 10;         % 收发面板间距（波长），矩阵 LoS 模型
config.d_lambda             = 0.5;        % 阵元间距（波长），矩阵 LoS 模型
config.SNR_dB               = 10;         % 目标回波信噪比
config.R_max_gate_m         = 600;        % 感知最大距离门限

rng(config.rng_seed, 'twister');

% ---- 1. 参数装配 ---------------------------------------------------------
params = build_default_params(config.param_overrides);
params.precoder_type = config.precoder_type;
params.enable_SI = config.enable_SI;
params.beta_SI = config.beta_SI;
params.enable_SIC = config.enable_SIC;
params.sic_use_true_channel = config.sic_use_true_channel;
params.SIC_pilot_len = config.SIC_pilot_len;
params.kappa_SI = config.kappa_SI;
params.SNR = config.SNR_dB;
params.fast_estimator.R_max_gate = config.R_max_gate_m;

fprintf('阵列: TX=%dx%d, RX=%dx%d, 子载波=%d, OFDM 符号=%d\n', ...
    params.Ntx, params.Nty, params.Mx, params.My, params.N, params.K);
fprintf('带宽=%.2f MHz, 距离分辨率=%.3f m, 最大不模糊距离=%.1f m\n', ...
    params.B/1e6, params.meta.range_resolution, params.meta.R_max);

% ---- 2. 生成 Rician 矩阵自干扰信道 -------------------------------------
Nt_total = params.Ntx * params.Nty;
Nr_total = params.Mx  * params.My;
hsi_cfg = struct( ...
    'model',        'ura_rician', ...
    'Nt_total',     Nt_total, ...
    'Nr_total',     Nr_total, ...
    'kappa_SI',     config.kappa_SI, ...
    'Ntx',          params.Ntx, ...
    'Nty',          params.Nty, ...
    'Mx',           params.Mx, ...
    'My',           params.My, ...
    'd_lambda',     config.d_lambda, ...
    'd_sep_wl',     config.d_sep_wl, ...
    'seed',         config.rng_seed);
[params.H_SI, hsi_info] = generate_HSI(hsi_cfg);
params.H_SI_matrix = params.H_SI;

% ---- 3. 生成 MIMO-OFDM 发射波形并执行 SI 抑制预编码 ---------------------
t_waveform = tic;
tx = generate_mimo_ofdm_waveform(params);
waveform_runtime = toc(t_waveform);
tx_signal = tx.X;
precoder_info = tx.precoder_info;
clear tx;

fprintf('预编码=%s, SI 泄漏=%.3g, 通信约束误差=%.3g\n', ...
    precoder_info.method, precoder_info.si_leak_avg, ...
    precoder_info.comm_err_avg);
fprintf('SI 注入=%d, beta_SI=%g, 数字 SIC=%d, H_SI=%dx%d\n', ...
    params.enable_SI, params.beta_SI, params.enable_SIC, ...
    size(params.H_SI_matrix, 1), size(params.H_SI_matrix, 2));

% ---- 4. 目标回波、自干扰与噪声仿真 -------------------------------------
t_sim = tic;
rx_cube = simulate_radar_channel_3d(tx_signal, params);
simulation_runtime = toc(t_sim);

% ---- 5. 角度-距离-速度联合估计 ------------------------------------------
t_est = tic;
[theta_est, phi_est, R_est, v_est, estimator_info] = ...
    joint_estimator_fast(rx_cube, tx_signal, params);
estimator_runtime = toc(t_est);
clear rx_cube tx_signal;

comparison = evaluate_estimation( ...
    theta_est, phi_est, R_est, v_est, params, true);

% ---- 6. 保存结构化结果 ---------------------------------------------------
result = struct();
result.version             = 'v1.0';
result.generated_at        = char(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss'));
result.config              = config;
result.params              = params;
result.hsi_info            = hsi_info;
result.precoder_info       = precoder_info;
result.theta_est_deg       = theta_est;
result.phi_est_deg         = phi_est;
result.range_est_m         = R_est;
result.velocity_est_mps    = v_est;
result.estimator_info      = estimator_info;
result.comparison          = comparison;
result.runtime_s           = struct( ...
    'waveform',   waveform_runtime, ...
    'simulation', simulation_runtime, ...
    'estimation', estimator_runtime, ...
    'total',      toc(t_total));

results_dir = fullfile(project_dir, 'results');
if ~exist(results_dir, 'dir')
    mkdir(results_dir);
end
result_file = fullfile(results_dir, 'ZTE_3D_SI_results.mat');
save(result_file, 'result', '-v7.3');

fprintf('\n结果已保存: %s\n', result_file);
fprintf('耗时: 波形 %.2f s | 回波/SI %.2f s | 估计 %.2f s | 总计 %.2f s\n', ...
    waveform_runtime, simulation_runtime, estimator_runtime, result.runtime_s.total);
fprintf('=================================================\n');
