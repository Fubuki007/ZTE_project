% =========================================================================
% task_execution_time_zf_null_sic_full.m
%   端到端执行时间对比：ZF / Null-space / Null-space + digital SIC
%   计时范围：
%     generate_mimo_ofdm_waveform + simulate_radar_channel_3d
%     + joint_estimator_fast
%   参数与原始执行时间脚本一致，MC 默认 10。
% =========================================================================
function task_execution_time_zf_null_sic_full()
t_all = tic;
warning('off','all');

methods       = {'zf', 'nullspace', 'nullspace'};
sic_flags     = [false, false, true];
method_labels = {'ZF', 'Null-space', 'Null-space + digital SIC'};
n_methods     = numel(methods);

Ns_list = [512, 1024, 2048, 3168, 6336];
L_list  = [16, 32, 64, 128, 256];
fixed_L_for_Ns = 64;
fixed_Ns_for_L = 3168;
Mx_val = 4; My_val = 4;
beta_SI = 10;
SNR_fixed = 0;
n_mc = 10;

fprintf('=== End-to-end execution time sweep ===\n');
fprintf('Ns=%s | L=%s | MC=%d | Mrx=%d | beta_SI=%g\n', ...
    mat2str(Ns_list), mat2str(L_list), n_mc, Mx_val*My_val, beta_SI);

baseParams = build_default_params();
baseParams.theta_true = [24.63, 15.94];
baseParams.phi_true   = [30.99, 13.58];
baseParams.R_true     = [200.6, 210.4];
baseParams.v_true     = [15.1, -5.4];
baseParams.alpha      = [1.0, 0.8];
baseParams.enable_SI  = true;
baseParams.beta_SI    = beta_SI;
baseParams.enable_SIC = false;
baseParams.sic_use_true_channel = false;
baseParams.SIC_pilot_len = 128;
baseParams.SNR        = SNR_fixed;
baseParams.K_stream   = 2;
baseParams.user_theta_rad = deg2rad(baseParams.theta_true(:));
baseParams.user_phi_rad   = deg2rad(baseParams.phi_true(:));
baseParams.Mx = Mx_val;
baseParams.My = My_val;
baseParams.joint_fft_3d.Na_x = Mx_val;
baseParams.joint_fft_3d.Na_y = My_val;
baseParams.fast_estimator.R_max_gate = 600;

Nt_total = baseParams.Ntx * baseParams.Nty;
Nr_total = Mx_val * My_val;

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
ns_seeds = randi(2^31-1, n_methods, numel(Ns_list), n_mc);
l_seeds  = randi(2^31-1, n_methods, numel(L_list), n_mc);

time_ns = NaN(n_methods, numel(Ns_list), n_mc);
time_L  = NaN(n_methods, numel(L_list), n_mc);

for mi = 1:n_methods
    for ni = 1:numel(Ns_list)
        p = configure_dimensions(baseParams, Ns_list(ni), fixed_L_for_Ns);
        p.precoder_type = methods{mi};
        p.H_SI = H_SI;
        p.H_SI_matrix = H_SI;
        p.enable_SIC = sic_flags(mi);
        fprintf('  %s Ns=%4d ... ', method_labels{mi}, Ns_list(ni));
        for mc = 1:n_mc
            rng(ns_seeds(mi, ni, mc));
            time_ns(mi, ni, mc) = local_end_to_end(p);
            if mod(mc,5)==0, fprintf('.'); end
        end
        fprintf(' mean %.4f s\n', mean(time_ns(mi,ni,:),'omitnan'));
    end
end

for mi = 1:n_methods
    for li = 1:numel(L_list)
        p = configure_dimensions(baseParams, fixed_Ns_for_L, L_list(li));
        p.precoder_type = methods{mi};
        p.H_SI = H_SI;
        p.H_SI_matrix = H_SI;
        p.enable_SIC = sic_flags(mi);
        fprintf('  %s L=%3d ... ', method_labels{mi}, L_list(li));
        for mc = 1:n_mc
            rng(l_seeds(mi, li, mc));
            time_L(mi, li, mc) = local_end_to_end(p);
            if mod(mc,5)==0, fprintf('.'); end
        end
        fprintf(' mean %.4f s\n', mean(time_L(mi,li,:),'omitnan'));
    end
end

time_ns_mean = squeeze(mean(time_ns,3,'omitnan'));
time_L_mean  = squeeze(mean(time_L,3,'omitnan'));

save(fullfile(pwd, 'task_execution_time_zf_null_sic_full.mat'), ...
    'Ns_list','L_list','method_labels','n_mc','Mx_val','My_val', ...
    'time_ns','time_L','time_ns_mean','time_L_mean');

% 出图
fig_dir = fullfile(pwd, 'fig');
if ~exist(fig_dir,'dir'), mkdir(fig_dir); end
plot_exec_time(Ns_list, time_ns_mean, 'The number of subcarriers', ...
    'Impact of the number of subcarriers', ...
    fullfile(fig_dir, 'execution_time_vs_subcarriers_zf_null_sic_full'));
plot_exec_time(L_list, time_L_mean, 'CPI length', ...
    'Impact of CPI length', ...
    fullfile(fig_dir, 'execution_time_vs_cpi_length_zf_null_sic_full'));

fprintf('\nDone. 总耗时 %.1f min\n', toc(t_all)/60);
end

function p = configure_dimensions(base, Ns, L)
p = base;
p.N = Ns;
p.B = Ns * 120e3;
p.K = L;
p.meta.delta_f = p.B / p.N;
p.meta.range_resolution = p.c / (2 * p.B);
p.meta.R_max = p.c / (2 * p.meta.delta_f);
p.joint_fft_3d.Nr = Ns;
p.joint_fft_3d.Nv = L;
p.fast_estimator.n_samp_r = min(256, Ns);
p.fast_estimator.n_samp_l = min(64, max(16, floor(L / 2)));
p.fast_estimator.n_pad_v = L;
end

function t = local_end_to_end(p)
timer_id = tic;
tx = generate_mimo_ofdm_waveform(p);
X_tx = tx.X;
clear tx;
rx_cube = simulate_radar_channel_3d(X_tx, p);
joint_estimator_fast(rx_cube, X_tx, p);
clear X_tx rx_cube;
t = toc(timer_id);
end

function plot_exec_time(x, y_mat, x_label, title_str, base_path)
fig = figure('Color','w','Units','inches','Position',[1 1 4.3 3.35], ...
    'PaperPositionMode','auto','Visible','off','Name',title_str);
ax = axes('Parent',fig); hold(ax,'on');
colors = {[0.902 0.294 0.208], [0.302 0.733 0.835], [0.200 0.627 0.173]};
markers = {'o','s','^'};
lines = {'-','--','-.'};
labels = {'ZF', 'Null-space', 'Null-space + digital SIC'};
for k=1:size(y_mat,1)
    loglog(ax, x, max(y_mat(k,:),1e-12), ...
        'Color',colors{k},'Marker',markers{k},'LineStyle',lines{k}, ...
        'LineWidth',1.35,'MarkerSize',5.2,'MarkerFaceColor','w', ...
        'DisplayName',labels{k});
end
xlabel(ax,x_label); ylabel(ax,'Execution time per estimation (s)');
title(ax,title_str);
legend(ax,labels,'Location','northwest','Box','on');
xticks(ax,x); xticklabels(ax,compose('%g',x));
xlim(ax,[min(x)*0.92,max(x)*1.08]);
apply_nature_axes(ax); hold(ax,'off');
savefig(fig,[base_path '.fig']);
exportgraphics(fig,[base_path '.png'],'Resolution',300);
print(fig,[base_path '.eps'],'-depsc2','-r300');
close(fig);
fprintf('  saved: %s.fig/.png/.eps\n', base_path);
end
