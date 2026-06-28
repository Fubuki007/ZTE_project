% =========================================================================
% task5_rmse_vs_snr_si.m
% -------------------------------------------------------------------------
% RMSE vs SNR 对比: ZF / Lagrange / Nullspace 三种预编码方案
% ★ 开启自干扰 (SI)，体现 nullspace/lagrange 对 SI 的抑制优势
%
% 与 task5_rmse_vs_snr.m 的区别:
%   - enable_SI = true (核心改动)
%   - SNR 范围 0:5:20 dB (工程合理范围)
%   - 蒙特卡洛 10 次/点
%   - H_SI 在预处理阶段固定 (与预编码器同一 H_SI)
%   - ★ SNR 基于目标回波功率定义 (不含 SI, 2026-06-26 修正)
% =========================================================================
clear; close all; clc;
t_all = tic;
warning('off', 'all');

fprintf('============================================================\n');
fprintf('  Task 5 (SI-ON): RMSE vs SNR — ZF / Lagrange / Nullspace\n');
fprintf('  ★ 自干扰已开启 ★\n');
fprintf('============================================================\n\n');

% ---- 1. 基础参数 ----
override_cfg = struct(...
    'user_theta_rad', deg2rad([10, 20, 30, 40]'), ...
    'user_phi_rad',   deg2rad([15, 25, 35, 45]'), ...
    'K_stream', 4);
params = build_default_params(override_cfg);
params.K_stream = 4;

% --- 全尺寸模式 (3GPP 5G NR FR2 标准: L=256) ---
% K=256 保证速度分辨率 Δv=c/(2·K·Ts·fc)≈2.34 m/s
% (K=64 时 Δv≈9.37 m/s, 两目标仅隔 2.2 bin, 无法准确估计)
params.K = 256;
params.joint_fft_3d.Nv = 256;
params.joint_4d.memory_cap_gb = 4;

% --- ★ 加速优化 (K=256 数据量大, 折中精度换速度) ---
% n_pad_v=256 (不做多普勒补零, 省 ~50% FFT 时间)
% MC=5 (原 10, 够看趋势)
params.fast_estimator.n_pad_v = 256;

% --- ★ 开启 SI ★ ---
params.enable_SI = false;
params.beta_SI   = 0.02;       % ★ SI 残差 = 2% 目标 (硬件模拟域抑制后)

% --- 构造 H_SI (固定 SI 信道，保证对比公平) ---
Nt_total = params.Ntx * params.Nty;
Nr_total = params.Mx  * params.My;
hsi_cfg = struct( ...
    'model',    'ura_rician', ...
    'Nt_total', Nt_total, ...
    'Nr_total', Nr_total, ...
    'kappa_SI', 100, ...          % Rician K 因子 (LoS 分量强度)
    'Ntx', params.Ntx, 'Nty', params.Nty, ...
    'Mx',  params.Mx,  'My',  params.My, ...
    'd_lambda', 0.5, ...
    'theta_tx_deg', params.theta_SI, 'phi_tx_deg', params.phi_SI, ...
    'theta_rx_deg', params.theta_SI, 'phi_rx_deg', params.phi_SI, ...
    'seed', 2026);
H_SI = generate_HSI(hsi_cfg);
H_SI = H_SI / norm(H_SI, 'fro') * sqrt(Nt_total * Nr_total);

fprintf('规模: Nt=%d, Nr=%d, Ns=%d, L=%d, K_stream=%d\n', ...
    Nt_total, Nr_total, params.N, params.K, params.K_stream);
fprintf('SI: kappa=%.0f, enable_SI=%d\n', hsi_cfg.kappa_SI, params.enable_SI);
fprintf('用户角度 (°): [%s], Rmax=%.1fm, ΔR=%.3fm\n', ...
    num2str(rad2deg(params.user_theta_rad'), '%.1f '), ...
    params.meta.R_max, params.meta.range_resolution);

% ---- 2. 实验矩阵 ----
precoders     = {'zf', 'nullspace', 'lagrange'};
snr_list      = -30:5:10;          % SNR 范围 -30~10 dB
n_mc          = 30;                % 蒙特卡洛次数 (提高以获得可靠误差棒)
n_prec        = numel(precoders);
n_snr         = numel(snr_list);

fprintf('SNR 范围: [%d, %d] dB, 共 %d 点\n', snr_list(1), snr_list(end), n_snr);
fprintf('蒙特卡洛: %d 次/点, 总计 %d 次估计\n', n_mc, n_snr * n_prec * n_mc);
est_total = n_snr * n_prec * n_mc;
fprintf('预估耗时: ~%.0f 分钟 (~%.1f 小时)\n\n', est_total * 28 / 60, est_total * 28 / 3600);

% ---- 3. 预编码器准备 (波形生成一次, 信道固定) ----
fprintf('--- 生成波形 (3种预编码, SI 开启) ---\n');
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

% ---- 4. 主循环: SNR × 预编码 × MC ----
rmse_R     = zeros(n_prec, n_snr, n_mc);
rmse_theta = zeros(n_prec, n_snr, n_mc);
rmse_v     = zeros(n_prec, n_snr, n_mc);

est_total = n_snr * n_prec * n_mc;
est_done  = 0;
t_loop_start = tic;

for snr_i = 1:n_snr
    snr_val = snr_list(snr_i);

    for prec_i = 1:n_prec
        pt = precoders{prec_i};
        tx_signal = tx_signals{prec_i}.X;

        p = params;
        p.SNR = snr_val;
        p.enable_SI = true;        % ★ 确保 SI 开启 ★
        p.H_SI_matrix = H_SI;      % ★ 矩阵 SI 模式 (与预编码器同一 H_SI)
        p.beta_SI = 0.02;          % ★ SI 残差 = 2% 目标
        p.R_SI = 0;                % 矩阵模式: SI 无特定距离

        for mc_i = 1:n_mc
            est_done = est_done + 1;

            % 显式绑定迭代索引，避免 rng('shuffle') 在 batch 模式同秒碰撞
            rng(sum(100*clock) + mc_i * 1000 + snr_i * 100 + prec_i);

            t_est = tic;
            rx_cube = simulate_radar_channel_3d(tx_signal, p);
            [th, ph, R, v, ~] = joint_estimator_fast(rx_cube, tx_signal, p);
            rt = toc(t_est);

            cmp = evaluate_estimation(th, ph, R, v, p, false);

            if isfield(cmp, 'rmse_R') && ~isnan(cmp.rmse_R)
                rmse_R(prec_i, snr_i, mc_i)     = cmp.rmse_R;
                rmse_theta(prec_i, snr_i, mc_i) = cmp.rmse_theta;
                rmse_v(prec_i, snr_i, mc_i)     = cmp.rmse_v;
            else
                rmse_R(prec_i, snr_i, mc_i)     = NaN;
                rmse_theta(prec_i, snr_i, mc_i) = NaN;
                rmse_v(prec_i, snr_i, mc_i)     = NaN;
            end

            clear rx_cube;

            % ---- 进度条 ----
            pct = 100 * est_done / est_total;
            elapsed = toc(t_loop_start);
            eta = elapsed / est_done * (est_total - est_done);
            bar_len = 30;
            bar_fill = round(bar_len * est_done / est_total);
            bar_str = ['[', repmat('=', 1, bar_fill), repmat(' ', 1, bar_len - bar_fill), ']'];
            fprintf('%s %3.0f%% | SNR=%+3ddB %-10s | mc=%d/%d | t=%.1fs | %s elapsed ETA %s\r', ...
                bar_str, pct, snr_val, pt, mc_i, n_mc, rt, ...
                datestr(seconds(elapsed), 'MM:SS'), datestr(seconds(eta), 'MM:SS'));
        end
    end
    fprintf('\n');
end
fprintf('\n');

% 每 SNR 点取中位数
% 用 median(..., 'omitnan') 替代 nanmedian —— 不需要统计工具箱
rmse_R_med     = median(rmse_R, 3, 'omitnan');
rmse_theta_med = median(rmse_theta, 3, 'omitnan');
rmse_v_med     = median(rmse_v, 3, 'omitnan');

% ---- 5. 保存结果 ----
results = struct();
results.snr_list       = snr_list;
results.precoders      = {precoders};
results.n_mc           = n_mc;
results.si_enabled     = true;
results.rmse_R         = rmse_R;
results.rmse_theta     = rmse_theta;
results.rmse_v         = rmse_v;
results.rmse_R_med     = rmse_R_med;
results.rmse_theta_med = rmse_theta_med;
results.rmse_v_med     = rmse_v_med;
results.params_summary = struct(...
    'Nt', Nt_total, 'Nr', Nr_total, 'Ns', params.N, 'L', params.K, ...
    'K_stream', params.K_stream, 'kappa_SI', hsi_cfg.kappa_SI, ...
    'enable_SI', params.enable_SI);
results.total_runtime = toc(t_all);

save('mat数据/task5_rmse_vs_snr_si_results.mat', '-struct', 'results', '-v7.3');
fprintf('结果已保存: mat数据/task5_rmse_vs_snr_si_results.mat\n');
fprintf('总耗时: %.1f 分钟\n', results.total_runtime / 60);

% ---- 6. 打印数据摘要 ----
fprintf('\n=== 距离 RMSE (m) 摘要 ===\n');
fprintf('%8s  %10s  %10s  %10s\n', 'SNR(dB)', 'ZF', 'Nullspace', 'Lagrange');
for i = 1:n_snr
    fprintf('%+8d  %10.2f  %10.2f  %10.2f\n', ...
        snr_list(i), rmse_R_med(1,i), rmse_R_med(2,i), rmse_R_med(3,i));
end

fprintf('============================================================\n');
fprintf('全部完成! 总耗时 %.1f 分钟\n', results.total_runtime / 60);
fprintf('============================================================\n');

% 桌面通知 (自动定位脚本所在目录)
try
    toast_py = fullfile(fileparts(mfilename('fullpath')), 'toast_notify.py');
    system(['python "' toast_py '" "Task5完成" "SI-ON MC=30 仿真结束"']);
catch
end
