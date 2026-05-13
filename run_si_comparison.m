% =========================================================================
% run_si_comparison.m  SI 自干扰强度对比实验 (独立脚本, 内存优化版)
% -------------------------------------------------------------------------
% 对比无 SI 基线与不同 SI 强度 (10x ~ 10000x beta_q) 下的估计精度。
%
% 内存优化策略:
%   - tx_signal 使用 single 精度 (内存减半)
%   - 估计器只需要 tx_sum (Ns,L), 不保留完整 4D tx_signal
%   - simulate_radar_channel_3d 内部已分块处理
%   - 每轮循环后 clear rx_cube 释放内存
% =========================================================================
clear; close all; clc;
t_total = tic;
warning('off', 'all');

fprintf('=================================================\n');
fprintf('  SI 自干扰强度对比实验 (内存优化版)\n');
fprintf('=================================================\n');

% ---- 1. 参数装配 ----
params = build_default_params();

fprintf('参数: 阵列=%dx%d, 子载波=%d, 符号=%d, 目标数=%d, SNR=%ddB\n', ...
    params.Mx, params.My, params.N, params.K, params.num_targets, params.SNR);

% ---- 2. 生成发射波形 ----
fprintf('[进度] 生成发射波形...\n');
tx_cfg = params;
tx_cfg.N         = params.N;
tx_cfg.K         = params.K;
tx_cfg.mod_order = params.mod_order;
tx_cfg.Ntx       = params.Ntx;
tx_cfg.Nty       = params.Nty;
tx_cfg.K_stream  = params.K_stream;
tx = generate_mimo_ofdm_waveform(tx_cfg);
tx_signal = single(tx.X);     % (Ntx, Nty, Ns, L), single 精度
clear tx;

% 预计算估计器需要的等效标量信号 (Ns, L)
% joint_estimator_fast 在 MIMO 模式下只用 sum(sum(tx_signal,1),2)
tx_sum = squeeze(sum(sum(tx_signal, 1), 2));   % (Ns, L), single
tx_sum_for_est = tx_sum ./ max(abs(tx_sum), eps('single'));  % 归一化版本备用

fprintf('[进度] 发射波形生成完毕\n');
fprintf('  tx_signal: %.2f GB (single), tx_sum: %.2f MB\n', ...
    numel(tx_signal)*4/1e9, numel(tx_sum)*4/1e6);

% ---- 3. SI 实验参数 ----
theta_SI_val = 45.0;                    % SI 俯仰角 (度)
phi_SI_val   = 30.0;                    % SI 方位角 (度)
R_SI_val     = 10 * params.lambda;      % SI 距离 = 10λ
v_SI_val     = 0;                       % SI 速度 = 0 (静止)
beta_q_max   = max(params.alpha);       % 最强目标反射系数
si_scale_list = [10, 100, 1000, 10000]; % beta_SI / beta_q 的倍数

fprintf('SI 参数: θ_SI=%.1f°, φ_SI=%.1f°, R_SI=%.4fm (%.1fλ), v_SI=%.1fm/s\n', ...
    theta_SI_val, phi_SI_val, R_SI_val, R_SI_val/params.lambda, v_SI_val);
fprintf('SI 强度倍数: [%s] × beta_q (beta_q_max=%.4f)\n', ...
    strjoin(arrayfun(@(x) sprintf('%d', x), si_scale_list, 'UniformOutput', false), ', '), ...
    beta_q_max);

% 总实验数 (基线 + N 个 SI 强度)
n_total_exp = 1 + length(si_scale_list);
exp_counter = 0;

% ---- 4. 无 SI 基线 ----
exp_counter = exp_counter + 1;
fprintf('\n[%d/%d] --- 基线: 无 SI ---\n', exp_counter, n_total_exp);
params_no_si = params;
params_no_si.enable_SI = false;

fprintf('  生成回波...');
rx_cube = simulate_radar_channel_3d(tx_signal, params_no_si);
fprintf(' 完成\n');

% 估计器: 传入 (Ns,L) 的 tx_sum, 走标量分支, 节省内存
fprintf('  运行估计器...');
tic;
[theta_est_b, phi_est_b, R_est_b, v_est_b, info_b] = ...
    joint_estimator_fast(rx_cube, tx_sum, params_no_si);
base_runtime = toc;
clear rx_cube;  % 立即释放
fprintf(' 完成 (%.3f秒)\n', base_runtime);

base_compare = evaluate_estimation(theta_est_b, phi_est_b, R_est_b, v_est_b, params_no_si, true);

base_result = struct( ...
    'label', '无SI', 'beta_SI', 0, 'scale', 0, ...
    'theta_est', theta_est_b, 'phi_est', phi_est_b, ...
    'R_est', R_est_b, 'v_est', v_est_b, ...
    'info', info_b, 'compare', base_compare, 'runtime', base_runtime);
fprintf('[%d/%d] 基线完成\n', exp_counter, n_total_exp);

% ---- 5. 各 SI 强度实验 ----
si_results = cell(length(si_scale_list), 1);

for idx = 1:length(si_scale_list)
    exp_counter = exp_counter + 1;
    scale = si_scale_list(idx);
    beta_SI_val = beta_q_max * scale;
    
    fprintf('\n[%d/%d] --- SI 强度 = %d × beta_q (beta_SI=%.4f) ---\n', ...
        exp_counter, n_total_exp, scale, beta_SI_val);
    
    % 构造带 SI 的参数
    params_si = params;
    params_si.enable_SI   = true;
    params_si.beta_SI     = beta_SI_val;
    params_si.beta_SI_abs = beta_SI_val;
    params_si.theta_SI    = theta_SI_val;
    params_si.phi_SI      = phi_SI_val;
    params_si.R_SI        = R_SI_val;
    params_si.v_SI        = v_SI_val;
    
    % 生成带 SI 的回波
    fprintf('  生成回波...');
    rx_cube = simulate_radar_channel_3d(tx_signal, params_si);
    fprintf(' 完成\n');
    
    % 估计器: 传入 (Ns,L) 的 tx_sum
    fprintf('  运行估计器...');
    tic;
    [theta_est_si, phi_est_si, R_est_si, v_est_si, info_si] = ...
        joint_estimator_fast(rx_cube, tx_sum, params_si);
    si_runtime = toc;
    clear rx_cube;  % 立即释放
    fprintf(' 完成 (%.3f秒)\n', si_runtime);
    
    % 评估
    si_compare = evaluate_estimation(theta_est_si, phi_est_si, R_est_si, v_est_si, params_si, true);
    
    si_results{idx} = struct( ...
        'label', sprintf('SI=%dx', scale), ...
        'beta_SI', beta_SI_val, ...
        'scale', scale, ...
        'theta_est', theta_est_si, 'phi_est', phi_est_si, ...
        'R_est', R_est_si, 'v_est', v_est_si, ...
        'info', info_si, 'compare', si_compare, 'runtime', si_runtime);
    
    fprintf('[%d/%d] 完成\n', exp_counter, n_total_exp);
end

% ---- 6. 汇总对比表 ----
fprintf('\n=================================================\n');
fprintf('  汇总对比: 无SI vs 各SI强度\n');
fprintf('=================================================\n');
fprintf('%-12s | %-10s | %-10s | %-10s | %-10s | %-8s\n', ...
    '场景', 'θ误差(°)', 'φ误差(°)', 'R误差(m)', 'v误差(m/s)', '耗时(s)');
fprintf('%s\n', repmat('-', 1, 72));

% 基线
if isstruct(base_compare) && isfield(base_compare, 'theta_err')
    fprintf('%-12s | %-10.4f | %-10.4f | %-10.4f | %-10.4f | %-8.3f\n', ...
        '无SI', mean(abs(base_compare.theta_err)), mean(abs(base_compare.phi_err)), ...
        mean(abs(base_compare.R_err)), mean(abs(base_compare.v_err)), base_runtime);
end

% 各 SI 结果
for idx = 1:length(si_results)
    r = si_results{idx};
    if isstruct(r.compare) && isfield(r.compare, 'theta_err')
        fprintf('%-12s | %-10.4f | %-10.4f | %-10.4f | %-10.4f | %-8.3f\n', ...
            r.label, mean(abs(r.compare.theta_err)), mean(abs(r.compare.phi_err)), ...
            mean(abs(r.compare.R_err)), mean(abs(r.compare.v_err)), r.runtime);
    else
        fprintf('%-12s | 估计失败或无法匹配目标\n', r.label);
    end
end

% ---- 7. 保存结果 ----
out = struct();
out.base_result   = base_result;
out.si_results    = si_results;
out.si_params     = struct('theta_SI', theta_SI_val, 'phi_SI', phi_SI_val, ...
                           'R_SI', R_SI_val, 'v_SI', v_SI_val, ...
                           'si_scale_list', si_scale_list, ...
                           'beta_q_max', beta_q_max);
out.params        = params;
out.total_runtime = toc(t_total);
save('ZTE_SI_comparison_results.mat', '-struct', 'out', '-v7.3');

fprintf('\n=================================================\n');
fprintf('结果已保存到 ZTE_SI_comparison_results.mat\n');
fprintf('总运行时间: %.3f 秒\n', out.total_runtime);
fprintf('=================================================\n');
