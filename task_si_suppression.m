% =========================================================================
% task_si_suppression.m — SI 抑制效果对比: ZF(不抑制) vs 零空间
%
%   验收目的: 证明零空间预编码能有效抑制自干扰 (SI), 强 SI (β_SI=10) 下验证
%
%   两条曲线 (同一图上):
%     1. 传统 ZF       — 有 SI, 不抑制 (precoder_type='zf')
%     2. 零空间法       — 有 SI, 预编码抑制 (precoder_type='nullspace')
%                        (bf.m W1: W=W0-Nc*pinv(H_SI*Nc)*H_SI*W0, 理想 91.5dB)
%
%   参数: Mrx=16, L=256, beta_SI=10 (强 SI), enable_SIC=false, K_stream=2
%         SNR=-20:5:10 (7点), MC=70
%   预估: ~40-55 分钟 (Intel i7)
%
%   出图: 三张 fig (角度/速度/距离), Nature 风格 semilogy
%   数据: data_si_suppression_si10.csv (median RMSE, 与 zf_null 同格式)
% =========================================================================

clear; close all; clc;
t_all = tic;
warning('off','all');

% ==================== 0. 日志 ============================================
log_path = fullfile(pwd, 'matlab_run.log');
if isfile(log_path), delete(log_path); end
diary(log_path);
diary on;

fprintf('═══════════════════════════════════════════════════════════════\n');
fprintf('  task_si_suppression — SI 抑制效果对比\n');
fprintf('  传统 ZF (不抑制) vs 零空间法 vs 拉格朗日法\n');
fprintf('  开始时间: %s\n', char(datetime('now')));

% ==================== 1. 参数 ============================================
methods     = {'zf', 'nullspace'};
method_labels = {'ZF (no SI suppression)', 'Null-space'};
n_methods   = numel(methods);

snr_list    = -20:5:10;           % SNR (dB), 7 点
n_snr       = numel(snr_list);
n_mc        = 30;                 % 蒙特卡洛次数 (加速: 70→30)
L_val       = 256;                % OFDM 符号数
Mrx_fixed   = 16;                 % 接收天线
Mx_fixed    = 4;
My_fixed    = 4;

fprintf('  方法: %s\n', strjoin(method_labels, ' | '));
fprintf('  SNR=[%d:%d:%d] (%d点) | MC=%d | L=%d | Mrx=%d\n', ...
    snr_list(1), snr_list(2)-snr_list(1), snr_list(end), n_snr, n_mc, L_val, Mrx_fixed);
fprintf('  总估计次数: %d 方法 × %d SNR × %d MC = %d\n', ...
    n_methods, n_snr, n_mc, n_methods * n_snr * n_mc);
fprintf('═══════════════════════════════════════════════════════════════\n\n');

% 预生成种子 (可复现)
rng(20260730);
rng_seeds = randi(2^31-1, n_methods, n_snr, n_mc);

% ==================== 2. 基础参数 ========================================
fprintf('--- 基础参数 ---\n');
baseParams = build_default_params();
baseParams.theta_true = [24.63, 15.94];
baseParams.phi_true   = [30.99, 13.58];
baseParams.R_true     = [200.6, 210.4];
baseParams.v_true     = [15.1, -5.4];
baseParams.alpha      = [1.0, 0.8];
baseParams.enable_SI  = true;      % 开启 SI
baseParams.beta_SI    = 10;        % ★ SI 强度 = 10 (强 SI, 原 0.1 的 100 倍)
baseParams.enable_SIC = false;     % ★ 关闭数字 SIC, 纯靠预编码
baseParams.K          = L_val;
baseParams.K_stream   = 2;
baseParams.user_theta_rad = deg2rad(baseParams.theta_true(:));
baseParams.user_phi_rad   = deg2rad(baseParams.phi_true(:));
baseParams.Mx = Mx_fixed;
baseParams.My = My_fixed;
baseParams.joint_fft_3d.Na_x = Mx_fixed;
baseParams.joint_fft_3d.Na_y = My_fixed;
baseParams.fast_estimator.n_samp_l = min(64, max(8, floor(L_val/2)));

Nt_total = baseParams.Ntx * baseParams.Nty;
Nr_fixed = Mx_fixed * My_fixed;
fprintf('  Mrx=%d (%d×%d), Nt=%d, Ns=%d, B=%.1f MHz\n', ...
    Mrx_fixed, Mx_fixed, My_fixed, Nt_total, baseParams.N, baseParams.B/1e6);

% 构造 H_SI (对三种方法都相同)
hsi_cfg_tx = struct( ...
    'model','ura_rician', 'Nt_total',Nt_total, 'Nr_total',64, ...
    'kappa_SI',10, 'Ntx',baseParams.Ntx, 'Nty',baseParams.Nty, ...
    'Mx',8, 'My',8, 'd_lambda',0.5, ...
    'theta_tx_deg',baseParams.theta_SI, 'phi_tx_deg',baseParams.phi_SI, ...
    'theta_rx_deg',baseParams.theta_SI, 'phi_rx_deg',baseParams.phi_SI);
H_SI_common = generate_HSI(hsi_cfg_tx);   % 共享 SI 信道

hsi_cfg_rx = struct( ...
    'model','ura_rician', 'Nt_total',Nt_total, 'Nr_total',Nr_fixed, ...
    'kappa_SI',10, 'Ntx',baseParams.Ntx, 'Nty',baseParams.Nty, ...
    'Mx',Mx_fixed, 'My',My_fixed, 'd_lambda',0.5, ...
    'theta_tx_deg',baseParams.theta_SI, 'phi_tx_deg',baseParams.phi_SI, ...
    'theta_rx_deg',baseParams.theta_SI, 'phi_rx_deg',baseParams.phi_SI);
H_SI_rx = generate_HSI(hsi_cfg_rx);        % 接收端 SI 信道

% ==================== 3. 预分配 + 输出目录 ================================
rmse_R_all     = NaN(n_methods, n_snr, n_mc);
rmse_theta_all = NaN(n_methods, n_snr, n_mc);
rmse_v_all     = NaN(n_methods, n_snr, n_mc);

fig_dir = fullfile(pwd, 'fig');
if ~exist(fig_dir, 'dir'), mkdir(fig_dir); end

% ==================== 4. 主仿真 ==========================================
for mi = 1:n_methods
    method = methods{mi};
    fprintf('\n==== 方法 %d/%d: %s ====\n', mi, n_methods, method_labels{mi});

    % --- 生成该方法的 TX 波形 ---
    p_tx = baseParams;
    p_tx.precoder_type = method;
    p_tx.H_SI = H_SI_common;        % 预编码器需要 H_SI
    p_tx.H_SI_matrix = H_SI_rx;     % 接收端回波模拟需要

    fprintf('  生成 TX 波形 (precoder=%s)...\n', method);
    tx = generate_mimo_ofdm_waveform(p_tx);
    X_tx = tx.X;                    % [Ntx, Nty, Ns, L]
    clear tx;
    fprintf('  TX: [%d×%d×%d×%d]\n', size(X_tx,1), size(X_tx,2), size(X_tx,3), size(X_tx,4));

    % --- SNR 循环 ---
    t_method = tic;
    for snr_i = 1:n_snr
        snr_val = snr_list(snr_i);
        rr = NaN(1, n_mc);
        tt = NaN(1, n_mc);
        vv = NaN(1, n_mc);

        fprintf('  [SNR %+4d dB] (%d/%d) ', snr_val, snr_i, n_snr);
        t_snr = tic;

        for mc_i = 1:n_mc
            rng(rng_seeds(mi, snr_i, mc_i));
            p = p_tx;
            p.SNR = snr_val;

            try
                rxCube = simulate_radar_channel_3d(X_tx, p);
                [th, ph, R_est, v_est, ~] = joint_estimator_fast(rxCube, X_tx, p);
                cmp = evaluate_estimation(th, ph, R_est, v_est, p, false);
                clear rxCube th ph R_est v_est;

                if isfield(cmp, 'rmse_R') && ~isnan(cmp.rmse_R)
                    rr(mc_i) = cmp.rmse_R;
                    tt(mc_i) = cmp.rmse_theta;
                    vv(mc_i) = cmp.rmse_v;
                end
                clear cmp;
            catch ME
                fprintf('x');
                clear rxCube th ph R_est v_est cmp;
            end

            if mod(mc_i, 20) == 0, fprintf('.'); end
        end

        rmse_R_all(mi, snr_i, :)     = rr;
        rmse_theta_all(mi, snr_i, :) = tt;
        rmse_v_all(mi, snr_i, :)     = vv;

        el = toc(t_snr);
        nan_r = sum(isnan(rr));
        fprintf(' | R=%.2f m  th=%.2f°  v=%.2f m/s | NaN:%d/%d | %s\n', ...
            median(rr, 'omitnan'), median(tt, 'omitnan'), ...
            median(vv, 'omitnan'), nan_r, n_mc, ...
            duration(0,0,round(el),'Format','mm:ss'));
    end

    fprintf('  %s 完成: %.1f min\n', method_labels{mi}, toc(t_method)/60);
end

fprintf('\n总仿真时间: %.1f min\n', toc(t_all)/60);

% ==================== 5. 汇总 + 保存数据 =================================
rmse_R_med     = median(rmse_R_all, 3, 'omitnan');
rmse_theta_med = median(rmse_theta_all, 3, 'omitnan');
rmse_v_med     = median(rmse_v_all, 3, 'omitnan');

fprintf('\n═══════════════════════════════════════════════════════════════\n');
fprintf('  RMSE 汇总 (median over %d MC)\n', n_mc);
fprintf('═══════════════════════════════════════════════════════════════\n');

for metric = {'距离', '角度', '速度'}
    switch metric{1}
        case '距离', data = rmse_R_med;     unit = 'm';
        case '角度', data = rmse_theta_med; unit = '°';
        case '速度', data = rmse_v_med;     unit = 'm/s';
    end
    fprintf('\n--- %s RMSE (%s) ---\n', metric{1}, unit);
    fprintf('%8s', 'SNR');
    for mi = 1:n_methods, fprintf('  %-10s', method_labels{mi}); end
    fprintf('\n');
    for si = 1:n_snr
        fprintf('%+8d', snr_list(si));
        for mi = 1:n_methods, fprintf('  %10.4f', data(mi,si)); end
        fprintf('\n');
    end
end

mat_path = fullfile(pwd, 'task_si_suppression.mat');
save(mat_path, ...
    'snr_list', 'methods', 'method_labels', 'n_mc', ...
    'rmse_R_med', 'rmse_theta_med', 'rmse_v_med', ...
    'rmse_R_all', 'rmse_theta_all', 'rmse_v_all');
fprintf('\n数据已保存: %s\n', mat_path);

% ---- 写 CSV (与 data_si_suppression_zf_null.csv 同格式, 便于复用画图脚本) ----
csv_path = fullfile(pwd, 'data_si_suppression_si10.csv');
fid = fopen(csv_path, 'w');
fprintf(fid, 'snr,zf_R,zf_th,zf_v,ns_R,ns_th,ns_v\n');
fclose(fid);
csv_data = [snr_list(:), ...
    rmse_R_med(1,:)', rmse_theta_med(1,:)', rmse_v_med(1,:)', ...
    rmse_R_med(2,:)', rmse_theta_med(2,:)', rmse_v_med(2,:)'];
writematrix(csv_data, csv_path, 'WriteMode', 'append');
fprintf('CSV 已保存: %s\n', csv_path);

% ==================== 6. 出图 (Nature 风格, semilogy, 仅 .fig) ===========
fprintf('\n--- 出图 (Nature 风格, semilogy) ---\n');

% 两条线颜色: 红(ZF) / 蓝(零空间)
colors    = {[0.902 0.294 0.208], [0.302 0.733 0.835]};
markers   = {'o', 's'};
linestyle = {'-', '--'};
leg_str   = method_labels;

titles  = {'Angle', 'Velocity', 'Range'};
ylabels = {'Angle RMSE (deg)', 'Velocity RMSE (m/s)', 'Range RMSE (m)'};
datas   = {rmse_theta_med, rmse_v_med, rmse_R_med};
fnames  = {'angle_si10', 'velocity_si10', 'range_si10'};
filename_prefix = 'fig_si_suppression';  % for title

for fi = 1:3
    fig = figure('Color', 'w', 'Units', 'pixels', ...
        'Position', [120+fi*30, 160+fi*30, 600, 440]);
    hold on;

    for mi = 1:n_methods
        semilogy(snr_list, max(datas{fi}(mi, :), 1e-12), ...
            'Color', colors{mi}, ...
            'Marker', markers{mi}, ...
            'LineStyle', linestyle{mi}, ...
            'LineWidth', 1.3, ...
            'MarkerSize', 5.5, ...
            'MarkerFaceColor', 'w');
    end

    xlabel('Input SNR (dB)', 'FontName', 'Times New Roman', 'FontSize', 10);
    ylabel(ylabels{fi}, 'FontName', 'Times New Roman', 'FontSize', 10);
    title(sprintf('%s RMSE vs SNR — SI Suppression Comparison  (L=%d, MC=%d)', ...
        titles{fi}, L_val, n_mc), ...
        'FontName', 'Times New Roman', 'FontSize', 10, 'FontWeight', 'normal');
    legend(leg_str, 'Location', 'northeastoutside', 'Box', 'on', ...
        'FontName', 'Times New Roman', 'FontSize', 8);
    xlim([snr_list(1)-2, snr_list(end)+2]);

    apply_nature_axes(gca);
    set(gca, 'YScale', 'log');

    fig_path = fullfile(fig_dir, sprintf('%s_%s.fig', filename_prefix, fnames{fi}));
    savefig(fig, fig_path);
    fprintf('  %s → fig/\n', fnames{fi});
end

% ==================== 7. Toast 通知 ========================================
toast_script = fullfile(pwd, 'toast_notify.py');
if isfile(toast_script)
    try
        cmd = sprintf('python "%s" "SI-抑制完成(β_SI=10)" "%d方法x%dSNRx%dMC, %.1fmin"', ...
            toast_script, n_methods, n_snr, n_mc, toc(t_all)/60);
        system(cmd);
    catch
    end
end

fprintf('\n═══════════════════════════════════════════════════════════════\n');
fprintf('  完成时间: %s\n', char(datetime('now')));
fprintf('  总耗时: %.1f min\n', toc(t_all)/60);
fprintf('  日志: %s\n', log_path);
fprintf('═══════════════════════════════════════════════════════════════\n');

diary off;
