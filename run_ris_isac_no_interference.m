function out = run_ris_isac_no_interference(mode)
%RUN_RIS_ISAC_NO_INTERFERENCE  RIS gain in the main ZTE ISAC chain
%
%   out = run_ris_isac_no_interference('quick')
%   out = run_ris_isac_no_interference('full')
%
% The experiment keeps the existing MIMO-OFDM waveform and estimator, sets
% enable_SI=false, and compares no RIS against random, continuous, and
% discrete-phase RIS target assistance. Noise is fixed to the no-RIS target
% power, so a gain in target power becomes an actual SNR/RMSE gain.

if nargin < 1 || isempty(mode)
    mode = 'full';
end
mode = lower(char(mode));
is_quick = strcmp(mode, 'quick');

root = fileparts(mfilename('fullpath'));
addpath(root);
rng(20261002, 'twister');

p = build_default_params();
p.enable_SI = false;
p.beta_SI = 0;
p.enable_SIC = false;
p.precoder_type = 'zf';
p.fast_estimator.R_max_gate = 600;
p.fast_estimator.R_min_gate = 20;
if is_quick
    p.K = 64;
end

p.ris = struct();
p.ris.enable = true;
p.ris.N_ris = 64;
p.ris.Nx = 8;
p.ris.Ny = 8;
p.ris.d_sep = 1.5 * p.lambda;
p.ris.eta = 0.8;
p.ris.target_weights = p.alpha(:).^2;
p.ris.max_sweeps = 12;
p.ris.randomize_order = false;

fprintf('===============================================================\n');
fprintf(' RIS target-assistance experiment, no co-channel interference\n');
fprintf(' mode=%s, fc=%.2f GHz, B=%.3f GHz, Ns=%d, CPI=%d\n', ...
    mode, p.fc/1e9, p.B/1e9, p.N, p.K);
fprintf(' Tx=%dx%d, Rx=%dx%d, RIS=%dx%d, eta=%.2f\n', ...
    p.Ntx, p.Nty, p.Mx, p.My, p.ris.Nx, p.ris.Ny, p.ris.eta);

tx_cfg = p;
tx_cfg.K_stream = 1;
tx = generate_mimo_ofdm_waveform(tx_cfg);
tx_signal = tx.X;

model_template = build_ris_target_model(p, tx, zeros(p.ris.N_ris,1));
[phi_cont, opt_cont] = optimize_ris_target_phase(model_template, p, Inf, ones(p.ris.N_ris,1));
phi_rand = exp(1j*2*pi*rand(p.ris.N_ris,1));
target_power_ref_by_q = local_target_powers(model_template, zeros(p.ris.N_ris,1), p.alpha);

names = {'No RIS', 'Random phase', 'Continuous phase', ...
         'Discrete tau=2', 'Discrete tau=4', 'Discrete tau=8', 'Discrete tau=16'};
phis = {zeros(p.ris.N_ris,1), phi_rand, phi_cont};
opt_infos = {struct(), struct(), opt_cont};
taus = [2 4 8 16];
for tau = taus
    [phi_tau, info_tau] = optimize_ris_target_phase(model_template, p, tau, phi_cont);
    phis{end+1} = phi_tau; %#ok<AGROW>
    opt_infos{end+1} = info_tau; %#ok<AGROW>
end

% Common noise reference: no RIS and no AWGN.
p_ref = p;
p_ref.ris_target_model = [];
rng(20261003, 'twister');
[~, ref_info] = simulate_radar_channel_3d(tx_signal, p_ref);
base_target_power = ref_info.target_signal_power;
p.noise_reference_target_power = base_target_power;

results = struct([]);
for k = 1:numel(names)
    p_case = p;
    if k == 1
        p_case.ris_target_model = [];
    else
        p_case.ris_target_model = build_ris_target_model(p, tx, phis{k});
    end
    target_power_q = local_target_powers(model_template, phis{k}, p.alpha);
    rng(20261004, 'twister');
    t_sim = tic;
    [rx_cube, sim_info] = simulate_radar_channel_3d(tx_signal, p_case);
    sim_time = toc(t_sim);
    t_est = tic;
    [theta_est, phi_est, R_est, v_est, est_info] = ...
        joint_estimator_fast(rx_cube, tx_signal, p_case);
    est_time = toc(t_est);
    compare = evaluate_estimation(theta_est, phi_est, R_est, v_est, p_case, false);

    target_gain_db = 10*log10(max(sim_info.target_signal_power, eps) / ...
        max(base_target_power, eps));
    r = struct();
    r.name = names{k};
    r.phi = phis{k};
    r.target_signal_power = sim_info.target_signal_power;
    r.target_gain_db = target_gain_db;
    r.target_gain_by_target_db = 10*log10(max(target_power_q, eps) ./ ...
        max(target_power_ref_by_q, eps));
    r.detected_targets = est_info.detected_targets;
    r.theta_est = theta_est;
    r.phi_est = phi_est;
    r.R_est = R_est;
    r.v_est = v_est;
    r.compare = compare;
    r.runtime_sim = sim_time;
    r.runtime_est = est_time;
    r.optimization = opt_infos{k};
    results = [results; r]; %#ok<AGROW>

    fprintf('%-20s gain=%8.3f dB (q=[%6.2f %6.2f]) detected=%d  RMSE(R)= %8.4f m  ', ...
        names{k}, target_gain_db, r.target_gain_by_target_db(1), ...
        r.target_gain_by_target_db(min(2,numel(r.target_gain_by_target_db))), ...
        est_info.detected_targets, compare.rmse_R);
    fprintf('RMSE(theta)= %8.4f deg  RMSE(phi)= %8.4f deg\n', ...
        compare.rmse_theta, compare.rmse_phi);
end

out = struct();
out.mode = mode;
out.params = p;
out.tx_precoder_info = tx.precoder_info;
out.base_target_power = base_target_power;
out.results = results;
out.timestamp = char(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss'));
save(fullfile(root, 'ris_isac_no_interference_results.mat'), '-struct', 'out', '-v7.3');

fid = fopen(fullfile(root, 'ris_isac_no_interference_summary.csv'), 'w');
fprintf(fid, 'method,target_gain_dB,target1_gain_dB,target2_gain_dB,detected_targets,rmse_theta_deg,rmse_phi_deg,rmse_range_m,rmse_velocity_mps\n');
for k = 1:numel(results)
    c = results(k).compare;
    gq = results(k).target_gain_by_target_db;
    if numel(gq) < 2, gq(2) = NaN; end
    fprintf(fid, '%s,%.8f,%.8f,%.8f,%d,%.8f,%.8f,%.8f,%.8f\n', ...
        results(k).name, results(k).target_gain_db, gq(1), gq(2), results(k).detected_targets, ...
        c.rmse_theta, c.rmse_phi, c.rmse_R, c.rmse_v);
end
fclose(fid);

fig = figure('Visible','off', 'Color','w', 'Position',[100 100 1200 720]);
gain = [results.target_gain_db];
rmse_r = arrayfun(@(r) r.compare.rmse_R, results);
rmse_t = arrayfun(@(r) r.compare.rmse_theta, results);
subplot(1,3,1); bar(gain); grid on; ylabel('Target-power gain (dB)');
set(gca, 'XTick', 1:numel(names), 'XTickLabel', names, 'XTickLabelRotation', 30);
subplot(1,3,2); bar(rmse_r); grid on; ylabel('Range RMSE (m)');
set(gca, 'XTick', 1:numel(names), 'XTickLabel', names, 'XTickLabelRotation', 30);
subplot(1,3,3); bar(rmse_t); grid on; ylabel('Elevation RMSE (deg)');
set(gca, 'XTick', 1:numel(names), 'XTickLabel', names, 'XTickLabelRotation', 30);
print(fig, fullfile(root, 'ris_isac_no_interference_results.png'), '-dpng', '-r150');
close(fig);
fprintf('结果已保存到 ris_isac_no_interference_results.mat/.csv/.png\n');
end

function p_q = local_target_powers(model, phi, alpha)
% Expected per-target transmit-beam powers for the common waveform.
Ns = size(model.direct_beam, 2);
Q = size(model.direct_beam, 1);
p_q = zeros(Q,1);
phi = phi(:);
for q = 1:Q
    ris_q = squeeze(sum(model.ris_beam(:,q,:) .* reshape(phi,[],1,1), 1));
    eff = model.direct_beam(q,:).' + reshape(ris_q, Ns, 1);
    p_q(q) = alpha(q)^2 * mean(abs(eff).^2);
end
end
