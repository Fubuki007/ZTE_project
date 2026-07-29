% =========================================================================
% task_L_quick_test.m — L=16 vs 64 RMSE对比 (角度+速度+距离, semilogy)
%
%   对比不同 OFDM 符号数 L (params.K) 对估计精度的影响。
%   参考项目: run_nature_performance_plots.m / task_mrx16_rmse_stable.m
%
%   参数: Mrx=16 固定, ZF预编码, SI-ON (beta=0.1, SIC), K_stream=2
%         SNR=-40:5:0 (9点), MC=100, L=[16, 64]
%   预估: ~25-35 分钟 (Intel i7)
%
%   出图: 三张独立 semilogy (角度/速度/距离), Nature 风格, fig+png
% =========================================================================
function task_L_quick_test()
t_all = tic;
warning('off','all');

% ==================== 0. 日志 ============================================
log_path = fullfile(pwd, 'matlab_run.log');
if isfile(log_path), delete(log_path); end
diary(log_path);
diary on;

fprintf('═══════════════════════════════════════════════════════════════\n');
fprintf('  task_L_quick_test — L=16 vs 64 RMSE 对比\n');
fprintf('  Mrx=16 | ZF | SI-ON (beta=0.1, SIC) | K_stream=2\n');
fprintf('  开始时间: %s\n', char(datetime('now')));

% ==================== 1. 参数 ============================================
L_list     = [16, 64];       % OFDM符号数 (params.K)
n_L        = numel(L_list);
snr_list   = -40:5:0;        % SNR (dB)
n_snr      = numel(snr_list);
n_mc       = 100;            % 蒙特卡洛次数
Mrx_fixed  = 16;
Mx_fixed   = 4;
My_fixed   = 4;

fprintf('  L=%s | SNR=[%d:%d:%d] (%d点) | MC=%d\n', ...
    mat2str(L_list), snr_list(1), snr_list(2)-snr_list(1), ...
    snr_list(end), n_snr, n_mc);
fprintf('  总估计次数: %d L × %d SNR × %d MC = %d\n', ...
    n_L, n_snr, n_mc, n_L * n_snr * n_mc);
fprintf('═══════════════════════════════════════════════════════════════\n\n');

% 预生成种子 (可复现)
rng(20260728);
rng_seeds = randi(2^31-1, n_L, n_snr, n_mc);

% ==================== 2. 基础参数 ========================================
fprintf('--- 基础参数 ---\n');
baseParams = build_default_params();
baseParams.theta_true = [24.63, 15.94];
baseParams.phi_true   = [30.99, 13.58];
baseParams.R_true     = [200.6, 210.4];
baseParams.v_true     = [15.1, -5.4];
baseParams.alpha      = [1.0, 0.8];
baseParams.enable_SI  = true;
baseParams.beta_SI    = 0.1;
baseParams.enable_SIC = true;
baseParams.precoder_type = 'zf';
baseParams.K_stream = 2;
baseParams.user_theta_rad = deg2rad(baseParams.theta_true(:));
baseParams.user_phi_rad   = deg2rad(baseParams.phi_true(:));
baseParams.Mx = Mx_fixed;
baseParams.My = My_fixed;
baseParams.joint_fft_3d.Na_x = Mx_fixed;
baseParams.joint_fft_3d.Na_y = My_fixed;

Nt_total = baseParams.Ntx * baseParams.Nty;
Nr_fixed = Mx_fixed * My_fixed;
fprintf('  Mrx=%d (%d×%d), Nt=%d, Ns=%d, B=%.1f MHz\n', ...
    Mrx_fixed, Mx_fixed, My_fixed, Nt_total, baseParams.N, baseParams.B/1e6);

% ==================== 3. 预分配 + 输出目录 ================================
rmse_R_all     = NaN(n_L, n_snr, n_mc);
rmse_theta_all = NaN(n_L, n_snr, n_mc);
rmse_v_all     = NaN(n_L, n_snr, n_mc);

fig_dir = fullfile(pwd, 'fig');
png_dir = fullfile(pwd, 'png');
if ~exist(fig_dir, 'dir'), mkdir(fig_dir); end
if ~exist(png_dir, 'dir'), mkdir(png_dir); end

% ==================== 4. 主仿真 ==========================================
for L_i = 1:n_L
    K_val = L_list(L_i);
    fprintf('\n==== L=%d (K=%d) ====\n', K_val, K_val);
    
    % --- 构造参数 ---
    p_L = baseParams;
    p_L.K = K_val;
    % 多普勒窗口自适应: 不超过 L/2
    p_L.fast_estimator.n_samp_l = min(64, max(8, floor(K_val/2)));
    
    % --- SI 信道 (固定 Mrx) ---
    hsi_cfg = struct( ...
        'model','ura_rician', 'Nt_total',Nt_total, 'Nr_total',Nr_fixed, ...
        'kappa_SI',10, 'Ntx',baseParams.Ntx, 'Nty',baseParams.Nty, ...
        'Mx',Mx_fixed, 'My',My_fixed, 'd_lambda',0.5, ...
        'theta_tx_deg',baseParams.theta_SI, 'phi_tx_deg',baseParams.phi_SI, ...
        'theta_rx_deg',baseParams.theta_SI, 'phi_rx_deg',baseParams.phi_SI);
    p_L.H_SI_matrix = generate_HSI(hsi_cfg);
    
    % H_SI for TX (兼容 generate_mimo_ofdm_waveform 内部引用)
    hsi_cfg_tx = struct( ...
        'model','ura_rician', 'Nt_total',Nt_total, 'Nr_total',64, ...
        'kappa_SI',10, 'Ntx',baseParams.Ntx, 'Nty',baseParams.Nty, ...
        'Mx',8, 'My',8, 'd_lambda',0.5, ...
        'theta_tx_deg',baseParams.theta_SI, 'phi_tx_deg',baseParams.phi_SI, ...
        'theta_rx_deg',baseParams.theta_SI, 'phi_rx_deg',baseParams.phi_SI);
    p_L.H_SI = generate_HSI(hsi_cfg_tx);
    
    % --- 发射波形 (每个 L 不同) ---
    fprintf('  生成 TX 波形 (L=%d)...\n', K_val);
    tx = generate_mimo_ofdm_waveform(p_L);
    X_tx = tx.X;
    clear tx;
    fprintf('  TX: [%d×%d×%d×%d]\n', size(X_tx,1), size(X_tx,2), size(X_tx,3), size(X_tx,4));
    
    % --- SNR 循环 ---
    t_L = tic;
    for snr_i = 1:n_snr
        snr_val = snr_list(snr_i);
        rr = NaN(1, n_mc);
        tt = NaN(1, n_mc);
        vv = NaN(1, n_mc);
        
        fprintf('  [SNR %+4d dB] (%d/%d) ', snr_val, snr_i, n_snr);
        t_snr = tic;
        
        for mc_i = 1:n_mc
            rng(rng_seeds(L_i, snr_i, mc_i));
            p = p_L;
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
                % 单次 MC 崩溃不中断
                fprintf('x');
                clear rxCube th ph R_est v_est cmp;
            end
            
            % 进度点 (每 20 个)
            if mod(mc_i, 20) == 0, fprintf('.'); end
        end
        
        rmse_R_all(L_i, snr_i, :)     = rr;
        rmse_theta_all(L_i, snr_i, :) = tt;
        rmse_v_all(L_i, snr_i, :)     = vv;
        
        el = toc(t_snr);
        nan_r = sum(isnan(rr));
        fprintf(' | R=%.2f m  th=%.2f°  v=%.2f m/s | NaN:%d/%d | %s\n', ...
            median(rr, 'omitnan'), median(tt, 'omitnan'), ...
            median(vv, 'omitnan'), nan_r, n_mc, ...
            duration(0,0,round(el),'Format','mm:ss'));
    end
    
    fprintf('  L=%d 完成: %.1f min\n', K_val, toc(t_L)/60);
end

fprintf('\n总仿真时间: %.1f min\n', toc(t_all)/60);

% ==================== 5. 汇总 + 保存数据 =================================
rmse_R_med     = median(rmse_R_all, 3, 'omitnan');
rmse_theta_med = median(rmse_theta_all, 3, 'omitnan');
rmse_v_med     = median(rmse_v_all, 3, 'omitnan');

fprintf('\n═══════════════════════════════════════════════════════════════\n');
fprintf('  RMSE 汇总 (median over %d MC)\n', n_mc);
fprintf('═══════════════════════════════════════════════════════════════\n');

fprintf('\n--- 距离 RMSE (m) ---\n');
fprintf('%8s  L=%-3d  L=%-3d\n', 'SNR', L_list(1), L_list(2));
for si = 1:n_snr
    fprintf('%+8d  %7.2f  %7.2f\n', snr_list(si), rmse_R_med(1,si), rmse_R_med(2,si));
end

fprintf('\n--- 角度 RMSE (°) ---\n');
fprintf('%8s  L=%-3d  L=%-3d\n', 'SNR', L_list(1), L_list(2));
for si = 1:n_snr
    fprintf('%+8d  %7.2f  %7.2f\n', snr_list(si), rmse_theta_med(1,si), rmse_theta_med(2,si));
end

fprintf('\n--- 速度 RMSE (m/s) ---\n');
fprintf('%8s  L=%-3d  L=%-3d\n', 'SNR', L_list(1), L_list(2));
for si = 1:n_snr
    fprintf('%+8d  %7.2f  %7.2f\n', snr_list(si), rmse_v_med(1,si), rmse_v_med(2,si));
end

mat_path = fullfile(pwd, 'task_L_quick_test.mat');
save(mat_path, ...
    'snr_list', 'L_list', 'n_mc', ...
    'rmse_R_med', 'rmse_theta_med', 'rmse_v_med', ...
    'rmse_R_all', 'rmse_theta_all', 'rmse_v_all');
fprintf('\n数据已保存: %s\n', mat_path);

% ==================== 6. 出图 (Nature 风格, 参考 run_nature_performance_plots.m) ===
fprintf('\n--- 出图 (Nature 风格, semilogy) ---\n');

% Nature journal 配色: 红(L=16) vs 蓝(L=64), 空心标记
colors    = {[0.902 0.294 0.208], [0.302 0.733 0.835]};
markers   = {'o', 's'};
linestyle = {'-', '--'};
leg_str   = {'L=16', 'L=64'};

titles  = {'Angle', 'Velocity', 'Range'};
ylabels = {'Angle RMSE (deg)', 'Velocity RMSE (m/s)', 'Range RMSE (m)'};
datas   = {rmse_theta_med, rmse_v_med, rmse_R_med};
fnames  = {'angle', 'velocity', 'range'};

for fi = 1:3
    fig = figure('Color', 'w', 'Units', 'pixels', ...
        'Position', [120+fi*30, 160+fi*30, 560, 420]);
    hold on;
    
    for Li = 1:n_L
        semilogy(snr_list, max(datas{fi}(Li, :), 1e-12), ...
            'Color', colors{Li}, ...
            'Marker', markers{Li}, ...
            'LineStyle', linestyle{Li}, ...
            'LineWidth', 1.15, ...
            'MarkerSize', 4.5, ...
            'MarkerFaceColor', 'w');
    end
    
    xlabel('Input SNR (dB)', 'FontName', 'Times New Roman', 'FontSize', 10);
    ylabel(ylabels{fi}, 'FontName', 'Times New Roman', 'FontSize', 10);
    title(sprintf('%s RMSE vs SNR  (L=16 vs 64, SI-ON)', titles{fi}), ...
        'FontName', 'Times New Roman', 'FontSize', 10, 'FontWeight', 'normal');
    legend(leg_str, 'Location', 'northeast', 'Box', 'on', ...
        'FontName', 'Times New Roman', 'FontSize', 8);
    xlim([snr_list(1)-2, snr_list(end)+2]);
    
    apply_nature_axes(gca);
    set(gca, 'YScale', 'log');   % semilogy 自动出 10^n 刻度
    
    % 保存 .fig + .png
    fig_path = fullfile(fig_dir, sprintf('fig_L_test_%s_semilogy.fig', fnames{fi}));
    png_path = fullfile(png_dir, sprintf('fig_L_test_%s_semilogy.png', fnames{fi}));
    savefig(fig, fig_path);
    exportgraphics(fig, png_path, 'Resolution', 600);
    fprintf('  %s → fig/ + png/\n', fnames{fi});
end

% ==================== 7. Toast 通知 =======================================
toast_script = fullfile(pwd, 'toast_notify.py');
if isfile(toast_script)
    try
        cmd = sprintf('python "%s" "L-test完成" "L=16vs64, %.1fmin"', ...
            toast_script, toc(t_all)/60);
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
end
