% =========================================================================
% task_si_suppression_nullspace_sic_full_v2.m
%   修正版：每个 MC 重新生成一次发射波形（数据符号），避免强 SI 下
%   固定波形导致 Null-space 结果由单个随机数据实现决定。
%
%   三条曲线：Null-space / Null-space + digital SIC / ZF（先跑 Null-space）
%   参数：SNR=-60:5:25, MC=5, L=256, Mrx=64, beta_SI=100
% =========================================================================
function task_si_suppression_nullspace_sic_full_v2()
t_all = tic;
warning('off','all');

log_path = fullfile(pwd, 'task_si_suppression_nullspace_sic_full_v2.log');
if isfile(log_path), delete(log_path); end
diary(log_path); diary on;

methods       = {'nullspace', 'nullspace', 'zf'};
sic_flags     = [false, true, false];
method_labels = {'Null-space', 'Null-space + digital SIC', 'ZF'};
n_methods     = numel(methods);

snr_list = -60:5:25;
n_snr    = numel(snr_list);
n_mc     = 5;             % MC 小一点，因为每个 MC 都会重新生成波形

L_val       = 256;
Mrx_fixed   = 64;
Mx_fixed    = 8;
My_fixed    = 8;
beta_SI_val = 100;

fprintf('=== Nullspace+SIC full v2 ===\n');
fprintf('Methods: %s\n', strjoin(method_labels, ' | '));
fprintf('SNR=[%d:%d:%d] | MC=%d | L=%d | Mrx=%d | beta_SI=%g\n', ...
    snr_list(1), snr_list(2)-snr_list(1), snr_list(end), ...
    n_mc, L_val, Mrx_fixed, beta_SI_val);
fprintf('每个 MC 重新生成发射波形（平均掉通信符号随机性）\n');

rng(20260730);
rng_seeds = randi(2^31-1, n_methods, n_snr, n_mc);

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
baseParams.SIC_pilot_len = 128;
baseParams.K          = L_val;
baseParams.K_stream   = 2;
baseParams.user_theta_rad = deg2rad(baseParams.theta_true(:));
baseParams.user_phi_rad   = deg2rad(baseParams.phi_true(:));
baseParams.Mx = Mx_fixed;
baseParams.My = My_fixed;
baseParams.joint_fft_3d.Na_x = Mx_fixed;
baseParams.joint_fft_3d.Na_y = My_fixed;
baseParams.fast_estimator.n_samp_l = min(64, max(8, floor(L_val/2)));
baseParams.fast_estimator.R_max_gate = 600;

Nt_total = baseParams.Ntx * baseParams.Nty;
Nr_fixed = Mx_fixed * My_fixed;

rng(20260731);
hsi_cfg_rx = struct( ...
    'model','ura_rician', 'Nt_total',Nt_total, 'Nr_total',Nr_fixed, ...
    'kappa_SI',10, 'Ntx',baseParams.Ntx, 'Nty',baseParams.Nty, ...
    'Mx',Mx_fixed, 'My',My_fixed, 'd_lambda',0.5, ...
    'theta_tx_deg',baseParams.theta_SI, 'phi_tx_deg',baseParams.phi_SI, ...
    'theta_rx_deg',baseParams.theta_SI, 'phi_rx_deg',baseParams.phi_SI, ...
    'seed', 20260731);
H_SI = generate_HSI(hsi_cfg_rx);

use_par = license('test', 'Distrib_Computing_Toolbox') && exist('parpool', 'file') == 2;
if use_par
    try
        n_workers = min(4, max(2, feature('numcores')));
        if isempty(gcp('nocreate'))
            parpool('Processes', n_workers);
        end
        fprintf('Parallel: parfor %d workers\n', n_workers);
    catch
        use_par = false;
    end
end

rmse_R_all     = NaN(n_methods, n_snr, n_mc);
rmse_theta_all = NaN(n_methods, n_snr, n_mc);
rmse_v_all     = NaN(n_methods, n_snr, n_mc);

for mi = 1:n_methods
    p_tx = baseParams;
    p_tx.precoder_type = methods{mi};
    p_tx.H_SI = H_SI;
    p_tx.H_SI_matrix = H_SI;

    fprintf('\n==== Method %d/%d: %s ====\n', mi, n_methods, method_labels{mi});
    for si = 1:n_snr
        snr_val = snr_list(si);
        p = p_tx;
        p.SNR = snr_val;
        p.enable_SI = true;
        p.enable_SIC = sic_flags(mi);
        p.H_SI_matrix = H_SI;
        p.beta_SI = beta_SI_val;

        fprintf('  [SNR %+4d dB] (%d/%d) ', snr_val, si, n_snr);
        if use_par
            parfor mc_i = 1:n_mc
                res = local_mc_rmse_full(rng_seeds(mi, si, mc_i), p);
                rmse_R_all(mi, si, mc_i)     = res(1);
                rmse_theta_all(mi, si, mc_i) = res(2);
                rmse_v_all(mi, si, mc_i)     = res(3);
            end
        else
            for mc_i = 1:n_mc
                res = local_mc_rmse_full(rng_seeds(mi, si, mc_i), p);
                rmse_R_all(mi, si, mc_i)     = res(1);
                rmse_theta_all(mi, si, mc_i) = res(2);
                rmse_v_all(mi, si, mc_i)     = res(3);
                if mod(mc_i, 1) == 0, fprintf('.'); end
            end
        end
        fprintf(' | R=%.3f m  th=%.3f deg  v=%.3f m/s | NaN:%d/%d\n', ...
            median(rmse_R_all(mi,si,:),'omitnan'), ...
            median(rmse_theta_all(mi,si,:),'omitnan'), ...
            median(rmse_v_all(mi,si,:),'omitnan'), ...
            sum(isnan(rmse_R_all(mi,si,:))), n_mc);
    end
end

rmse_R_med     = median(rmse_R_all, 3, 'omitnan');
rmse_theta_med = median(rmse_theta_all, 3, 'omitnan');
rmse_v_med     = median(rmse_v_all, 3, 'omitnan');

save(fullfile(pwd, 'task_si_suppression_nullspace_sic_full_v2.mat'), ...
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

fig_dir = fullfile(pwd, 'fig');
if ~exist(fig_dir, 'dir'), mkdir(fig_dir); end
titles  = {'Angle RMSE vs SNR (L = 256, MC = 5, beta=100)', ...
           'Range RMSE vs SNR (L = 256, MC = 5, beta=100)', ...
           'Velocity RMSE vs SNR (L = 256, MC = 5, beta=100)'};
ylabels = {'Angle RMSE (deg)', 'Range RMSE (m)', 'Velocity RMSE (m/s)'};
fnames  = {'angle', 'range', 'velocity'};
datas   = {rmse_theta_med, rmse_R_med, rmse_v_med};
colors  = {[0.302 0.733 0.835], [0.200 0.627 0.173], [0.902 0.294 0.208]};
markers = {'o','s','^'};
lines   = {'--','-.','-'};
for fi = 1:3
    fig = figure('Color','w','Units','pixels','Position',[100+fi*30,140+fi*30,620,470]);
    ax = axes('Parent',fig); hold(ax,'on');
    for mi=1:n_methods
        semilogy(ax, snr_list, max(datas{fi}(mi,:),1e-12), ...
            'Color',colors{mi},'Marker',markers{mi},'LineStyle',lines{mi}, ...
            'LineWidth',1.3,'MarkerSize',5.5,'MarkerFaceColor','w', ...
            'DisplayName',method_labels{mi});
    end
    xlabel(ax,'Input SNR (dB)'); ylabel(ax,ylabels{fi});
    title(ax,titles{fi}); legend(ax,method_labels,'Location','northeast');
    xlim(ax,[snr_list(1)-2,snr_list(end)+2]);
    apply_nature_axes(ax); set(ax,'YScale','log');
    base = fullfile(fig_dir, sprintf('fig_si_suppression_nullspace_sic_%s_v2', fnames{fi}));
    savefig(fig,[base '.fig']); exportgraphics(fig,[base '.png'],'Resolution',300); close(fig);
end

fprintf('\nDone. 总耗时 %.1f min\n', toc(t_all)/60);
diary off;
end

function res = local_mc_rmse_full(seed, p)
rng(seed);
tx = generate_mimo_ofdm_waveform(p);   % 每个 MC 重新生成数据符号
X_tx = tx.X;
rx_cube = simulate_radar_channel_3d(X_tx, p);
[th, ph, R, v, ~] = joint_estimator_fast(rx_cube, X_tx, p);
cmp = evaluate_estimation(th, ph, R, v, p, false);
if isfield(cmp, 'rmse_R') && ~isnan(cmp.rmse_R)
    res = [cmp.rmse_R, cmp.rmse_theta, cmp.rmse_v];
else
    res = [NaN, NaN, NaN];
end
end

