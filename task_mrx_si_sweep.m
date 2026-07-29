% =========================================================================
% task_mrx_si_sweep.m — Mrx=4,16 SI-ON RMSE vs SNR (三张独立图)
%   ZF预编码, SI=ON, beta_SI=1.0, Nature风格
%   输出: fig/*.fig + png/*.png
% =========================================================================
function task_mrx_si_sweep()
t_all = tic;
warning('off','all');

% ---- 日志 ----
log_path = fullfile(pwd, 'matlab_run.log');
if isfile(log_path), delete(log_path); end
diary(log_path); diary on;

fprintf('=== Mrx Sweep SI-ON: Mrx=[4 16] ZF beta_SI=1.0 ===\n\n');

% ---- 1. 参数配置 ----
mrx_list = [4 16];
mrx_Mx   = [2  4];
mrx_My   = [2  4];
n_mrx    = numel(mrx_list);

snr_list = -5:5:20;        % SNR 扫描范围 (dB)
n_snr    = numel(snr_list);
n_mc     = 70;              % 蒙特卡洛次数

fprintf('SNR: %s\n', mat2str(snr_list));
fprintf('MC: %d, Mrx: %s\n\n', n_mc, mat2str(mrx_list));

% 预生成种子 (确保不同配置独立)
rng(20260722);
rng_seeds = randi(2^31-1, n_mrx, n_snr, n_mc);

% ---- 2. TX波形 (ZF, Ns=12672, 合理目标角度, 与 Mrx 无关) ----
fprintf('--- 生成 TX 波形 (ZF, Ns=12672, K_stream=2) ---\n');
baseParams = build_default_params();

% ★ 覆盖目标参数为合理值 (60.83°太偏, broadside参考失配)
baseParams.theta_true = [24.63, 15.94];
baseParams.phi_true   = [30.99, 13.58];
baseParams.R_true     = [200.6, 210.4];
baseParams.v_true     = [15.1, -5.4];
baseParams.alpha      = [1.0, 0.8];

baseParams.enable_SI  = true;
baseParams.beta_SI    = 0.1;
baseParams.enable_SIC = true;    % ★ 数字自干扰消除 (论文 IV.B, 公式 50)
baseParams.precoder_type = 'zf';
baseParams.K_stream = 2;         % 两个用户分别对准两个目标, 保证雷达照射
baseParams.user_theta_rad = deg2rad(baseParams.theta_true(:));
baseParams.user_phi_rad   = deg2rad(baseParams.phi_true(:));
fprintf('  Ns=%d, B=%.1f MHz, dR=%.3f m\n', baseParams.N, baseParams.B/1e6, baseParams.meta.range_resolution);

% 生成 H_SI 用于构造发射信号 (不用于 ZF, 仅保留以兼容)
Nt_total = baseParams.Ntx * baseParams.Nty;
Nr_default = baseParams.Mx * baseParams.My;
hsi_cfg_base = struct( ...
    'model',    'ura_rician', ...
    'Nt_total', Nt_total, 'Nr_total', Nr_default, ...
    'kappa_SI', 10, ...
    'Ntx', baseParams.Ntx, 'Nty', baseParams.Nty, ...
    'Mx',  baseParams.Mx,  'My',  baseParams.My, ...
    'd_lambda', 0.5, ...
    'theta_tx_deg', baseParams.theta_SI, 'phi_tx_deg', baseParams.phi_SI, ...
    'theta_rx_deg', baseParams.theta_SI, 'phi_rx_deg', baseParams.phi_SI);
baseParams.H_SI = generate_HSI(hsi_cfg_base);

tx = generate_mimo_ofdm_waveform(baseParams);
X_tx = tx.X;
fprintf('TX: [%d x %d x %d x %d]\n\n', size(X_tx,1), size(X_tx,2), size(X_tx,3), size(X_tx,4));

% ---- 3. 主仿真循环 ----
rmse_R_all     = zeros(n_mrx, n_snr, n_mc);
rmse_theta_all = zeros(n_mrx, n_snr, n_mc);
rmse_v_all     = zeros(n_mrx, n_snr, n_mc);

for mrx_i = 1:n_mrx
    Mrx = mrx_list(mrx_i);
    Mxv = mrx_Mx(mrx_i);
    Myv = mrx_My(mrx_i);
    Nr  = Mxv * Myv;
    
    fprintf('==== Mrx=%d (%dx%d, Nr=%d) ====\n', Mrx, Mxv, Myv, Nr);
    
    % 构造该 Mrx 的参数
    p_mrx = baseParams;
    p_mrx.Mx = Mxv; p_mrx.My = Myv;
    p_mrx.joint_fft_3d.Na_x = Mxv;
    p_mrx.joint_fft_3d.Na_y = Myv;
    
    % 为该 Mrx 生成 H_SI_matrix (矩阵 SI 模式)
    hsi_cfg = struct( ...
        'model',    'ura_rician', ...
        'Nt_total', Nt_total, 'Nr_total', Nr, ...
        'kappa_SI', 10, ...
        'Ntx', baseParams.Ntx, 'Nty', baseParams.Nty, ...
        'Mx',  Mxv, 'My',  Myv, ...
        'd_lambda', 0.5, ...
        'theta_tx_deg', baseParams.theta_SI, 'phi_tx_deg', baseParams.phi_SI, ...
        'theta_rx_deg', baseParams.theta_SI, 'phi_rx_deg', baseParams.phi_SI);
    p_mrx.H_SI_matrix = generate_HSI(hsi_cfg);
    
    t_mrx = tic;
    for snr_i = 1:n_snr
        snr_val = snr_list(snr_i);
        rr = zeros(1, n_mc); tt = zeros(1, n_mc); vv = zeros(1, n_mc);
        
        for mc_i = 1:n_mc
            rng(rng_seeds(mrx_i, snr_i, mc_i));
            p = p_mrx;
            p.SNR = snr_val;
            
            rxCube = simulate_radar_channel_3d(X_tx, p);
            [th, ph, R_est, v_est, ~] = joint_estimator_fast(rxCube, X_tx, p);
            cmp = evaluate_estimation(th, ph, R_est, v_est, p, false);
            clear rxCube th ph R_est v_est;
            
            if isfield(cmp, 'rmse_R') && ~isnan(cmp.rmse_R)
                rr(mc_i)  = cmp.rmse_R;
                tt(mc_i)  = cmp.rmse_theta;
                vv(mc_i)  = cmp.rmse_v;
            else
                rr(mc_i) = NaN; tt(mc_i) = NaN; vv(mc_i) = NaN;
            end
        end
        
        rmse_R_all(mrx_i, snr_i, :)     = rr;
        rmse_theta_all(mrx_i, snr_i, :) = tt;
        rmse_v_all(mrx_i, snr_i, :)     = vv;
        
        % 进度
        el = toc(t_mrx);
        fprintf('  SNR%+4d | R=%.3f  th=%.3f°  v=%.3f m/s | %s\n', ...
            snr_val, median(rr,'omitnan'), median(tt,'omitnan'), ...
            median(vv,'omitnan'), datestr(seconds(el), 'MM:SS'));
    end
    fprintf('  Mrx=%d done: %.1f min\n\n', Mrx, toc(t_mrx)/60);
end

fprintf('Total simulation: %.1f min\n\n', toc(t_all)/60);

% ---- 4. 汇总 ----
rmse_R_med     = median(rmse_R_all, 3, 'omitnan');
rmse_theta_med = median(rmse_theta_all, 3, 'omitnan');
rmse_v_med     = median(rmse_v_all, 3, 'omitnan');

fprintf('=== Range RMSE (m) ===\n');
fprintf('%8s  Mrx=%-3d  Mrx=%-3d\n', 'SNR', mrx_list(1), mrx_list(2));
for si = 1:n_snr
    fprintf('%+8d  %7.3f  %7.3f\n', snr_list(si), rmse_R_med(1,si), rmse_R_med(2,si));
end
fprintf('\n=== Angle RMSE (deg) ===\n');
fprintf('%8s  Mrx=%-3d  Mrx=%-3d\n', 'SNR', mrx_list(1), mrx_list(2));
for si = 1:n_snr
    fprintf('%+8d  %7.3f  %7.3f\n', snr_list(si), rmse_theta_med(1,si), rmse_theta_med(2,si));
end
fprintf('\n=== Velocity RMSE (m/s) ===\n');
fprintf('%8s  Mrx=%-3d  Mrx=%-3d\n', 'SNR', mrx_list(1), mrx_list(2));
for si = 1:n_snr
    fprintf('%+8d  %7.3f  %7.3f\n', snr_list(si), rmse_v_med(1,si), rmse_v_med(2,si));
end

% ---- 5. 出图 (三张独立, .fig + .png) ----
fprintf('\n--- Plotting ---\n');
fig_dir = fullfile(pwd, 'fig');
png_dir = fullfile(pwd, 'png');
if ~exist(fig_dir, 'dir'), mkdir(fig_dir); end
if ~exist(png_dir, 'dir'), mkdir(png_dir); end

% 色盲友好配色
colors = {[0.902 0.294 0.208], [0.302 0.733 0.835]};  % 红 #E64B35, 蓝 #4DBBD5
markers = {'o', 's'};
linestyles = {'-', '--'};
leg_str = arrayfun(@(m) sprintf('M_{rx}=%d', m), mrx_list, 'UniformOutput', false);

% 直接使用线性值（不做 dB 转换）
titles   = {'Angle', 'Velocity', 'Range'};
ylabels  = {'Angle RMSE (deg)', 'Velocity RMSE (m/s)', 'Range RMSE (m)'};
datas    = {rmse_theta_med, rmse_v_med, rmse_R_med};
fnames   = {'angle', 'velocity', 'range'};

for fi = 1:3
    fig = figure('Position', [100+fi*30, 100+fi*30, 560, 420], 'Color', 'w');
    hold on;
    
    for mi = 1:n_mrx
        plot(snr_list, datas{fi}(mi, :), ...
            'Color', colors{mi}, ...
            'Marker', markers{mi}, ...
            'LineStyle', linestyles{mi}, ...
            'LineWidth', 1.5, ...
            'MarkerSize', 7, ...
            'MarkerFaceColor', colors{mi});
    end
    
    xlabel('SNR (dB)', 'FontName', 'Times New Roman', 'FontSize', 11);
    ylabel(ylabels{fi}, 'FontName', 'Times New Roman', 'FontSize', 11);
    title(sprintf('%s RMSE vs SNR (SI-ON, \\beta_{SI}=0.1, ZF)', titles{fi}), ...
        'FontName', 'Times New Roman', 'FontSize', 10);
    legend(leg_str, 'Location', 'northeast', 'FontSize', 9);
    apply_nature_axes(gca);
    xlim([snr_list(1)-2, snr_list(end)+2]);
    
    % 保存 .fig + .png
    fig_path = fullfile(fig_dir, sprintf('fig_%s_rmse_vs_snr_mrx_sion.fig', fnames{fi}));
    png_path = fullfile(png_dir, sprintf('fig_%s_rmse_vs_snr_mrx_sion.png', fnames{fi}));
    savefig(fig, fig_path);
    exportgraphics(fig, png_path, 'Resolution', 600);
    fprintf('  %s -> fig/ + png/\n', fnames{fi});
end

fprintf('\n=== ALL DONE (%.1f min) ===\n', toc(t_all)/60);
diary off;
end
