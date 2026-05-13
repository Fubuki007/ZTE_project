% =========================================================================
% task3_precoder_system_comparison.m
% -------------------------------------------------------------------------
% 把 3 种预编码 (zf / nullspace / lagrange) 放进完整 MIMO-OFDM ISAC 主流程,
% 在 3 种 SI 信道下扫描 beta_SI 强度, 看下游参数估计性能.
%
% 实验矩阵:
%   [E1] 大 κ 莱斯 (LoS 主导, κ_SI = 1e4)   → 预期 nullspace/lagrange 比 zf 强很多
%   [E2] 小 κ 莱斯 (κ_SI = 1)                → 预期抑制量适中 (~20 dB)
%   [E3] 纯高斯 (κ_SI → 0, 约 1e-6)          → 预期几乎压不住
%
% 每组实验扫描 si_scale_list × 3 种预编码, 记录:
%   - SI 泄漏功率 ||H_SI * W||^2 (理论验证)
%   - 下游距离/角度估计误差
%   - 失锁门限 ρ_th (|R_err|>5m 或 |θ_err|>2°)
%   - 通信约束偏差 ||H_c'*W - I||^2
%
% 耗时考量: 每次估计约 5-20s, 3×3×N_scale 次调用 → 预计数十分钟, 所以:
%   - 默认 si_scale_list 较稀疏
%   - params.K_stream = 1 (单流, 与主流程一致)
% =========================================================================
clear; close all; clc;
t_all = tic;
warning('off', 'all');
rng(0);

fprintf('==========================================================\n');
fprintf('  任务 3 + 4: 预编码 × SI 信道 系统级对比\n');
fprintf('==========================================================\n');

% ---- 1. 参数 (复用主流程参数) ----
params = build_default_params();

% 规模控制: 默认使用缩减规模 (便于快速迭代);
% 若需跑全尺寸, 把 FAST_MODE 改为 false.
%
% 注意: 不能直接改 N, 因为 params.B / params.N = Δf 决定了 Rmax,
% 缩 N 会让 Rmax 变小, 目标 R=600m 被折叠. 只缩 K (符号数) 最安全.
FAST_MODE = true;
if FAST_MODE
    params.K = 64;              % 缩减 OFDM 符号数 (L)
    params.joint_fft_3d.Nv = params.K;
    params.joint_4d.memory_cap_gb = 4;
end

Nt_total = params.Ntx * params.Nty;
Nr_total = params.Mx  * params.My;
fprintf('规模: Nt=%d, Nr=%d, Ns=%d, L=%d, 目标数=%d, FAST_MODE=%d\n', ...
    Nt_total, Nr_total, params.N, params.K, params.num_targets, FAST_MODE);
fprintf('Rmax=%.1fm, ΔR=%.3fm, 目标 R=[%s]m\n', ...
    params.meta.R_max, params.meta.range_resolution, ...
    num2str(params.R_true, '%.2f '));

% ---- 2. 实验矩阵定义 ----
channel_cases = struct('label', {}, 'kappa', {});
channel_cases(1) = struct('label', 'E1_LoS',      'kappa', 1e4);
channel_cases(2) = struct('label', 'E2_mixed',    'kappa', 1);
channel_cases(3) = struct('label', 'E3_Rayleigh', 'kappa', 1e-6);

precoders = {'zf', 'nullspace', 'lagrange'};

% SI 强度扫描 (相对 beta_q_max 的倍数)
si_scale_list = [0, 1, 10, 100, 1000, 10000];
beta_q_max = max(params.alpha);

% 失锁判据
thr_theta_deg = 2.0;
thr_R_m       = 5.0;

% ---- 3. 发射波形准备 (每个 (channel, precoder) 对独立生成 W, 因此在循环内做) ----
fprintf('\n--- 开始实验 ---\n');

results = struct();
results.channel_cases = channel_cases;
results.precoders     = precoders;
results.si_scale_list = si_scale_list;

n_ch   = numel(channel_cases);
n_prec = numel(precoders);
n_sc   = numel(si_scale_list);

% 存储: results.data(ch_i, prec_i, sc_i) = struct(...)
data = cell(n_ch, n_prec, n_sc);

for ch_i = 1:n_ch
    kap = channel_cases(ch_i).kappa;
    ch_label = channel_cases(ch_i).label;
    fprintf('\n=========== 信道 %s (κ=%g) ===========\n', ch_label, kap);

    % 针对该信道生成一个固定的 H_SI, 用于 W 设计 + 回波注入
    hsi_cfg = struct( ...
        'model',    'ura_rician', ...
        'Nt_total', Nt_total, ...
        'Nr_total', Nr_total, ...
        'kappa_SI', kap, ...
        'Ntx', params.Ntx, 'Nty', params.Nty, ...
        'Mx',  params.Mx,  'My',  params.My, ...
        'd_lambda', 0.5, ...
        'theta_tx_deg', params.theta_SI, 'phi_tx_deg', params.phi_SI, ...
        'theta_rx_deg', params.theta_SI, 'phi_rx_deg', params.phi_SI, ...
        'seed', 1234 + ch_i);
    H_SI = generate_HSI(hsi_cfg);

    % 归一化为 ||H_SI||_F = 1 级别方便 beta_SI 缩放解释
    H_SI = H_SI / norm(H_SI, 'fro') * sqrt(Nt_total * Nr_total);

    for prec_i = 1:n_prec
        pt = precoders{prec_i};
        fprintf('\n  预编码: %-10s\n', pt);

        % --- 生成发射波形 ---
        tx_cfg = params;
        tx_cfg.precoder_type = pt;
        tx_cfg.H_SI = H_SI;
        tx = generate_mimo_ofdm_waveform(tx_cfg);
        tx_signal = single(tx.X);

        % 记录 W 诊断: 取第一个子载波的 si_leak (所有子载波相同量级)
        si_leak  = tx.precoder_info.si_leak_avg;
        comm_err = tx.precoder_info.comm_err_avg;
        fprintf('    波形 si_leak=%.4g, comm_err=%.4g\n', si_leak, comm_err);

        % --- 对每个 SI 强度跑估计 ---
        for sc_i = 1:n_sc
            scale = si_scale_list(sc_i);
            beta_SI_val = beta_q_max * scale;

            p = params;
            if scale == 0
                p.enable_SI = false;
            else
                p.enable_SI  = true;
                p.beta_SI    = beta_SI_val;
                p.beta_SI_abs= beta_SI_val;
                % 关键: 注入的 SI 信道必须和 W 设计时用的同一个
                p.H_SI_matrix = H_SI;
            end

            t_est = tic;
            rx_cube = simulate_radar_channel_3d(tx_signal, p);

            % 估计器: 标量等效, 省内存
            tx_sum = squeeze(sum(sum(tx_signal, 1), 2));  % (Ns, L)
            [th, ph, R, v, ~] = joint_estimator_fast(rx_cube, tx_sum, p);
            rt = toc(t_est);

            cmp = evaluate_estimation(th, ph, R, v, p, false);

            clear rx_cube;

            data{ch_i, prec_i, sc_i} = struct( ...
                'channel',   ch_label, ...
                'kappa',     kap, ...
                'precoder',  pt, ...
                'scale',     scale, ...
                'beta_SI',   beta_SI_val, ...
                'si_leak',   si_leak, ...
                'comm_err',  comm_err, ...
                'compare',   cmp, ...
                'runtime',   rt);

            % 摘要打印
            if isfield(cmp, 'theta_err') && ~isempty(cmp.theta_err)
                et = mean(abs(cmp.theta_err));
                ep = mean(abs(cmp.phi_err));
                eR = mean(abs(cmp.R_err));
                ev = mean(abs(cmp.v_err));
                fprintf('    scale=%-6g : θ=%6.3f° φ=%6.3f° R=%6.2fm v=%5.2fm/s  (%.1fs)\n', ...
                    scale, et, ep, eR, ev, rt);
            else
                fprintf('    scale=%-6g : 估计失败  (%.1fs)\n', scale, rt);
            end
        end
    end
end

results.data = data;
results.total_runtime = toc(t_all);

% ---- 4. 汇总: 失锁门限 ----
fprintf('\n==========================================================\n');
fprintf('  汇总: 各组合的 SI 失锁门限 (首个使 θ 或 R 误差超阈值的 scale)\n');
fprintf('  判据: |θ_err|>%.1f° 或 |R_err|>%.1fm\n', thr_theta_deg, thr_R_m);
fprintf('==========================================================\n');
fprintf('%-12s | %-10s | %-12s | %-12s | %-10s\n', ...
    '信道', '预编码', '失锁 scale', 'ρ_th (dB)', 'si_leak');
fprintf('%s\n', repmat('-', 1, 70));

summary_tbl = cell(0);
for ch_i = 1:n_ch
    for prec_i = 1:n_prec
        first_fail = NaN;
        sl_report = NaN;
        for sc_i = 1:n_sc
            d = data{ch_i, prec_i, sc_i};
            sl_report = d.si_leak;
            if d.scale == 0, continue; end
            cmp = d.compare;
            if ~isfield(cmp, 'theta_err') || isempty(cmp.theta_err)
                first_fail = d.scale;
                break;
            end
            et = mean(abs(cmp.theta_err));
            eR = mean(abs(cmp.R_err));
            if et > thr_theta_deg || eR > thr_R_m
                first_fail = d.scale;
                break;
            end
        end
        rho_th_db = NaN;
        if ~isnan(first_fail) && first_fail > 0
            rho_th_db = 10 * log10(first_fail);
        end
        ch_label = channel_cases(ch_i).label;
        pt = precoders{prec_i};
        fprintf('%-12s | %-10s | %-12g | %-+12.1f | %-10.3g\n', ...
            ch_label, pt, first_fail, rho_th_db, sl_report);
        summary_tbl{end+1} = struct( ...
            'channel', ch_label, ...
            'precoder', pt, ...
            'first_fail_scale', first_fail, ...
            'rho_th_db', rho_th_db, ...
            'si_leak', sl_report);
    end
    fprintf('%s\n', repmat('-', 1, 70));
end

results.summary = summary_tbl;
results.threshold = struct('theta_deg', thr_theta_deg, 'R_m', thr_R_m);

save('task3_precoder_system_results.mat', '-struct', 'results', '-v7.3');
fprintf('\n结果保存到 task3_precoder_system_results.mat\n');
fprintf('总耗时: %.1f 分钟\n', results.total_runtime / 60);
