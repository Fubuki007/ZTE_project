% =========================================================================
% task_si_suppression_nullspace_sic_full.m
%   服务器完整版：Angle / Range / Velocity RMSE vs SNR
%   三条曲线：
%     1. ZF
%     2. Null-space
%     3. Null-space + digital SIC (LS 估计 SI 信道，参考 SIC.m)
%
%   参数与之前 7 点图保持一致：
%     SNR = -60:5:30, MC = 100, L = 256, Mrx = 16, beta_SI = 10
%
%   运行：
%     matlab -batch "task_si_suppression_nullspace_sic_full"
%
%   输出：
%     task_si_suppression_nullspace_sic_full.mat
%     fig/fig_si_suppression_nullspace_sic_{angle,velocity,range}.fig/.png
% =========================================================================
function task_si_suppression_nullspace_sic_full()
t_all = tic;
warning('off','all');

% ==================== 0. Log ==============================================
log_path = fullfile(pwd, 'task_si_suppression_nullspace_sic_full.log');
if isfile(log_path), delete(log_path); end
diary(log_path); diary on;

fprintf('============================================================\n');
fprintf('  Nullspace+SIC validation (full server version)\n');
fprintf('  ZF / Null-space / Null-space + digital SIC\n');
fprintf('  Start: %s\n', char(datetime('now')));
fprintf('============================================================\n\n');

% ==================== 1. Config ==========================================
methods       = {'zf', 'nullspace', 'nullspace'};
sic_flags     = [false, false, true];
method_labels = {'ZF', 'Null-space', 'Null-space + digital SIC'};
n_methods     = numel(methods);

snr_list = -60:5:30;       % 与之前 7 点图一致
n_snr    = numel(snr_list);
n_mc     = 100;            % 蒙特卡洛次数

L_val       = 256;
Mrx_fixed   = 64;
Mx_fixed    = 8;
My_fixed    = 8;
beta_SI_val = 10;

fprintf('  Methods: %s\n', strjoin(method_labels, ' | '));
fprintf('  SNR=[%d:%d:%d] (%d pts) | MC=%d | L=%d | Mrx=%d | beta_SI=%g\n', ...
    snr_list(1), snr_list(2)-snr_list(1), snr_list(end), n_snr, ...
    n_mc, L_val, Mrx_fixed, beta_SI_val);
fprintf('  Total trials: %d methods x %d SNR x %d MC = %d\n', ...
    n_methods, n_snr, n_mc, n_methods*n_snr*n_mc);
fprintf('============================================================\n\n');

% Reproducible seeds
rng(20260730);
rng_seeds = randi(2^31-1, n_methods, n_snr, n_mc);

% ==================== 2. Base parameters =================================
baseParams = build_default_params();
baseParams.theta_true = [24.63, 15.94];
baseParams.phi_true   = [30.99, 13.58];
baseParams.R_true     = [200.6, 210.4];
baseParams.v_true     = [15.1, -5.4];
baseParams.alpha      = [1.0, 0.8];
baseParams.enable_SI  = true;
baseParams.beta_SI    = beta_SI_val;
baseParams.enable_SIC = false;
baseParams.sic_use_true_channel = false;
baseParams.SIC_pilot_len = 128;     % 比 SIC.m 的 64 稍长，低 SNR 下 LS 更稳
baseParams.K          = L_val;
baseParams.K_stream   = 2;
baseParams.user_theta_rad = deg2rad(baseParams.theta_true(:));
baseParams.user_phi_rad   = deg2rad(baseParams.phi_true(:));
baseParams.Mx = Mx_fixed;
baseParams.My = My_fixed;
baseParams.joint_fft_3d.Na_x = Mx_fixed;
baseParams.joint_fft_3d.Na_y = My_fixed;
baseParams.fast_estimator.n_samp_l = min(64, max(8, floor(L_val/2)));
baseParams.fast_estimator.R_max_gate = 600;   % 滤除近距离/远距离 SI 假峰

Nt_total = baseParams.Ntx * baseParams.Nty;
Nr_fixed = Mx_fixed * My_fixed;
fprintf('  Mrx=%d (%dx%d), Nt=%d, Ns=%d, B=%.1f MHz\n', ...
    Mrx_fixed, Mx_fixed, My_fixed, Nt_total, baseParams.N, baseParams.B/1e6);

% H_SI: 预编码用 64xNt，接收/SIC 用 16xNt
rng(20260730);
hsi_cfg_tx = struct( ...
    'model','ura_rician', 'Nt_total',Nt_total, 'Nr_total',64, ...
    'kappa_SI',10, 'Ntx',baseParams.Ntx, 'Nty',baseParams.Nty, ...
    'Mx',8, 'My',8, 'd_lambda',0.5, ...
    'theta_tx_deg',baseParams.theta_SI, 'phi_tx_deg',baseParams.phi_SI, ...
    'theta_rx_deg',baseParams.theta_SI, 'phi_rx_deg',baseParams.phi_SI);
H_SI_common = generate_HSI(hsi_cfg_tx);

rng(20260731);
hsi_cfg_rx = struct( ...
    'model','ura_rician', 'Nt_total',Nt_total, 'Nr_total',Nr_fixed, ...
    'kappa_SI',10, 'Ntx',baseParams.Ntx, 'Nty',baseParams.Nty, ...
    'Mx',Mx_fixed, 'My',My_fixed, 'd_lambda',0.5, ...
    'theta_tx_deg',baseParams.theta_SI, 'phi_tx_deg',baseParams.phi_SI, ...
    'theta_rx_deg',baseParams.theta_SI, 'phi_rx_deg',baseParams.phi_SI);
H_SI_rx = generate_HSI(hsi_cfg_rx);

% ==================== 2.5 parfor =========================================
use_par = license('test', 'Distrib_Computing_Toolbox') && exist('parpool', 'file') == 2;
if use_par
    try
        n_workers = min(8, max(2, feature('numcores')));
        if isempty(gcp('nocreate'))
            parpool('Processes', n_workers);
        end
        fprintf('  Parallel: parfor %d workers\n\n', n_workers);
    catch
        use_par = false;
        fprintf('  Parallel startup failed, use serial\n\n');
    end
else
    fprintf('  Parallel not available, use serial\n\n');
end

% ==================== 3. Preallocation ===================================
rmse_R_all     = NaN(n_methods, n_snr, n_mc);
rmse_theta_all = NaN(n_methods, n_snr, n_mc);
rmse_v_all     = NaN(n_methods, n_snr, n_mc);

% ==================== 4. Main loop =======================================
for mi = 1:n_methods
    method = methods{mi};
    fprintf('\n==== Method %d/%d: %s ====\n', mi, n_methods, method_labels{mi});

    p_tx = baseParams;
    p_tx.precoder_type = method;
    p_tx.H_SI          = H_SI_rx;   % 修正：预编码设计与实际 SI 注入使用同一个 H_SI
    p_tx.H_SI_matrix   = H_SI_rx;

    fprintf('  Generating TX waveform (precoder=%s)...\n', method);
    tx = generate_mimo_ofdm_waveform(p_tx);
    X_tx = tx.X;
    clear tx;
    fprintf('  TX: [%dx%dx%dx%d]\n', size(X_tx,1), size(X_tx,2), size(X_tx,3), size(X_tx,4));

    t_method = tic;
    for si = 1:n_snr
        snr_val = snr_list(si);
        p = p_tx;
        p.SNR         = snr_val;
        p.enable_SI   = true;
        p.enable_SIC  = sic_flags(mi);
        p.H_SI_matrix = H_SI_rx;
        p.beta_SI     = beta_SI_val;

        fprintf('  [SNR %+4d dB] (%d/%d) ', snr_val, si, n_snr);
        if use_par
            parfor mc_i = 1:n_mc
                res = local_mc_rmse_full(rng_seeds(mi, si, mc_i), X_tx, p);
                rmse_R_all(mi, si, mc_i)     = res(1);
                rmse_theta_all(mi, si, mc_i) = res(2);
                rmse_v_all(mi, si, mc_i)     = res(3);
            end
        else
            for mc_i = 1:n_mc
                res = local_mc_rmse_full(rng_seeds(mi, si, mc_i), X_tx, p);
                rmse_R_all(mi, si, mc_i)     = res(1);
                rmse_theta_all(mi, si, mc_i) = res(2);
                rmse_v_all(mi, si, mc_i)     = res(3);
                if mod(mc_i, 20) == 0, fprintf('.'); end
            end
        end

        fprintf(' | R=%.3f m  th=%.3f deg  v=%.3f m/s | NaN:%d/%d\n', ...
            median(rmse_R_all(mi,si,:),'omitnan'), ...
            median(rmse_theta_all(mi,si,:),'omitnan'), ...
            median(rmse_v_all(mi,si,:),'omitnan'), ...
            sum(isnan(rmse_R_all(mi,si,:))), n_mc);
    end

    fprintf('  %s finished: %.1f min\n', method_labels{mi}, toc(t_method)/60);
end

fprintf('\nTotal simulation time: %.1f min\n', toc(t_all)/60);

% ==================== 5. Summary =========================================
rmse_R_med     = median(rmse_R_all, 3, 'omitnan');
rmse_theta_med = median(rmse_theta_all, 3, 'omitnan');
rmse_v_med     = median(rmse_v_all, 3, 'omitnan');

save(fullfile(pwd, 'task_si_suppression_nullspace_sic_full.mat'), ...
    'snr_list', 'methods', 'sic_flags', 'method_labels', ...
    'n_mc', 'beta_SI_val', 'L_val', 'Mx_fixed', 'My_fixed', ...
    'rmse_R_all', 'rmse_theta_all', 'rmse_v_all', ...
    'rmse_R_med', 'rmse_theta_med', 'rmse_v_med');

fprintf('\n--- Summary ---\n');
for metric = {'Angle', 'Range', 'Velocity'}
    switch metric{1}
        case 'Angle',    data = rmse_theta_med; unit = 'deg';
        case 'Range',    data = rmse_R_med;     unit = 'm';
        case 'Velocity', data = rmse_v_med;     unit = 'm/s';
    end
    fprintf('\n%s RMSE (%s):\n', metric{1}, unit);
    fprintf('%8s  %16s  %16s  %16s\n', 'SNR', method_labels{1}, ...
        method_labels{2}, method_labels{3});
    for si = 1:n_snr
        fprintf('%+8d  %16.6f  %16.6f  %16.6f\n', ...
            snr_list(si), data(1,si), data(2,si), data(3,si));
    end
end

% ==================== 6. Figures =========================================
fig_dir = fullfile(pwd, 'fig');
if ~exist(fig_dir, 'dir'), mkdir(fig_dir); end

titles  = {'Angle RMSE vs SNR (L = 256, MC = 100)', ...
           'Range RMSE vs SNR (L = 256, MC = 100)', ...
           'Velocity RMSE vs SNR (L = 256, MC = 100)'};
ylabels = {'Angle RMSE (deg)', 'Range RMSE (m)', 'Velocity RMSE (m/s)'};
fnames  = {'angle', 'range', 'velocity'};
datas   = {rmse_theta_med, rmse_R_med, rmse_v_med};

colors    = {[0.902 0.294 0.208], [0.200 0.627 0.173], [0.100 0.420 0.750]};
markers   = {'o', '^', 'v'};
linestyles = {'-', '-.', '--'};

for fi = 1:3
    fig = figure('Color', 'w', 'Units', 'pixels', ...
        'Position', [100+fi*30, 140+fi*30, 620, 470]);
    ax = axes('Parent', fig);
    hold(ax, 'on');

    for mi = 1:n_methods
        semilogy(ax, snr_list, max(datas{fi}(mi,:), 1e-12), ...
            'Color', colors{mi}, ...
            'Marker', markers{mi}, ...
            'LineStyle', linestyles{mi}, ...
            'LineWidth', 1.3, ...
            'MarkerSize', 5.5, ...
            'MarkerFaceColor', 'w', ...
            'DisplayName', method_labels{mi});
    end

    xlabel(ax, 'Input SNR (dB)', 'FontName', 'Times New Roman', 'FontSize', 10);
    ylabel(ax, ylabels{fi}, 'FontName', 'Times New Roman', 'FontSize', 10);
    title(ax, titles{fi}, 'FontName', 'Times New Roman', ...
        'FontSize', 10, 'FontWeight', 'normal');
    legend(ax, method_labels, 'Location', 'northeast', 'Box', 'on', ...
        'FontName', 'Times New Roman', 'FontSize', 9);
    xlim(ax, [snr_list(1)-2, snr_list(end)+2]);

    yvals = datas{fi}(:);
    yvals = yvals(~isnan(yvals) & yvals>0);
    if ~isempty(yvals)
        ylo = 10^floor(log10(min(yvals)));
        yhi = 10^ceil(log10(max(yvals)));
        ylim(ax, [ylo, yhi]);
    end

    apply_nature_axes(ax);
    set(ax, 'YScale', 'log');
    ytick_vals = 10.^(floor(log10(ylim(ax))) : ceil(log10(ylim(ax))));
    set(ax, 'YTick', ytick_vals);
    set(ax, 'YTickLabel', arrayfun(@(v) sprintf('10^{%d}', round(log10(v))), ...
        ytick_vals, 'UniformOutput', false));
    hold(ax, 'off');

    base_path = fullfile(fig_dir, sprintf('fig_si_suppression_nullspace_sic_%s', fnames{fi}));
    savefig(fig, [base_path '.fig']);
    exportgraphics(fig, [base_path '.png'], 'Resolution', 300);
    close(fig);
    fprintf('  saved: %s.fig/.png\n', base_path);
end

fprintf('\nDone. Saved .mat and figures.\n');
diary off;
end

% =========================================================================
% parfor helper
% =========================================================================
function res = local_mc_rmse_full(seed, X_tx, p)
rng(seed);
rx_cube = simulate_radar_channel_3d(X_tx, p);
[th, ph, R, v, ~] = joint_estimator_fast(rx_cube, X_tx, p);
cmp = evaluate_estimation(th, ph, R, v, p, false);
if isfield(cmp, 'rmse_R') && ~isnan(cmp.rmse_R)
    res = [cmp.rmse_R, cmp.rmse_theta, cmp.rmse_v];
else
    res = [NaN, NaN, NaN];
end
end




