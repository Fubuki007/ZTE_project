% =========================================================================
% task_range_rmse_only.m — 仅距离RMSE vs SNR (semilogy, SI-ON, ZF)
%   目的: 专注距离RMSE，提高MC次数+加密SNR以消除抖动
%   Y轴: 10^n (对数刻度), X轴: SNR (dB)
% =========================================================================
function task_range_rmse_only()
t_all = tic;
warning('off','all');

% ---- 参数 ----
mrx_list   = [4  16];
mrx_Mx     = [2   4];
mrx_My     = [2   4];
snr_list   = -40:5:0;        % SNR=-40~0dB, 5dB步长, 9个点 (看趋势够用)
n_snr      = numel(snr_list);
n_mc       = 150;            % MC=150, 9点×150×2配置≈不到20分钟
n_mrx      = numel(mrx_list);

fprintf('=== 距离RMSE vs SNR (semilogy) ===\n');
fprintf('SNR: [%d:%d:%d] (%d点)\n', snr_list(1), snr_list(2)-snr_list(1), snr_list(end), n_snr);
fprintf('MC: %d, Mrx: %s\n\n', n_mc, mat2str(mrx_list));

% 预生成种子
rng(20260728);
rng_seeds = randi(2^31-1, n_mrx, n_snr, n_mc);

% ---- TX波形 ----
fprintf('--- 生成 TX 波形 (ZF, Ns=12672) ---\n');
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

Nt_total = baseParams.Ntx * baseParams.Nty;
Nr_default = baseParams.Mx * baseParams.My;
hsi_cfg_base = struct( ...
    'model','ura_rician', 'Nt_total',Nt_total, 'Nr_total',Nr_default, ...
    'kappa_SI',10, 'Ntx',baseParams.Ntx, 'Nty',baseParams.Nty, ...
    'Mx',baseParams.Mx, 'My',baseParams.My, 'd_lambda',0.5, ...
    'theta_tx_deg',baseParams.theta_SI, 'phi_tx_deg',baseParams.phi_SI, ...
    'theta_rx_deg',baseParams.theta_SI, 'phi_rx_deg',baseParams.phi_SI);
baseParams.H_SI = generate_HSI(hsi_cfg_base);

tx = generate_mimo_ofdm_waveform(baseParams);
X_tx = tx.X;
fprintf('TX: [%d x %d x %d x %d]\n\n', size(X_tx,1), size(X_tx,2), size(X_tx,3), size(X_tx,4));

% ---- 主仿真 (仅距离) ----
rmse_R_all = zeros(n_mrx, n_snr, n_mc);

for mrx_i = 1:n_mrx
    Mrx = mrx_list(mrx_i);
    Mxv = mrx_Mx(mrx_i);
    Myv = mrx_My(mrx_i);
    Nr  = Mxv * Myv;
    
    fprintf('==== Mrx=%d (%dx%d, Nr=%d) ====\n', Mrx, Mxv, Myv, Nr);
    
    p_mrx = baseParams;
    p_mrx.Mx = Mxv; p_mrx.My = Myv;
    p_mrx.joint_fft_3d.Na_x = Mxv;
    p_mrx.joint_fft_3d.Na_y = Myv;
    
    hsi_cfg = struct( ...
        'model','ura_rician', 'Nt_total',Nt_total, 'Nr_total',Nr, ...
        'kappa_SI',10, 'Ntx',baseParams.Ntx, 'Nty',baseParams.Nty, ...
        'Mx',Mxv, 'My',Myv, 'd_lambda',0.5, ...
        'theta_tx_deg',baseParams.theta_SI, 'phi_tx_deg',baseParams.phi_SI, ...
        'theta_rx_deg',baseParams.theta_SI, 'phi_rx_deg',baseParams.phi_SI);
    p_mrx.H_SI_matrix = generate_HSI(hsi_cfg);
    
    t_mrx = tic;
    for snr_i = 1:n_snr
        snr_val = snr_list(snr_i);
        rr = zeros(1, n_mc);
        
        for mc_i = 1:n_mc
            rng(rng_seeds(mrx_i, snr_i, mc_i));
            p = p_mrx;
            p.SNR = snr_val;
            
            rxCube = simulate_radar_channel_3d(X_tx, p);
            [~, ~, R_est, ~, ~] = joint_estimator_fast(rxCube, X_tx, p);
            cmp = evaluate_estimation(NaN, NaN, R_est, NaN, p, false);
            clear rxCube R_est;
            
            if isfield(cmp, 'rmse_R') && ~isnan(cmp.rmse_R)
                rr(mc_i) = cmp.rmse_R;
            else
                rr(mc_i) = NaN;
            end
        end
        
        rmse_R_all(mrx_i, snr_i, :) = rr;
        el = toc(t_mrx);
        fprintf('  SNR%+4d | R=%.3f m | %s\n', snr_val, median(rr,'omitnan'), ...
            duration(0,0,round(el),'Format','mm:ss'));
    end
    fprintf('  Mrx=%d done: %.1f min\n\n', Mrx, toc(t_mrx)/60);
end

fprintf('Total simulation: %.1f min\n\n', toc(t_all)/60);

% ---- 汇总 ----
rmse_R_med = median(rmse_R_all, 3, 'omitnan');
fprintf('=== 距离 RMSE (m) ===\n');
fprintf('%8s  Mrx=%-3d  Mrx=%-3d\n', 'SNR', mrx_list(1), mrx_list(2));
for si = 1:n_snr
    fprintf('%+8d  %7.3f  %7.3f\n', snr_list(si), rmse_R_med(1,si), rmse_R_med(2,si));
end

% ---- 保存数据 ----
save('task_range_rmse_only.mat', 'snr_list', 'mrx_list', 'rmse_R_med', 'rmse_R_all', 'n_mc');
fprintf('\n数据已保存: task_range_rmse_only.mat\n');

% ---- ★ semilogy 出图 ----
fig_dir = fullfile(pwd, 'fig');
png_dir = fullfile(pwd, 'png');
if ~exist(fig_dir, 'dir'), mkdir(fig_dir); end
if ~exist(png_dir, 'dir'), mkdir(png_dir); end

colors = {[0.902 0.294 0.208], [0.302 0.733 0.835]};
markers = {'o', 's'};
linestyles = {'-', '--'};
leg_str = arrayfun(@(m) sprintf('M_{rx}=%d', m), mrx_list, 'UniformOutput', false);

% 参考 run_nature_performance_plots.m 的 Nature 风格配色
fig = figure('Position', [100, 100, 640, 480], 'Color', 'w');
hold on;

for mi = 1:n_mrx
    semilogy(snr_list, max(rmse_R_med(mi, :), 1e-12), ...
        'Color', colors{mi}, ...
        'Marker', markers{mi}, ...
        'LineStyle', linestyles{mi}, ...
        'LineWidth', 1.15, ...
        'MarkerSize', 4.5, ...
        'MarkerFaceColor', 'w');    % Nature 风格: 空心标记
end

xlabel('Input SNR (dB)', 'FontName', 'Times New Roman', 'FontSize', 10);
ylabel('Range RMSE (m)', 'FontName', 'Times New Roman', 'FontSize', 10);
title('Range RMSE vs SNR  (SI-ON, \beta_{SI}=0.1, SIC, ZF)', ...
    'FontName', 'Times New Roman', 'FontSize', 10, 'FontWeight', 'normal');
legend(leg_str, 'Location', 'northeast', 'Box', 'on', ...
    'FontName', 'Times New Roman', 'FontSize', 8);
xlim([snr_list(1)-2, snr_list(end)+2]);

apply_nature_axes(gca);
set(gca, 'YScale', 'log');   % ★ semilogy后显式设log, 自动出10^n刻度

fig_path = fullfile(fig_dir, 'fig_range_rmse_semilogy.fig');
png_path = fullfile(png_dir, 'fig_range_rmse_semilogy.png');
savefig(fig, fig_path);
exportgraphics(fig, png_path, 'Resolution', 600);
fprintf('  fig + png 已保存\n');

fprintf('\n=== ALL DONE (%.1f min) ===\n', toc(t_all)/60);
end
