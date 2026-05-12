% =========================================================================
% scan_si_effect.m  SI (自干扰) 强度扫描脚本
% -------------------------------------------------------------------------
% 从 main.m 里抽离出来的独立扫描脚本. 负责对若干 SI 幅度倍数做蒙特卡洛
% 仿真, 统计各倍数下的平均 RMSE. 不依赖 main.m 的任何中间变量, 可直接
% 单独运行:
%       >> scan_si_effect
%
% 配置全部集中在本脚本顶部, 基础参数从 build_default_params.m 取, 评估
% 由 evaluate_estimation.m 负责. SI 扫描倍数可通过修改 scale_list 调整.
%
% 依赖:
%   build_default_params.m   参数装配
%   generate_mimo_ofdm_waveform.m   发射信号 (MIMO ZF 预编码)
%   simulate_radar_channel_3d.m  回波生成 (内部根据 params.enable_SI 决定是否叠加 SI)
%   joint_angle_range_velocity_estimator.m  4D 联合估计
%   evaluate_estimation.m    估计结果 vs 真值
% =========================================================================
clear; close all; clc;
warning('off', 'all');
t_total = tic;

fprintf('=================================================\n');
fprintf('  SI 强度扫描 (自干扰对 ISAC 估计性能的影响)\n');
fprintf('=================================================\n');

% ---- 1. 参数装配 ----
params = build_default_params();

% ---- 2. 扫描配置 (可按需修改) ----
scale_list   = params.beta_SI_scale_list;     % SI 幅度倍数
scale_names  = params.beta_SI_scale_names;    % 对应文字标签
num_mc       = 10;                             % 每个倍数的蒙特卡洛次数
include_base = true;                           % 是否同时跑一次 "无 SI" 基线

fprintf('阵列=%dx%d, 等效子载波=%d, 符号=%d, 目标数=%d, SNR=%ddB\n', ...
    params.Mx, params.My, params.N, params.K, params.num_targets, params.SNR);
fprintf('扫描倍数 = [%s], 每点MC=%d\n', ...
    strjoin(scale_names, ', '), num_mc);

% ---- 3. 发射信号 (所有 run 共用同一张 tx_signal, 主要差异来自 SI 幅度) ----
%   严格对齐作者 main_snr_rmse_quicklook.m 的 MIMO 发射流程:
%     H → ZF 预编码 W → 16-QAM 符号 S → X = W·S  (论文公式 (2))
tx_cfg = params;
tx_cfg.N         = params.N;
tx_cfg.K         = params.K;
tx_cfg.mod_order = params.mod_order;
tx_cfg.Ntx       = params.Ntx;
tx_cfg.Nty       = params.Nty;
tx_cfg.K_stream  = params.K_stream;
tx       = generate_mimo_ofdm_waveform(tx_cfg);
tx_signal = tx.X;     % (Ntx, Nty, Ns, L)

% ---- 4. SI 相对强度标定: 用最强真实目标的幅度作为参考 ----
ref_target_amp = max(abs(params.alpha));
if isfield(params, 'use_physical_pathloss') && params.use_physical_pathloss
    ref_target_amp = ref_target_amp * (params.lambda / (4 * pi * max(params.R_true)))^2;
end
if ref_target_amp <= 0 || ~isfinite(ref_target_amp)
    ref_target_amp = 1;
end

% ---- 5. 可选: 无 SI 基线 ----
base_result = [];
if include_base
    params_no_si = params;
    params_no_si.enable_SI = false;

    rmse_theta_mc = nan(1, num_mc);
    rmse_phi_mc   = nan(1, num_mc);
    rmse_R_mc     = nan(1, num_mc);
    rmse_v_mc     = nan(1, num_mc);

    fprintf('\n-------------------- 无 SI 基线 --------------------\n');
    tic;
    for mc = 1:num_mc
        rx_cube = simulate_radar_channel_3d(tx_signal, params_no_si);
        [th, ph, r, v] = joint_estimator_fast(rx_cube, tx_signal, params_no_si);
        c = evaluate_estimation(th, ph, r, v, params_no_si, false);
        rmse_theta_mc(mc) = c.rmse_theta;
        rmse_phi_mc(mc)   = c.rmse_phi;
        rmse_R_mc(mc)     = c.rmse_R;
        rmse_v_mc(mc)     = c.rmse_v;
    end
    base_runtime = toc;

    base_result = struct( ...
        'label', '无SI', 'scale', 0, 'beta_SI', 0, 'beta_SI_abs', 0, ...
        'rmse_theta_mean', mean(rmse_theta_mc, 'omitnan'), ...
        'rmse_phi_mean',   mean(rmse_phi_mc,   'omitnan'), ...
        'rmse_R_mean',     mean(rmse_R_mc,     'omitnan'), ...
        'rmse_v_mean',     mean(rmse_v_mc,     'omitnan'), ...
        'runtime', base_runtime);

    fprintf('基线平均RMSE: 角度=%.3f°, 方位=%.3f°, 距离=%.3fm, 速度=%.3fm/s (用时 %.3fs)\n', ...
        base_result.rmse_theta_mean, base_result.rmse_phi_mean, ...
        base_result.rmse_R_mean,     base_result.rmse_v_mean, base_runtime);
end

% ---- 6. 逐倍数扫描 ----
results = repmat(struct( ...
    'scale', [], 'label', [], 'beta_SI', [], 'beta_SI_abs', [], ...
    'rmse_theta_mean', [], 'rmse_phi_mean', [], ...
    'rmse_R_mean', [], 'rmse_v_mean', [], 'runtime', []), ...
    numel(scale_list), 1);

for idx = 1:numel(scale_list)
    params_run = params;
    params_run.enable_SI   = true;
    params_run.beta_SI_abs = params.beta_SI * ref_target_amp * scale_list(idx);

    fprintf('\n==================== SI 扫描 %d/%d ====================\n', idx, numel(scale_list));
    fprintf('SI 强度 = %s, 相对比例 = %.3g, 绝对幅度 = %.3e\n', ...
        scale_names{idx}, params.beta_SI * scale_list(idx), params_run.beta_SI_abs);

    rmse_theta_mc = nan(1, num_mc);
    rmse_phi_mc   = nan(1, num_mc);
    rmse_R_mc     = nan(1, num_mc);
    rmse_v_mc     = nan(1, num_mc);

    tic;
    for mc = 1:num_mc
        rx_cube = simulate_radar_channel_3d(tx_signal, params_run);
        [th, ph, r, v] = joint_estimator_fast(rx_cube, tx_signal, params_run);
        c = evaluate_estimation(th, ph, r, v, params_run, false);
        rmse_theta_mc(mc) = c.rmse_theta;
        rmse_phi_mc(mc)   = c.rmse_phi;
        rmse_R_mc(mc)     = c.rmse_R;
        rmse_v_mc(mc)     = c.rmse_v;
    end
    cost_time = toc;

    results(idx).scale           = scale_list(idx);
    results(idx).label           = scale_names{idx};
    results(idx).beta_SI         = params.beta_SI * scale_list(idx);
    results(idx).beta_SI_abs     = params_run.beta_SI_abs;
    results(idx).rmse_theta_mean = mean(rmse_theta_mc, 'omitnan');
    results(idx).rmse_phi_mean   = mean(rmse_phi_mc,   'omitnan');
    results(idx).rmse_R_mean     = mean(rmse_R_mc,     'omitnan');
    results(idx).rmse_v_mean     = mean(rmse_v_mc,     'omitnan');
    results(idx).runtime         = cost_time;

    fprintf('扫描完成, 用时 %.3fs (%d次MC平均)\n', cost_time, num_mc);
    fprintf('平均RMSE: 角度=%.3f°, 方位=%.3f°, 距离=%.3fm, 速度=%.3fm/s\n', ...
        results(idx).rmse_theta_mean, results(idx).rmse_phi_mean, ...
        results(idx).rmse_R_mean,     results(idx).rmse_v_mean);
end

% ---- 7. 保存结果 ----
out = struct();
out.base_result   = base_result;
out.results       = results;
out.params        = params;
out.num_mc        = num_mc;
out.total_runtime = toc(t_total);
save('ZTE_SI_scan_results.mat', '-struct', 'out', '-v7.3');

fprintf('\n结果已保存到 ZTE_SI_scan_results.mat\n');
fprintf('=================================================\n');
fprintf('SI 扫描总运行时间: %.3f 秒\n', out.total_runtime);
fprintf('=================================================\n');
