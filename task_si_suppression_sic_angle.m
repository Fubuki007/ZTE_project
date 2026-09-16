% =========================================================================
% task_si_suppression_sic_angle.m
% -------------------------------------------------------------------------
% Null-space vs Lagrange, SI-ON + digital SIC-ON, ANGLE-RMSE-ONLY comparison.
%
% This is the SIC-enabled companion of task_si_suppression.m:
%   * ZF is removed
%   * only angle RMSE is recorded / plotted
%   * baseParams.enable_SIC = true
%   * digital SIC uses a pilot-based LS estimate of the SI channel, exactly
%     in the spirit of SIC.m (Y0 = G_eff*X0 + noise, G_hat = Y0/X0)
%
% Outputs
%   task_si_suppression_sic_angle.mat
%   data_si_suppression_sic_ns_lag_angle.csv   (snr, ns_sic_th, lag_sic_th)
%   fig/fig_si_suppression_sic_angle.fig/.png  (standalone new curves)
%
% To overlay the two new curves on the previous polished figure, run:
%   add_sic_angle_to_previous_fig
%
% Important: keep beta_SI and the scenario identical to the previous no-SIC
% figure so that the only difference is enable_SIC=true.
% =========================================================================
clear; close all; clc;
t_all = tic;
warning('off','all');

% ======================= 0. Log ==========================================
log_path = fullfile(pwd, 'task_si_suppression_sic_angle_run.log');
if isfile(log_path), delete(log_path); end
diary(log_path);
diary on;

fprintf('============================================================\n');
fprintf('  Null-space vs Lagrange : SI-ON + digital SIC-ON\n');
fprintf('  Angle RMSE only\n');
fprintf('  Start: %s\n', char(datetime('now')));

% ======================= 1. Config =======================================
methods       = {'nullspace', 'lagrange'};
method_labels = {'Null-space + digital SIC', 'Lagrange + digital SIC'};
n_methods     = numel(methods);

% ---- Choose the grid that matches the figure you want to extend ----------
% fig/angle_rmse_vs_snr_si_suppression.* uses SNR=-60:5:30 and MC=100.
% task_si_suppression.m itself used SNR=-20:5:10 and MC=30.
match_previous_fig = true;
if match_previous_fig
    snr_list = -60:5:30;      % same x-axis as the previous 3-curve figure
    n_mc     = 100;           % same MC as the previous figure title
else
    snr_list = -20:5:10;      % original task_si_suppression grid
    n_mc     = 30;            % original task_si_suppression MC
end
n_snr = numel(snr_list);

L_val       = 256;            % OFDM symbols
Mrx_fixed   = 16;             % receive antennas
Mx_fixed    = 4;
My_fixed    = 4;
beta_SI_val = 10;             % strong SI, same as task_si_suppression.m

fprintf('  Methods: %s\n', strjoin(method_labels, ' | '));
fprintf('  SNR=[%d:%d:%d] (%d pts) | MC=%d | L=%d | Mrx=%d | beta_SI=%g\n', ...
    snr_list(1), snr_list(2)-snr_list(1), snr_list(end), n_snr, ...
    n_mc, L_val, Mrx_fixed, beta_SI_val);
fprintf('  enable_SI=true, enable_SIC=true (pilot LS-estimated H_SI, as in SIC.m)\n');
fprintf('  Total trials: %d methods x %d SNR x %d MC = %d\n', ...
    n_methods, n_snr, n_mc, n_methods*n_snr*n_mc);
fprintf('============================================================\n\n');

% Reproducible MC seeds. Same master seed as task_si_suppression.m.
rng(20260730);
rng_seeds = randi(2^31-1, n_methods, n_snr, n_mc);

% ======================= 2. Base parameters ===============================
fprintf('--- Base parameters ---\n');
baseParams = build_default_params();
baseParams.theta_true = [24.63, 15.94];
baseParams.phi_true   = [30.99, 13.58];
baseParams.R_true     = [200.6, 210.4];
baseParams.v_true     = [15.1, -5.4];
baseParams.alpha      = [1.0, 0.8];
baseParams.enable_SI  = true;       % inject SI
baseParams.beta_SI    = beta_SI_val;
baseParams.enable_SIC = true;       % enable digital SIC (LS-estimated H_SI)
baseParams.sic_use_true_channel = false;  % false = SIC.m-style LS estimate
baseParams.SIC_pilot_len = 64;      % pilot length for SI channel estimation
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
fprintf('  Mrx=%d (%dx%d), Nt=%d, Ns=%d, B=%.1f MHz\n', ...
    Mrx_fixed, Mx_fixed, My_fixed, Nt_total, baseParams.N, baseParams.B/1e6);

% ---- H_SI used by the precoder (64x16) and by SI injection/SIC (16x16) ---
hsi_cfg_tx = struct( ...
    'model','ura_rician', 'Nt_total',Nt_total, 'Nr_total',64, ...
    'kappa_SI',10, 'Ntx',baseParams.Ntx, 'Nty',baseParams.Nty, ...
    'Mx',8, 'My',8, 'd_lambda',0.5, ...
    'theta_tx_deg',baseParams.theta_SI, 'phi_tx_deg',baseParams.phi_SI, ...
    'theta_rx_deg',baseParams.theta_SI, 'phi_rx_deg',baseParams.phi_SI);
H_SI_common = generate_HSI(hsi_cfg_tx);

hsi_cfg_rx = struct( ...
    'model','ura_rician', 'Nt_total',Nt_total, 'Nr_total',Nr_fixed, ...
    'kappa_SI',10, 'Ntx',baseParams.Ntx, 'Nty',baseParams.Nty, ...
    'Mx',Mx_fixed, 'My',My_fixed, 'd_lambda',0.5, ...
    'theta_tx_deg',baseParams.theta_SI, 'phi_tx_deg',baseParams.phi_SI, ...
    'theta_rx_deg',baseParams.theta_SI, 'phi_rx_deg',baseParams.phi_SI);
H_SI_rx = generate_HSI(hsi_cfg_rx);

% ======================= 3. Angle-only result arrays ======================
rmse_theta_all = NaN(n_methods, n_snr, n_mc);

fig_dir = fullfile(pwd, 'fig');
if ~exist(fig_dir, 'dir'), mkdir(fig_dir); end

% ======================= 4. Main loop =====================================
for mi = 1:n_methods
    method = methods{mi};
    fprintf('\n==== Method %d/%d: %s ====\n', mi, n_methods, method_labels{mi});

    % Generate TX waveform once per precoder.
    p_tx = baseParams;
    p_tx.precoder_type = method;
    p_tx.H_SI          = H_SI_common;   % used by precoder design
    p_tx.H_SI_matrix   = H_SI_rx;       % used by SI injection and SIC
    fprintf('  Generating TX waveform (precoder=%s)...\n', method);
    tx = generate_mimo_ofdm_waveform(p_tx);
    X_tx = tx.X;                        % [Ntx, Nty, Ns, L]
    clear tx;
    fprintf('  TX: [%dx%dx%dx%d]\n', ...
        size(X_tx,1), size(X_tx,2), size(X_tx,3), size(X_tx,4));

    t_method = tic;
    for snr_i = 1:n_snr
        snr_val = snr_list(snr_i);
        tt = NaN(1, n_mc);

        fprintf('  [SNR %+4d dB] (%d/%d) ', snr_val, snr_i, n_snr);
        t_snr = tic;

        for mc_i = 1:n_mc
            rng(rng_seeds(mi, snr_i, mc_i));
            p = p_tx;
            p.SNR         = snr_val;
            p.enable_SI   = true;
            p.enable_SIC  = true;
            p.H_SI_matrix = H_SI_rx;
            p.beta_SI     = beta_SI_val;

            try
                rxCube = simulate_radar_channel_3d(X_tx, p);
                [th, ph, R_est, v_est, ~] = joint_estimator_fast(rxCube, X_tx, p);
                cmp = evaluate_estimation(th, ph, R_est, v_est, p, false);
                clear rxCube th ph R_est v_est;

                if isfield(cmp, 'rmse_theta') && ~isnan(cmp.rmse_theta)
                    tt(mc_i) = cmp.rmse_theta;   % angle RMSE only
                end
                clear cmp;
            catch ME
                fprintf('x');
                clear rxCube th ph R_est v_est cmp;
            end

            if mod(mc_i, 20) == 0, fprintf('.'); end
        end

        rmse_theta_all(mi, snr_i, :) = tt;

        el = toc(t_snr);
        fprintf(' | th=%.4f deg | NaN:%d/%d | %s\n', ...
            median(tt, 'omitnan'), sum(isnan(tt)), n_mc, ...
            duration(0,0,round(el),'Format','mm:ss'));

        % Lightweight checkpoint after every SNR point.
        save('task_si_suppression_sic_angle_checkpoint.mat', ...
            'snr_list', 'methods', 'method_labels', 'n_mc', ...
            'beta_SI_val', 'rmse_theta_all');
    end

    fprintf('  %s finished: %.1f min\n', method_labels{mi}, toc(t_method)/60);
end

fprintf('\nTotal simulation time: %.1f min\n', toc(t_all)/60);

% ======================= 5. Summary / save ================================
rmse_theta_med = median(rmse_theta_all, 3, 'omitnan');

fprintf('\n--- Angle RMSE summary (median over %d MC) ---\n', n_mc);
fprintf('%8s  %28s  %28s\n', 'SNR', method_labels{1}, method_labels{2});
for si = 1:n_snr
    fprintf('%+8d  %28.6f  %28.6f\n', ...
        snr_list(si), rmse_theta_med(1,si), rmse_theta_med(2,si));
end

mat_path = fullfile(pwd, 'task_si_suppression_sic_angle.mat');
save(mat_path, ...
    'snr_list', 'methods', 'method_labels', 'n_mc', ...
    'beta_SI_val', 'rmse_theta_all', 'rmse_theta_med');
fprintf('\nSaved: %s\n', mat_path);

% CSV for the merge script: snr, ns_sic_th, lag_sic_th
csv_path = fullfile(pwd, 'data_si_suppression_sic_ns_lag_angle.csv');
fid = fopen(csv_path, 'w');
fprintf(fid, 'snr,ns_sic_th,lag_sic_th\n');
fclose(fid);
csv_data = [snr_list(:), rmse_theta_med(1,:)', rmse_theta_med(2,:)'];
writematrix(csv_data, csv_path, 'WriteMode', 'append');
fprintf('Saved: %s\n', csv_path);

% ======================= 6. Standalone angle figure =======================
fprintf('\n--- Standalone angle figure ---\n');
colors    = {[0.302 0.733 0.835], [0.200 0.627 0.173]};
markers   = {'s', '^'};
linestyle = {'--', '-.'};

fig = figure('Color', 'w', 'Units', 'pixels', ...
    'Position', [120, 160, 600, 440]);
hold on;
for mi = 1:n_methods
    semilogy(snr_list, max(rmse_theta_med(mi, :), 1e-12), ...
        'Color', colors{mi}, ...
        'Marker', markers{mi}, ...
        'LineStyle', linestyle{mi}, ...
        'LineWidth', 1.3, ...
        'MarkerSize', 5.5, ...
        'MarkerFaceColor', 'w');
end
xlabel('Input SNR (dB)', 'FontName', 'Times New Roman', 'FontSize', 10);
ylabel('Angle RMSE (deg)', 'FontName', 'Times New Roman', 'FontSize', 10);
title(sprintf('Angle RMSE vs SNR - digital SIC (LS est.) (L=%d, MC=%d, beta_{SI}=%g)', ...
    L_val, n_mc, beta_SI_val), ...
    'FontName', 'Times New Roman', 'FontSize', 10, 'FontWeight', 'normal');
legend(method_labels, 'Location', 'northeastoutside', 'Box', 'on', ...
    'FontName', 'Times New Roman', 'FontSize', 8, 'Interpreter', 'none');
xlim([snr_list(1)-2, snr_list(end)+2]);
apply_nature_axes(gca);
set(gca, 'YScale', 'log');

base_path = fullfile(fig_dir, 'fig_si_suppression_sic_angle');
savefig(fig, [base_path '.fig']);
exportgraphics(fig, [base_path '.png'], 'Resolution', 300);
fprintf('  %s.fig / .png\n', base_path);

% ======================= 7. Toast =========================================
toast_script = fullfile(pwd, 'toast_notify.py');
if isfile(toast_script)
    try
        cmd = sprintf('python "%s" "SI-SIC angle run done" "%dx%dx%d, %.1fmin"', ...
            toast_script, n_methods, n_snr, n_mc, toc(t_all)/60);
        system(cmd);
    catch
    end
end

fprintf('\nDone. Next step to overlay on the previous figure:\n');
fprintf('  add_sic_angle_to_previous_fig\n');
fprintf('Finished: %s | Total: %.1f min\n', char(datetime('now')), toc(t_all)/60);

diary off;
