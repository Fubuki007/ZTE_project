% =========================================================================
% task_si_strength_zf_null_sic_quick.m
%   SI 强度鲁棒性快速测试：beta_SI = 100 / 1000 / 10000
%   三条曲线：ZF / Null-space / Null-space + digital SIC
%   快速规模：Ns=2048, L=128, Mrx=64, MC=5, SNR=0 dB
% =========================================================================
function task_si_strength_zf_null_sic_quick_beta1_10()
clear; close all; clc; warning('off','all');
t_all = tic;

methods       = {'zf', 'nullspace', 'nullspace'};
sic_flags     = [false, false, true];
method_labels = {'ZF', 'Null-space', 'Null-space + digital SIC'};
n_methods     = numel(methods);

beta_list = [1, 10, 100, 1000, 10000];
n_beta = numel(beta_list);
n_mc = 5;
SNR_fixed = 0;
N_val = 2048;
L_val = 128;
Mx_val = 8; My_val = 8;

fprintf('=== SI strength quick test ===\n');
fprintf('beta_SI = [%s], MC=%d, SNR=%d dB, Ns=%d, L=%d, Mrx=%dx%d\n\n', ...
    num2str(beta_list), n_mc, SNR_fixed, N_val, L_val, Mx_val, My_val);

baseParams = build_default_params();
baseParams.theta_true = [24.63, 15.94];
baseParams.phi_true   = [30.99, 13.58];
baseParams.R_true     = [200.6, 210.4];
baseParams.v_true     = [15.1, -5.4];
baseParams.alpha      = [1.0, 0.8];
baseParams.enable_SI  = true;
baseParams.beta_SI    = 100;   % 循环内覆盖
baseParams.enable_SIC = false;
baseParams.sic_use_true_channel = false;
baseParams.SIC_pilot_len = 128;
baseParams.SNR        = SNR_fixed;
baseParams.K          = L_val;
baseParams.K_stream   = 2;
baseParams.user_theta_rad = deg2rad(baseParams.theta_true(:));
baseParams.user_phi_rad   = deg2rad(baseParams.phi_true(:));
baseParams.Mx = Mx_val;
baseParams.My = My_val;
baseParams.N = N_val;
baseParams.B = N_val * 120e3;
baseParams.joint_fft_3d.Na_x = Mx_val;
baseParams.joint_fft_3d.Na_y = My_val;
baseParams.joint_fft_3d.Nr = N_val;
baseParams.joint_fft_3d.Nv = L_val;
baseParams.fast_estimator.n_samp_l = min(64, max(8, floor(L_val/2)));
baseParams.fast_estimator.n_pad_v = L_val;
baseParams.fast_estimator.R_max_gate = 600;

Nt_total = baseParams.Ntx * baseParams.Nty;
Nr_total = Mx_val * My_val;

% 同一个 64x16 H_SI，预编码设计与注入/SIC 一致
rng(20260731);
hsi_cfg = struct( ...
    'model','ura_rician', 'Nt_total',Nt_total, 'Nr_total',Nr_total, ...
    'kappa_SI',10, 'Ntx',baseParams.Ntx, 'Nty',baseParams.Nty, ...
    'Mx',Mx_val, 'My',My_val, 'd_lambda',0.5, ...
    'theta_tx_deg',baseParams.theta_SI, 'phi_tx_deg',baseParams.phi_SI, ...
    'theta_rx_deg',baseParams.theta_SI, 'phi_rx_deg',baseParams.phi_SI, ...
    'seed', 20260731);
H_SI = generate_HSI(hsi_cfg);

rng(20260801);
rng_seeds = randi(2^31-1, n_methods, n_beta, n_mc);

rmse_R = NaN(n_methods, n_beta, n_mc);
rmse_theta = NaN(n_methods, n_beta, n_mc);
rmse_v = NaN(n_methods, n_beta, n_mc);

for mi = 1:n_methods
    p_tx = baseParams;
    p_tx.precoder_type = methods{mi};
    p_tx.H_SI = H_SI;
    p_tx.H_SI_matrix = H_SI;
    tx = generate_mimo_ofdm_waveform(p_tx);
    X_tx = tx.X;
    fprintf('  [%s] si_leak=%.4g\n', method_labels{mi}, tx.precoder_info.si_leak_avg);
    clear tx;

    for bi = 1:n_beta
        beta_val = beta_list(bi);
        p = p_tx;
        p.beta_SI = beta_val;
        p.enable_SI = true;
        p.enable_SIC = sic_flags(mi);
        p.H_SI_matrix = H_SI;

        fprintf('  %s beta=%d ...\n', method_labels{mi}, beta_val);
        for mc = 1:n_mc
            rng(rng_seeds(mi, bi, mc));
            res = local_mc_rmse_full(rng_seeds(mi, bi, mc), X_tx, p);
            rmse_R(mi, bi, mc)     = res(1);
            rmse_theta(mi, bi, mc) = res(2);
            rmse_v(mi, bi, mc)     = res(3);
        end
        fprintf('    R=%.4f m, th=%.4f deg, v=%.4f m/s\n', ...
            median(rmse_R(mi,bi,:),'omitnan'), ...
            median(rmse_theta(mi,bi,:),'omitnan'), ...
            median(rmse_v(mi,bi,:),'omitnan'));
    end
    clear X_tx;
end

rmse_R_med = median(rmse_R, 3, 'omitnan');
rmse_theta_med = median(rmse_theta, 3, 'omitnan');
rmse_v_med = median(rmse_v, 3, 'omitnan');

fprintf('\n=== Summary (median over MC) ===\n');
fprintf('Angle RMSE:\n');
for bi=1:n_beta
    fprintf(' beta=%6d  ZF=%.4f  NS=%.4f  NS+SIC=%.4f\n', ...
        beta_list(bi), rmse_theta_med(1,bi), rmse_theta_med(2,bi), rmse_theta_med(3,bi));
end
fprintf('Range RMSE:\n');
for bi=1:n_beta
    fprintf(' beta=%6d  ZF=%.4f  NS=%.4f  NS+SIC=%.4f\n', ...
        beta_list(bi), rmse_R_med(1,bi), rmse_R_med(2,bi), rmse_R_med(3,bi));
end
fprintf('Velocity RMSE:\n');
for bi=1:n_beta
    fprintf(' beta=%6d  ZF=%.4f  NS=%.4f  NS+SIC=%.4f\n', ...
        beta_list(bi), rmse_v_med(1,bi), rmse_v_med(2,bi), rmse_v_med(3,bi));
end

save('task_si_strength_zf_null_sic_quick_beta1_10.mat', ...
    'beta_list','method_labels','rmse_R_med','rmse_theta_med','rmse_v_med', ...
    'rmse_R','rmse_theta','rmse_v');

% 出图
fig_dir = fullfile(pwd, 'fig');
if ~exist(fig_dir, 'dir'), mkdir(fig_dir); end
titles = {'Angle RMSE', 'Range RMSE', 'Velocity RMSE'};
ylabs  = {'Angle RMSE (deg)', 'Range RMSE (m)', 'Velocity RMSE (m/s)'};
fnames = {'angle', 'range', 'velocity'};
datas  = {rmse_theta_med, rmse_R_med, rmse_v_med};
colors = {[0.902 0.294 0.208], [0.302 0.733 0.835], [0.200 0.627 0.173]};
markers = {'o','s','^'};
lines = {'-','--','-.'};

for fi=1:3
    fig = figure('Color','w','Units','pixels','Position',[100+fi*30,140+fi*30,620,470]);
    ax = axes('Parent',fig); hold(ax,'on');
    for mi=1:n_methods
        semilogy(ax, beta_list, max(datas{fi}(mi,:),1e-12), ...
            'Color',colors{mi},'Marker',markers{mi},'LineStyle',lines{mi}, ...
            'LineWidth',1.3,'MarkerSize',5.5,'MarkerFaceColor','w', ...
            'DisplayName',method_labels{mi});
    end
    xlabel(ax,'Self-interference strength \beta_{SI} (relative to target)','FontName','Times New Roman','FontSize',10);
    ylabel(ax,ylabs{fi},'FontName','Times New Roman','FontSize',10);
    title(ax,titles{fi},'FontName','Times New Roman','FontSize',10,'FontWeight','normal');
    legend(ax,method_labels,'Location','northeast','Box','on');
    set(ax,'XScale','log'); xlim(ax,[min(beta_list)*0.8,max(beta_list)*1.2]);
    yvals = datas{fi}(:); yvals=yvals(~isnan(yvals)&yvals>0);
    if ~isempty(yvals)
        ylo=10^floor(log10(min(yvals))); yhi=10^ceil(log10(max(yvals)));
        ylim(ax,[ylo,yhi]);
    end
    apply_nature_axes(ax); set(ax,'YScale','log');
    hold(ax,'off');
    base = fullfile(fig_dir, sprintf('fig_si_strength_zf_null_sic_%s_quick_beta1_10', fnames{fi}));
    savefig(fig,[base '.fig']);
    exportgraphics(fig,[base '.png'],'Resolution',300);
    close(fig);
    fprintf('  saved: %s.fig/.png\n', base);
end
fprintf('\n总耗时 %.1f s\n', toc(t_all));
end

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

