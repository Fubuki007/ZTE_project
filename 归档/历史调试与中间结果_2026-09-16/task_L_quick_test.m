% =========================================================================
% task_L_quick_test.m — L 参数扫描: RMSE对比 (角度+速度+距离, semilogy)
%
%   对比不同 OFDM 符号数 L (params.K) 对估计精度的影响。
%   参考项目: run_nature_performance_plots.m / task_mrx16_rmse_stable.m
%
%   参数: Mrx=16 固定, ZF预编码, SI-ON (beta=0.1, SIC), K_stream=2
%         SNR=-35:5:15 (11点), MC=100, L=[64, 128, 256, 512]
%   预估: ~60-90 分钟 (Intel i7)
%
%   出图: 三张独立 semilogy (角度/速度/距离), Nature 风格, 仅 .fig
%   智能跳过: 若 task_L_quick_test.mat 已存在且参数匹配, 跳过仿真直接出图
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
fprintf('  task_L_quick_test — L 参数扫描 RMSE 对比\n');
fprintf('  Mrx=16 | ZF | SI-ON (beta=0.1, SIC) | K_stream=2\n');
fprintf('  开始时间: %s\n', char(datetime('now')));

% ==================== 1. 参数 ============================================
L_list     = [64, 128, 256, 512];  % OFDM符号数 (params.K)
n_L        = numel(L_list);
snr_list   = -35:5:15;             % SNR (dB)
n_snr      = numel(snr_list);
n_mc       = 100;                  % 蒙特卡洛次数
Mrx_fixed  = 16;
Mx_fixed   = 4;
My_fixed   = 4;

fprintf('  L=%s | SNR=[%d:%d:%d] (%d点) | MC=%d\n', ...
    mat2str(L_list), snr_list(1), snr_list(2)-snr_list(1), ...
    snr_list(end), n_snr, n_mc);
fprintf('  总估计次数: %d L × %d SNR × %d MC = %d\n', ...
    n_L, n_snr, n_mc, n_L * n_snr * n_mc);
fprintf('═══════════════════════════════════════════════════════════════\n\n');

% ==================== 2. 检查已有数据 ====================================
mat_path = fullfile(pwd, 'task_L_quick_test.mat');
skip_sim = false;
if isfile(mat_path)
    tmp = load(mat_path);
    if isfield(tmp, 'L_list') && isfield(tmp, 'snr_list') && isfield(tmp, 'n_mc')
        if isequal(tmp.L_list(:), L_list(:)) && ...
           isequal(tmp.snr_list(:), snr_list(:)) && ...
           tmp.n_mc == n_mc
            fprintf('>>> 检测到已有数据 (L=%s, SNR匹配), 跳过仿真直接出图 <<<\n\n', mat2str(L_list));
            L_list  = tmp.L_list;
            snr_list = tmp.snr_list;
            n_mc    = tmp.n_mc;
            n_L     = numel(L_list);
            n_snr   = numel(snr_list);
            rmse_R_med     = tmp.rmse_R_med;
            rmse_theta_med = tmp.rmse_theta_med;
            rmse_v_med     = tmp.rmse_v_med;
            rmse_R_all     = tmp.rmse_R_all;
            rmse_theta_all = tmp.rmse_theta_all;
            rmse_v_all     = tmp.rmse_v_all;
            skip_sim = true;
        else
            fprintf('>>> 已有数据参数不匹配, 将重新仿真 <<<\n');
            fprintf('    文件: L=%s, SNR=%s\n', mat2str(tmp.L_list), mat2str(tmp.snr_list));
            fprintf('    脚本: L=%s, SNR=%s\n\n', mat2str(L_list), mat2str(snr_list));
        end
    end
    clear tmp;
end

% ==================== 3. 基础参数 (仅仿真需要) ============================
if ~skip_sim
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

    % 预分配
    rmse_R_all     = NaN(n_L, n_snr, n_mc);
    rmse_theta_all = NaN(n_L, n_snr, n_mc);
    rmse_v_all     = NaN(n_L, n_snr, n_mc);

    % 预生成种子 (可复现)
    rng(20260728);
    rng_seeds = randi(2^31-1, n_L, n_snr, n_mc);

    % ==================== 4. 主仿真 ==========================================
    for L_i = 1:n_L
        K_val = L_list(L_i);
        fprintf('\n==== L=%d (K=%d) ====\n', K_val, K_val);

        p_L = baseParams;
        p_L.K = K_val;
        p_L.fast_estimator.n_samp_l = min(64, max(8, floor(K_val/2)));

        % SI 信道 (固定 Mrx)
        hsi_cfg = struct( ...
            'model','ura_rician', 'Nt_total',Nt_total, 'Nr_total',Nr_fixed, ...
            'kappa_SI',10, 'Ntx',baseParams.Ntx, 'Nty',baseParams.Nty, ...
            'Mx',Mx_fixed, 'My',My_fixed, 'd_lambda',0.5, ...
            'theta_tx_deg',baseParams.theta_SI, 'phi_tx_deg',baseParams.phi_SI, ...
            'theta_rx_deg',baseParams.theta_SI, 'phi_rx_deg',baseParams.phi_SI);
        p_L.H_SI_matrix = generate_HSI(hsi_cfg);

        hsi_cfg_tx = struct( ...
            'model','ura_rician', 'Nt_total',Nt_total, 'Nr_total',64, ...
            'kappa_SI',10, 'Ntx',baseParams.Ntx, 'Nty',baseParams.Nty, ...
            'Mx',8, 'My',8, 'd_lambda',0.5, ...
            'theta_tx_deg',baseParams.theta_SI, 'phi_tx_deg',baseParams.phi_SI, ...
            'theta_rx_deg',baseParams.theta_SI, 'phi_rx_deg',baseParams.phi_SI);
        p_L.H_SI = generate_HSI(hsi_cfg_tx);

        fprintf('  生成 TX 波形 (L=%d)...\n', K_val);
        tx = generate_mimo_ofdm_waveform(p_L);
        X_tx = tx.X;
        clear tx;
        fprintf('  TX: [%d×%d×%d×%d]\n', size(X_tx,1), size(X_tx,2), size(X_tx,3), size(X_tx,4));

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
                    fprintf('x');
                    clear rxCube th ph R_est v_est cmp;
                end

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

    % 汇总
    rmse_R_med     = median(rmse_R_all, 3, 'omitnan');
    rmse_theta_med = median(rmse_theta_all, 3, 'omitnan');
    rmse_v_med     = median(rmse_v_all, 3, 'omitnan');

    % 保存数据
    save(mat_path, ...
        'snr_list', 'L_list', 'n_mc', ...
        'rmse_R_med', 'rmse_theta_med', 'rmse_v_med', ...
        'rmse_R_all', 'rmse_theta_all', 'rmse_v_all');
    fprintf('\n数据已保存: %s\n', mat_path);
end

% ==================== 5. 打印汇总 ==========================================
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
    for li = 1:n_L, fprintf('  L=%-5d', L_list(li)); end
    fprintf('\n');
    for si = 1:n_snr
        fprintf('%+8d', snr_list(si));
        for li = 1:n_L, fprintf('  %7.2f', data(li,si)); end
        fprintf('\n');
    end
end

% ==================== 6. 出图 (Nature 风格, semilogy, 仅 .fig) =============
fprintf('\n--- 出图 (Nature 风格, semilogy) ---\n');

all_colors = {[0.902 0.294 0.208], [0.302 0.733 0.835], ...
              [0.000 0.447 0.741], [0.494 0.184 0.556], ...
              [0.929 0.694 0.125], [0.850 0.325 0.098]};
all_markers  = {'o', 's', '^', 'd', 'v', '>'};
all_styles   = {'-', '--', '-.', ':', '-', '--'};
colors    = all_colors(1:n_L);
markers   = all_markers(1:n_L);
linestyle = all_styles(1:n_L);
leg_str   = arrayfun(@(L) sprintf('L=%d', L), L_list, 'UniformOutput', false);

titles  = {'Angle', 'Velocity', 'Range'};
ylabels = {'Angle RMSE (deg)', 'Velocity RMSE (m/s)', 'Range RMSE (m)'};
datas   = {rmse_theta_med, rmse_v_med, rmse_R_med};
fnames  = {'angle', 'velocity', 'range'};

fig_dir = fullfile(pwd, 'fig');
if ~exist(fig_dir, 'dir'), mkdir(fig_dir); end

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
    title_str = sprintf('%s RMSE vs SNR  (L=%s, SI-ON)', titles{fi}, ...
        strjoin(arrayfun(@num2str, L_list, 'UniformOutput', false), '/'));
    title(title_str, ...
        'FontName', 'Times New Roman', 'FontSize', 10, 'FontWeight', 'normal');
    legend(leg_str, 'Location', 'northeast', 'Box', 'on', ...
        'FontName', 'Times New Roman', 'FontSize', 8);
    xlim([snr_list(1)-2, snr_list(end)+2]);

    apply_nature_axes(gca);
    set(gca, 'YScale', 'log');

    fig_path = fullfile(fig_dir, sprintf('fig_L_test_%s_semilogy.fig', fnames{fi}));
    savefig(fig, fig_path);
    fprintf('  %s → fig/\n', fnames{fi});
end

% ==================== 7. Toast 通知 ========================================
toast_script = fullfile(pwd, 'toast_notify.py');
if isfile(toast_script)
    try
        cmd = sprintf('python "%s" "L-test完成" "L=%s, %.1fmin"', ...
            toast_script, mat2str(L_list), toc(t_all)/60);
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
