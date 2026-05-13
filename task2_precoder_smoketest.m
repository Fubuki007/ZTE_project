% =========================================================================
% task2_precoder_smoketest.m
% -------------------------------------------------------------------------
% 冒烟测试: 验证 generate_mimo_ofdm_waveform 的 3 种 precoder_type 都能
% 正常跑通, 并输出预期量级的 si_leak / comm_err 汇总.
% =========================================================================
clear; close all; clc;
params = build_default_params();

% 降低规模以加快验证 (不改主流程)
params.N = 64;
params.K = 32;

Nt = params.Ntx * params.Nty;
Nr = params.Mx  * params.My;

% 构造系统级 URA 自干扰信道 (用 'ura_rician', 便于 simulate_radar_channel_3d
% 未来也能用同一 H_SI 注入空间回波, 保证 W 设计和回波注入方向一致)
hsi_cfg = struct( ...
    'model',    'ura_rician', ...
    'Nt_total', Nt, ...
    'Nr_total', Nr, ...
    'kappa_SI', 100, ...
    'Ntx', params.Ntx, 'Nty', params.Nty, ...
    'Mx',  params.Mx,  'My',  params.My, ...
    'd_lambda', 0.5, ...
    'theta_tx_deg', 45, 'phi_tx_deg', 30, ...
    'theta_rx_deg', 45, 'phi_rx_deg', 30, ...
    'seed', 42);
[H_SI, ~] = generate_HSI(hsi_cfg);

tx_cfg = params;
tx_cfg.H_SI = H_SI;

methods = {'zf', 'nullspace', 'lagrange'};
fprintf('=================================================\n');
fprintf('  任务 2 冒烟: 3 种预编码生成发射波形\n');
fprintf('  Nt=%d, Nr=%d, Ns=%d, L=%d, κ_SI=%g\n', Nt, Nr, params.N, params.K, hsi_cfg.kappa_SI);
fprintf('=================================================\n');
for k = 1:numel(methods)
    tx_cfg.precoder_type = methods{k};
    tx = generate_mimo_ofdm_waveform(tx_cfg);
    pi_ = tx.precoder_info;
    fprintf('  %-10s: si_leak(avg)=%-10.4g  comm_err(avg)=%-10.4g  X size=[%s]\n', ...
        methods{k}, pi_.si_leak_avg, pi_.comm_err_avg, ...
        num2str(size(tx.X)));
end
fprintf('\n冒烟通过.\n');
