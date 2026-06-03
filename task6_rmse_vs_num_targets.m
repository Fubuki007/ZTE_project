% =========================================================================
% task6_rmse_vs_num_targets.m
% -------------------------------------------------------------------------
% 扫描目标数 Q = 1~8，蒙特卡洛仿真，计算三种预编码方案的角度/距离/速度 RMSE
%
% 每个 Q 跑 N_mc 次随机目标布局，取平均 RMSE
% FAST_MODE 加速（L=64），无 SI（聚焦估计器本身的多目标能力）
% =========================================================================
clear; close all; clc;
rng(42);
t_all = tic;

% ---- 0. 参数 ----
params = build_default_params();

% 加速设置
FAST_MODE = true;
if FAST_MODE
    params.K = 64;
    params.joint_fft_3d.Nv = params.K;
    params.joint_4d.memory_cap_gb = 4;
end

% 关闭 SI，聚焦估计性能
params.enable_SI = false;

% 使用随机通信信道（确保 nullspace 正常）
params.comm_channel_type = 'random';
params.comm_channel_seed = 42;

Nt = params.Ntx * params.Nty;
Nr = params.Mx * params.My;
Ns = params.N;
L  = params.K;

fprintf('============================================================\n');
fprintf('  Task 6: RMSE vs Number of Targets\n');
fprintf('  Nt=%d, Nr=%d, Ns=%d, L=%d, FAST_MODE=%d\n', ...
    Nt, Nr, Ns, L, FAST_MODE);
fprintf('============================================================\n\n');

% ---- 1. 扫描设置 ----
Q_list = 1:8;               % 目标数
N_mc   = 8;                  % 每个 Q 的蒙特卡洛次数
precoder_types  = {'zf', 'nullspace', 'lagrange'};
precoder_names  = {'ZF', 'Nullspace', 'Lagrange'};
n_prec = 3;
n_Q    = numel(Q_list);

% 预分配
rmse_angle = zeros(n_prec, n_Q);    % 综合角度 RMSE (theta+phi 合并)
rmse_range = zeros(n_prec, n_Q);    % 距离 RMSE
rmse_vel   = zeros(n_prec, n_Q);    % 速度 RMSE

% ---- 2. 预先生成 SI 信道 (H_SI 固定，所有 MC 共用) ----
hsi_cfg = struct(...
    'model',     'ura_rician', ...
    'Nt_total',  Nt, ...
    'Nr_total',  Nr, ...
    'kappa_SI',  1e4, ...
    'Ntx', params.Ntx, 'Nty', params.Nty, ...
    'Mx',  params.Mx, 'My', params.My, ...
    'd_lambda', 0.5, ...
    'theta_tx_deg', params.theta_SI, 'phi_tx_deg', params.phi_SI, ...
    'theta_rx_deg', params.theta_SI, 'phi_rx_deg', params.phi_SI, ...
    'seed', 1234);
H_SI_fixed = generate_HSI(hsi_cfg);
H_SI_fixed = H_SI_fixed / norm(H_SI_fixed, 'fro') * sqrt(Nt * Nr);

% ---- 3. 进度条初始化 ----
n_total = n_Q * N_mc * n_prec;   % 总仿真步数
step = 0;
bar_width = 40;                   % 进度条宽度(字符)

fprintf('总仿真步数: %d (Q=%d × MC=%d × 预编码=%d)\n', n_total, n_Q, N_mc, n_prec);
fprintf('[%s]   0%%  ETA: --:--:--\n', repmat(' ', 1, bar_width));

% ---- 4. 主循环 ----
for qi = 1:n_Q
    Q = Q_list(qi);
    
    % 每个 MC trial 累积
    mc_angle = zeros(n_prec, N_mc);
    mc_range = zeros(n_prec, N_mc);
    mc_vel   = zeros(n_prec, N_mc);
    mc_fail  = zeros(n_prec, 1);
    
    for mc = 1:N_mc
        % --- 生成 Q 个随机目标 ---
        [th_true, ph_true, R_true, v_true, alpha_true] = ...
            generate_random_targets(Q, params);
        
        p_mc = params;
        p_mc.num_targets = Q;
        p_mc.theta_true  = th_true;
        p_mc.phi_true    = ph_true;
        p_mc.R_true      = R_true;
        p_mc.v_true      = v_true;
        p_mc.alpha       = alpha_true;
        
        for prec_i = 1:n_prec
            pt = precoder_types{prec_i};
            
            % --- 发射波形 ---
            tx_cfg = p_mc;
            tx_cfg.precoder_type = pt;
            tx_cfg.H_SI = H_SI_fixed;
            
            try
                tx = generate_mimo_ofdm_waveform(tx_cfg);
            catch
                mc_fail(prec_i) = mc_fail(prec_i) + 1;
                step = step + 1;
                print_progress(step, n_total, bar_width, t_all);
                continue;
            end
            
            % --- 雷达回波 + 估计 ---
            tx_signal = single(tx.X);
            rx_cube = simulate_radar_channel_3d(tx_signal, p_mc);
            tx_sum = squeeze(sum(sum(tx_signal, 1), 2));
            [th_est, ph_est, R_est, v_est, ~] = ...
                joint_estimator_fast(rx_cube, tx_sum, p_mc);
            clear rx_cube;
            
            % --- 评估 ---
            cmp = evaluate_estimation(th_est, ph_est, R_est, v_est, p_mc, false);
            
            if isempty(cmp.theta_err) || all(isnan(cmp.theta_err))
                mc_fail(prec_i) = mc_fail(prec_i) + 1;
                mc_angle(prec_i, mc) = NaN;
                mc_range(prec_i, mc) = NaN;
                mc_vel(prec_i, mc)   = NaN;
            else
                mc_angle(prec_i, mc) = sqrt(cmp.rmse_theta^2 + cmp.rmse_phi^2);
                mc_range(prec_i, mc) = cmp.rmse_R;
                mc_vel(prec_i, mc)   = cmp.rmse_v;
            end
            
            % --- 更新进度条 ---
            step = step + 1;
            print_progress(step, n_total, bar_width, t_all);
        end
    end
    
    % --- 汇总当前 Q ---
    for prec_i = 1:n_prec
        valid = ~isnan(mc_angle(prec_i, :));
        if any(valid)
            rmse_angle(qi, prec_i) = mean(mc_angle(prec_i, valid));
            rmse_range(qi, prec_i) = mean(mc_range(prec_i, valid));
            rmse_vel(qi, prec_i)   = mean(mc_vel(prec_i, valid));
        else
            rmse_angle(qi, prec_i) = NaN;
            rmse_range(qi, prec_i) = NaN;
            rmse_vel(qi, prec_i)   = NaN;
        end
    end
end

% 进度条换行
fprintf('\n');
for qi = 1:n_Q
    fprintf('Q=%d: ', Q_list(qi));
    for prec_i = 1:n_prec
        fprintf('%s θ=%.2f° R=%.2fm v=%.2fm/s | ', ...
            precoder_names{prec_i}, ...
            rmse_angle(qi, prec_i), rmse_range(qi, prec_i), rmse_vel(qi, prec_i));
    end
    fprintf('\n');
end

% ---- 5. 保存结果 ----
out_dir = fullfile(pwd, 'task6_results');
if ~exist(out_dir, 'dir'), mkdir(out_dir); end

save(fullfile(out_dir, 'task6_rmse_vs_Q.mat'), ...
    'Q_list', 'N_mc', 'rmse_angle', 'rmse_range', 'rmse_vel', ...
    'precoder_names', 'precoder_types', '-v7.3');

fprintf('\n============================================================\n');
fprintf('  结果保存: %s\\task6_rmse_vs_Q.mat\n', out_dir);
fprintf('  总耗时: %.1f 分钟\n', toc(t_all)/60);
fprintf('============================================================\n');

% =========================================================================
% ==== 局部函数 ============================================================
% =========================================================================

function print_progress(step, n_total, bar_width, t_all)
    % 单行动态刷新进度条
    pct = step / n_total;
    n_fill = round(pct * bar_width);
    bar_str = [repmat('=', 1, n_fill), repmat(' ', 1, bar_width - n_fill)];
    
    elapsed = toc(t_all);
    if step > 0 && pct > 0
        eta = elapsed / pct - elapsed;
        eta_str = sprintf('%02d:%02d:%02d', ...
            floor(eta/3600), floor(mod(eta,3600)/60), floor(mod(eta,60)));
    else
        eta_str = '--:--:--';
    end
    
    % \r 回到行首覆盖刷新
    fprintf('\r[%s] %5.1f%%  ETA: %s', bar_str, pct*100, eta_str);
end

function [th, ph, R, v, alpha] = generate_random_targets(Q, params)
    % 生成 Q 个随机目标，保证最小间隔（角度 > 波束宽度，距离 > 分辨率，速度 > 分辨率）
    
    % 参数空间
    th_range = [5, 60];       % 俯仰角范围 (度)
    ph_range = [0, 50];       % 方位角范围 (度)
    R_range  = [100, 800];    % 距离范围 (m)
    v_range  = [-20, 20];     % 速度范围 (m/s)
    
    % 最小间隔 (2× 理论分辨率，保证可分辨)
    d_th = params.lambda / (params.Mx * params.d) * 180/pi * 3;  % ~3×波束宽度
    d_ph = params.lambda / (params.My * params.d) * 180/pi * 3;
    d_R  = params.c / (2 * params.B) * 5;   % 5×距离分辨率
    d_v  = params.c / (2 * params.fc * params.K * params.Ts) * 3;
    
    d_th = max(d_th, 5);   % 至少 5°
    d_ph = max(d_ph, 5);
    d_R  = max(d_R, 5);    % 至少 5m
    d_v  = max(d_v, 2);    % 至少 2 m/s
    
    th = zeros(1, Q);
    ph = zeros(1, Q);
    R  = zeros(1, Q);
    v  = zeros(1, Q);
    
    max_attempts = 500;
    
    for q = 1:Q
        accepted = false;
        for attempt = 1:max_attempts
            th_try = th_range(1) + rand * diff(th_range);
            ph_try = ph_range(1) + rand * diff(ph_range);
            R_try  = R_range(1)  + rand * diff(R_range);
            v_try  = v_range(1)  + rand * diff(v_range);
            
            % 检查与已接受目标的间隔
            ok = true;
            for j = 1:(q-1)
                if abs(th_try - th(j)) < d_th || ...
                   abs(ph_try - ph(j)) < d_ph || ...
                   abs(R_try  - R(j))  < d_R  || ...
                   abs(v_try  - v(j))  < d_v
                    ok = false;
                    break;
                end
            end
            if ok
                accepted = true;
                break;
            end
        end
        if ~accepted
            % 放弃间隔约束，随机生成
            th_try = th_range(1) + rand * diff(th_range);
            ph_try = ph_range(1) + rand * diff(ph_range);
            R_try  = R_range(1)  + rand * diff(R_range);
            v_try  = v_range(1)  + rand * diff(v_range);
        end
        th(q) = th_try;
        ph(q) = ph_try;
        R(q)  = R_try;
        v(q)  = v_try;
    end
    
    % 复反射系数 (幅度在 0.5~1.0 之间随机)
    alpha = 0.5 + 0.5 * rand(1, Q);
end
