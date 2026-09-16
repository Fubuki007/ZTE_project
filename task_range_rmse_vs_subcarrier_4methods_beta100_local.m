% =========================================================================
% task_range_rmse_vs_subcarrier_4methods_beta100_local.m
% -------------------------------------------------------------------------
% 距离 RMSE vs 子载波数 Ns — 四方法对比
% -------------------------------------------------------------------------
% 四根曲线 (enable_SI=true, beta_SI=100 固定, SNR=0 dB 固定):
%   1. ZF-DFT          无专门 SI 抑制的基准      (precoder='zf',       SIC=off)
%   2. Tx-NS-DFT       仅发射域 Null-Space 抑制  (precoder='nullspace',SIC=off)
%   3. Rx-SIC-DFT      仅接收域 Digital SIC      (precoder='zf',       SIC=on )
%   4. Dual-Domain-DFT Tx Null-Space + Rx SIC    (precoder='nullspace',SIC=on )
%
% 横坐标: 等效子载波数 Ns (对数刻度, 6 点: 512~12672, 12672=4CC聚合全尺寸);
%         子载波间隔固定 120 kHz, 带宽随 Ns 线性增长 B=Ns*120kHz,
%         距离分辨率 Delta R=c/(2B) 随 Ns 提高 (12672 -> 0.099 m).
% 纵坐标: 距离 RMSE (m), 对数轴.
%
% 预期趋势:
%   - 健康方法 (Tx-NS / Rx-SIC / Dual): RMSE 随 Ns 增大近似按 1/Ns 下降
%     (分辨率越细, 抛物线插值越准);
%   - ZF-DFT (beta_SI=100, 无抑制): 检测层被 SI 打崩, 全 Ns 范围高 RMSE.
%
% 其余配置与 SNR 扫描脚本一致:
%   接收阵列 8x8 (Mrx=64), 发射阵列 4x4 (Nt=16), OFDM 符号 L=256, 目标 Q=2
%   H_SI 64x16 (ura_rician, kappa=10, seed=20260731), beta_SI=100
%   门限: R_min_gate=20 m, R_max_gate=600 m
%
% 本地版: n_mc=4, 约 12~15 分钟 (96 次估计); 服务器版 n_mc=50, 约 2.5~3 小时
% 冒烟模式 (约 3 分钟): task_range_rmse_vs_subcarrier_4methods_beta100_local(true)
%
% 运行 (在项目根目录):
%   matlab -batch "task_range_rmse_vs_subcarrier_4methods_beta100_local"         % 正常
%   matlab -batch "task_range_rmse_vs_subcarrier_4methods_beta100_local(true)"   % 冒烟
%
% 输出 (均在项目根目录):
%   task_range_rmse_vs_subcarrier_4methods_beta100.mat / .csv / .log / _checkpoint.mat
%   fig/fig_range_rmse_vs_subcarrier_4methods_beta100.fig/.png/.eps
% -------------------------------------------------------------------------
% =========================================================================
function task_range_rmse_vs_subcarrier_4methods_beta100_local(smoke_test)
if nargin < 1 || isempty(smoke_test), smoke_test = false; end
close all; clc; warning('off','all');
t_all = tic;

% ==================== 0. 路径 + 日志 =======================================
script_dir = fileparts(mfilename('fullpath'));
if isempty(script_dir), script_dir = pwd; end
addpath(script_dir);                       % 项目根 (design_precoder 等)
func_dir = fullfile(script_dir, 'server_run_si_sweep');
if isfolder(func_dir)
    addpath(func_dir);                     % 置顶: 遮蔽根目录同名旧拷贝
end

% ★ 版本自检: 必须用 server_run_si_sweep 里带 R_max_gate 的估计器
jfile = which('joint_estimator_fast');
if isempty(jfile)
    error('找不到 joint_estimator_fast');
end
if ~contains(fileread(jfile), 'R_max_gate')
    error('joint_estimator_fast 版本过旧 (无 R_max_gate): %s', jfile);
end

% ★ 严格串行: 关掉任何残留 parpool (全尺寸 rx_cube ~3.3 GB/次, 并行必爆内存)
if ~isempty(gcp('nocreate')), delete(gcp('nocreate')); end

mode_tag   = '_local';
mode_label = '本地预览';
if smoke_test, mode_tag = '_local_smoke'; mode_label = '本地冒烟'; end
log_path = fullfile(script_dir, ['task_range_rmse_vs_subcarrier_4methods_beta100' mode_tag '.log']);
if isfile(log_path), delete(log_path); end
diary(log_path); diary on;

% ==================== 1. 配置 ==============================================
L_val       = 256;                 % OFDM 符号数
Mx_val      = 8;  My_val = 8;      % 接收阵列 8x8 -> Mrx=64
K_stream    = 2;                   % 通信用户/空间流数

beta_SI_val   = 100;                 % SI 强度固定 (相对目标幅度)
snr_fixed     = 0;                   % 输入 SNR 固定 (dB)
delta_f_fixed = 120e3;               % 子载波间隔固定 (3GPP FR2 mu=3)

if smoke_test
    Ns_list = [1024, 3168, 12672];    % 冒烟: 3 点
    n_mc    = 1;
else
    Ns_list = [512, 1024, 2048, 3168, 6336, 12672];   % 完整: 6 点
    n_mc    = 4;
end
n_ns = numel(Ns_list);
n_sweep = n_ns;

methods = struct( ...
    'tag',      {'ZF-DFT', 'Tx-NS-DFT', 'Rx-SIC-DFT', 'Dual-Domain-DFT'}, ...
    'label',    {'ZF-DFT (no SI suppression)', ...
                 'Tx-NS-DFT (Tx null-space only)', ...
                 'Rx-SIC-DFT (Rx digital SIC only)', ...
                 'Dual-Domain-DFT (Tx NS + Rx SIC)'}, ...
    'precoder', {'zf', 'nullspace', 'zf', 'nullspace'}, ...
    'use_sic',  {false, false, true, true});
n_methods = numel(methods);
method_tags = {methods.tag};

% ==================== 2. 基础参数 =========================================
baseParams = build_default_params();
baseParams.theta_true = [24.63, 15.94];
baseParams.phi_true   = [30.99, 13.58];
baseParams.R_true     = [200.6, 210.4];
baseParams.v_true     = [15.1, -5.4];
baseParams.alpha      = [1.0, 0.8];
baseParams.enable_SI  = true;
baseParams.enable_SIC = false;
baseParams.K          = L_val;
baseParams.K_stream   = K_stream;
baseParams.user_theta_rad = deg2rad(baseParams.theta_true(:));
baseParams.user_phi_rad   = deg2rad(baseParams.phi_true(:));
baseParams.Mx = Mx_val;
baseParams.My = My_val;
baseParams.joint_fft_3d.Na_x = Mx_val;
baseParams.joint_fft_3d.Na_y = My_val;
baseParams.fast_estimator.n_samp_l = min(64, max(8, floor(L_val/2)));
baseParams.fast_estimator.n_pad_v  = L_val;    % 多普勒不补零 (省内存)
baseParams.fast_estimator.R_min_gate = 20;     % 滤近距假峰
baseParams.fast_estimator.R_max_gate = 600;    % 滤 SI 的 DC 相干峰 (1250 m)
baseParams.SNR        = snr_fixed;
baseParams.beta_SI    = beta_SI_val;

Nt_total = baseParams.Ntx * baseParams.Nty;
Nr_total = Mx_val * My_val;

% ==================== 3. H_SI (64x16, 固定种子保证可复现) ================
rng(20260731);
hsi_cfg = struct( ...
    'model','ura_rician', 'Nt_total',Nt_total, 'Nr_total',Nr_total, ...
    'kappa_SI',10, 'Ntx',baseParams.Ntx, 'Nty',baseParams.Nty, ...
    'Mx',Mx_val, 'My',My_val, 'd_lambda',0.5, ...
    'theta_tx_deg',baseParams.theta_SI, 'phi_tx_deg',baseParams.phi_SI, ...
    'theta_rx_deg',baseParams.theta_SI, 'phi_rx_deg',baseParams.phi_SI, ...
    'seed', 20260731);
H_SI = generate_HSI(hsi_cfg);       % 64 x 16

% ==================== 4. 预生成随机种子 (可复现) =========================
rng(20260801);
rng_seeds = randi(2^31-1, n_methods, n_sweep, n_mc);

% ==================== 5. 打印参数核对 ======================================
n_trials = n_methods * n_sweep * n_mc;
fprintf('═══════════════════════════════════════════════════════════════\n');
fprintf('  距离 RMSE vs 子载波数 — 四方法对比 (%s)\n', mode_label);
fprintf('  开始时间: %s\n', char(datetime('now')));
fprintf('═══════════════════════════════════════════════════════════════\n');
fprintf('  方法: %s\n', strjoin({methods.label}, ' | '));
fprintf('  阵列: 接收 %dx%d (Mrx=%d), 发射 %dx%d (Nt=%d)\n', ...
    Mx_val, My_val, Nr_total, baseParams.Ntx, baseParams.Nty, Nt_total);
fprintf('  子载波扫描: Ns = %s (%d 点)\n', mat2str(Ns_list), n_ns);
fprintf('  固定: SNR=%+d dB, beta_SI=%g\n', snr_fixed, beta_SI_val);
fprintf('  符号: L=%d, 目标数: Q=%d\n', L_val, baseParams.num_targets);
fprintf('  SI: enable=%d, H_SI %dx%d (kappa=%d, seed=%d)\n', ...
    baseParams.enable_SI, size(H_SI,1), size(H_SI,2), ...
    hsi_cfg.kappa_SI, hsi_cfg.seed);
fprintf('  门限: R_min_gate=20 m, R_max_gate=600 m\n');
fprintf('  总估计次数: %d 方法 x %d 扫描点 x %d MC = %d\n', ...
    n_methods, n_sweep, n_mc, n_trials);
fprintf('  运行模式: 严格串行 (无 parfor)\n');
est_sec = n_methods * n_mc * sum(Ns_list/12672 * 22);   % Ns 越小单次越快
fprintf('  预估耗时: ~%.1f 小时 (全尺寸 12672 子载波按 ~22 s/次)\n', est_sec/3600);
fprintf('═══════════════════════════════════════════════════════════════\n\n');

% ==================== 6. 结果数组 + 断点续跑 ==============================
rmse_R     = NaN(n_methods, n_sweep, n_mc);
rmse_theta = NaN(n_methods, n_sweep, n_mc);
rmse_v     = NaN(n_methods, n_sweep, n_mc);
done_mask  = false(n_methods, n_sweep, n_mc);

ckpt_path = fullfile(script_dir, ['task_range_rmse_vs_subcarrier_4methods_beta100' mode_tag '_checkpoint.mat']);
if isfile(ckpt_path)
    tmp = load(ckpt_path);
    ok = isfield(tmp,'rmse_R') && isfield(tmp,'done_mask') && ...
         isfield(tmp,'Ns_list') && isfield(tmp,'snr_fixed') && ...
         isfield(tmp,'beta_SI_val') && isfield(tmp,'method_tags') && ...
         isequal(size(tmp.rmse_R), [n_methods n_ns n_mc]) && ...
         isequal(tmp.Ns_list(:), Ns_list(:)) && ...
         tmp.snr_fixed == snr_fixed && ...
         tmp.beta_SI_val == beta_SI_val && ...
         isequal(tmp.method_tags, method_tags);
    if ok
        rmse_R     = tmp.rmse_R;
        rmse_theta = tmp.rmse_theta;
        rmse_v     = tmp.rmse_v;
        done_mask  = tmp.done_mask;
        fprintf('Checkpoint 已加载: %d/%d 次估计已完成, 断点续跑.\n\n', ...
            sum(done_mask(:)), numel(done_mask));
    else
        fprintf('Checkpoint 与当前配置不一致, 重新开始.\n\n');
    end
    clear tmp;
end

fig_dir = fullfile(script_dir, 'fig');
if ~exist(fig_dir, 'dir'), mkdir(fig_dir); end

% ==================== 7. 主循环: 方法 -> 扫描点 -> MC =====================
n_done0 = sum(done_mask(:));
for mi = 1:n_methods
    m = methods(mi);
    fprintf('\n==== 方法 %d/%d: %s ====\n', mi, n_methods, m.label);

    for ni = 1:n_ns
        Ns_val = Ns_list(ni);
        if all(squeeze(done_mask(mi, ni, :)))
            fprintf('  [%s Ns=%d] 已完成, 跳过\n', m.tag, Ns_val);
            continue;
        end

        % ---- 波形随 Ns 变化, 每个 (方法, Ns) 组合重新生成一次 ----
        p_tx = baseParams;
        p_tx.precoder_type = m.precoder;
        p_tx.enable_SIC    = m.use_sic;
        p_tx.H_SI          = H_SI;        % 预编码器用
        p_tx.H_SI_matrix   = H_SI;        % 回波模拟 / 数字 SIC 用
        p_tx.N             = Ns_val;
        p_tx.B             = Ns_val * delta_f_fixed;   % 子载波间隔固定 120 kHz
        p_tx.meta.range_resolution = p_tx.c / (2 * p_tx.B);
        p_tx.meta.R_max            = p_tx.c / (2 * delta_f_fixed);
        p_tx.joint_fft_3d.Nr       = Ns_val;
        rng(20260730 + mi*100 + ni);
        tx = generate_mimo_ofdm_waveform(p_tx);
        X_tx = tx.X;                % [Ntx, Nty, Ns, L]
        fprintf('  TX: [%dx%dx%dx%d], B=%.2f MHz, si_leak=%.4g, comm_err=%.3g\n', ...
            size(X_tx,1), size(X_tx,2), size(X_tx,3), size(X_tx,4), ...
            p_tx.B/1e6, tx.precoder_info.si_leak_avg, ...
            tx.precoder_info.comm_err_avg);
        clear tx;

        p = p_tx;
        p.SNR = snr_fixed;

        fprintf('  [%s Ns=%d] (Ns %d/%d) ', m.tag, Ns_val, ni, n_ns);
        t_blk = tic;
        for mc_i = 1:n_mc
            if done_mask(mi, ni, mc_i), continue; end
            rng(rng_seeds(mi, ni, mc_i));
            try
                rxCube = simulate_radar_channel_3d(X_tx, p);
                [th, ph, R_est, v_est, ~] = joint_estimator_fast(rxCube, X_tx, p);
                cmp = evaluate_estimation(th, ph, R_est, v_est, p, false);
                if isfield(cmp, 'rmse_R') && ~isnan(cmp.rmse_R)
                    rmse_R(mi, ni, mc_i)     = cmp.rmse_R;
                    rmse_theta(mi, ni, mc_i) = cmp.rmse_theta;
                    rmse_v(mi, ni, mc_i)     = cmp.rmse_v;
                end
            catch
                fprintf('x');
            end
            done_mask(mi, ni, mc_i) = true;
            clear rxCube th ph R_est v_est cmp;
            if mod(mc_i, 10) == 0, fprintf('.'); end

            % 断点保存 (每个 MC 一次, 文件很小, 崩溃后可续跑)
            save(ckpt_path, 'rmse_R','rmse_theta','rmse_v','done_mask', ...
                'Ns_list','snr_fixed','beta_SI_val','method_tags','mi','ni');
        end

        el = toc(t_blk);
        eta_str = '';

        fprintf(' | med R=%.4f m (NaN %d/%d) | %s | %s\n', ...
            median(rmse_R(mi, ni, :), 'omitnan'), ...
            sum(isnan(rmse_R(mi, ni, :))), n_mc, ...
            datestr(seconds(round(el)), 'MM:SS'), eta_str);
        clear X_tx;
    end
end

% ==================== 8. 汇总 + 保存 =======================================
rmse_R_med     = median(rmse_R, 3, 'omitnan');
rmse_theta_med = median(rmse_theta, 3, 'omitnan');
rmse_v_med     = median(rmse_v, 3, 'omitnan');

fprintf('\n═══════════════════════════════════════════════════════════════\n');
fprintf('  距离 RMSE (m) 摘要 (median over %d MC)\n', n_mc);
fprintf('═══════════════════════════════════════════════════════════════\n');
fprintf('%8s', 'Ns');
for mi = 1:n_methods, fprintf('  %-16s', methods(mi).tag); end
fprintf('\n');
for ni = 1:n_ns
    fprintf('%8d', Ns_list(ni));
    for mi = 1:n_methods, fprintf('  %16.4f', rmse_R_med(mi, ni)); end
    fprintf('\n');
end

results = struct();
results.Ns_list       = Ns_list;
results.snr_fixed     = snr_fixed;
results.beta_SI       = beta_SI_val;
results.method_tags    = {methods.tag};
results.method_labels  = {methods.label};
results.n_mc           = n_mc;
results.enable_SI      = true;
results.rmse_R         = rmse_R;
results.rmse_theta     = rmse_theta;
results.rmse_v         = rmse_v;
results.rmse_R_med     = rmse_R_med;
results.rmse_theta_med = rmse_theta_med;
results.rmse_v_med     = rmse_v_med;
results.params_summary = struct( ...
    'Nt', Nt_total, 'Mrx', Nr_total, 'Ns_max', baseParams.N, 'L', L_val, ...
    'B_MHz', baseParams.B/1e6, 'n_cc', baseParams.meta.n_cc, ...
    'Rmax', baseParams.meta.R_max, ...
    'range_resolution', baseParams.meta.range_resolution, ...
    'Ts_us', baseParams.Ts*1e6, 'fc_GHz', baseParams.fc/1e9);
results.total_runtime_min = toc(t_all)/60;

mat_path = fullfile(script_dir, ['task_range_rmse_vs_subcarrier_4methods_beta100' mode_tag '.mat']);
save(mat_path, '-struct', 'results');
fprintf('\n数据已保存: %s\n', mat_path);

% CSV
csv_path = fullfile(script_dir, ['task_range_rmse_vs_subcarrier_4methods_beta100' mode_tag '.csv']);
fid = fopen(csv_path, 'w');
fprintf(fid, 'Ns,%s\n', strjoin({methods.tag}, ','));
for ni = 1:n_ns
    fprintf(fid, '%d', Ns_list(ni));
    for mi = 1:n_methods
        fprintf(fid, ',%.6e', rmse_R_med(mi, ni));
    end
    fprintf(fid, '\n');
end
fclose(fid);
fprintf('CSV 已保存: %s\n', csv_path);

% ==================== 9. 出图 (Nature 风格, semilogy) ====================
colors  = {[0.80 0.20 0.15], [0.20 0.55 0.25], [0.15 0.40 0.75], ...
           [0.10 0.10 0.10]};
markers = {'o', 's', 'd', '^'};

fig = figure('Color', 'w', 'Units', 'pixels', ...
    'Position', [120, 160, 700, 500]);
hold on;
h = gobjects(n_methods, 1);
x_data = Ns_list;
for mi = 1:n_methods
    h(mi) = semilogy(x_data, max(rmse_R_med(mi, :), 1e-12), '-', ...
        'Color', colors{mi}, 'Marker', markers{mi}, 'LineWidth', 1.5, ...
        'MarkerSize', 6, 'MarkerFaceColor', 'w', ...
        'MarkerIndices', 1:max(1, floor(n_sweep/3)):n_sweep);
end

xlabel('Number of subcarriers N_s', 'FontName', 'Times New Roman', 'FontSize', 11);
ylabel('Range RMSE (m)', 'FontName', 'Times New Roman', 'FontSize', 11);
title(sprintf('Range RMSE vs Subcarriers (SNR = %+d dB, \\beta_{SI} = %g, MC = %d)', ...
    snr_fixed, beta_SI_val, n_mc), 'FontName', 'Times New Roman', 'FontSize', 11, ...
    'FontWeight', 'normal');
legend(h, {methods.label}, 'Location', 'northeastoutside', 'Box', 'off', ...
    'FontName', 'Times New Roman', 'FontSize', 9, 'Interpreter', 'none');
set(gca, 'XScale', 'log');
set(gca, 'XTick', Ns_list);
set(gca, 'XTickLabel', cellstr(num2str(Ns_list(:), '%d')));
xlim([Ns_list(1)*0.8, Ns_list(end)*1.25]);

yvals = rmse_R_med(:);
yvals = yvals(~isnan(yvals) & yvals > 0);
if ~isempty(yvals)
    ylo = 10^floor(log10(min(yvals)));
    yhi = 10^ceil(log10(max(yvals)));
    ylim([ylo, yhi]);
    ytick_vals = 10 .^ (floor(log10(ylo)) : ceil(log10(yhi)));
    set(gca, 'YTick', ytick_vals);
    set(gca, 'YTickLabel', ...
        cellfun(@(n) sprintf('10^{%s}', n), ...
        arrayfun(@(v) num2str(log10(v)), ytick_vals, 'UniformOutput', false), ...
        'UniformOutput', false));
end
apply_nature_axes(gca);
set(gca, 'YScale', 'log');

base_path = fullfile(fig_dir, ['fig_range_rmse_vs_subcarrier_4methods_beta100' mode_tag]);
savefig(fig, [base_path '.fig']);
exportgraphics(fig, [base_path '.png'], 'Resolution', 300);
print(fig, [base_path '.eps'], '-depsc2', '-painters');
close(fig);
fprintf('图已保存: %s.fig/.png/.eps\n', base_path);

% ==================== 10. 桌面通知 (仅 Windows) ===========================
if ~isunix
    toast_script = fullfile(script_dir, 'toast_notify.py');
    if isfile(toast_script)
        try
            cmd = sprintf('python "%s" "RMSE-子载波四方法(本地)" "%d方法x%d点x%dMC, %.1fmin"', ...
                toast_script, n_methods, n_sweep, n_mc, toc(t_all)/60);
            system(cmd);
        catch
        end
    end
end

fprintf('\n═══════════════════════════════════════════════════════════════\n');
fprintf('  完成时间: %s\n', char(datetime('now')));
fprintf('  总耗时: %.1f 分钟\n', toc(t_all)/60);
fprintf('  日志: %s\n', log_path);
fprintf('═══════════════════════════════════════════════════════════════\n');
diary off;
end

