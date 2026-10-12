function out = run_ris_rmse_snr_worker(shard_id)
%RUN_RIS_RMSE_SNR_WORKER  One of four full-size RIS/SI RMSE shards.
%
% Four remote MATLAB jobs call this function with shard_id=1..4. Each job
% evaluates 25 of the 100 Monte-Carlo trials at every SNR point. The random
% seeds depend only on the global MC index and SNR, so the four shards merge
% into a paired, reproducible MC=100 experiment.

if nargin < 1 || isempty(shard_id), shard_id = 1; end
shard_id = round(shard_id);
n_shards = 4;
if shard_id < 1 || shard_id > n_shards
    error('shard_id must be an integer in 1..4');
end

root = fileparts(mfilename('fullpath'));
if isempty(root), root = pwd; end
addpath(root);
warning('off', 'all');

% ========================= Experiment definition =========================
n_mc_total = 100;
snr_list = -45:5:20;
beta_si = 0.1;                 % residual SI amplitude relative to target
mc_indices = shard_id:n_shards:n_mc_total;
n_mc_local = numel(mc_indices);

scheme_names = {'No RIS', 'RIS continuous', 'RIS tau=4'};
n_scheme = numel(scheme_names);
n_snr = numel(snr_list);

stem = sprintf('ris_rmse_snr_mc100_shard%d', shard_id);
log_path = fullfile(root, [stem '.log']);
ckpt_path = fullfile(root, [stem '_checkpoint.mat']);
final_path = fullfile(root, [stem '.mat']);
if isfile(log_path), delete(log_path); end
diary(log_path); diary on;

fprintf('===============================================================\n');
base_for_print = build_default_params();
fprintf(' RIS + SI RMSE SNR worker %d/%d\n', shard_id, n_shards);
fprintf(' Full size: Ns=%d, CPI=%d, Tx=%d, Rx=%d, SNR=[%d:%d:%d], beta_SI=%.3g\n', ...
    base_for_print.N, 256, 16, 64, snr_list(1), snr_list(2)-snr_list(1), ...
    snr_list(end), beta_si);
fprintf(' Global MC indices: %d..%d (stride %d), local count=%d\n', ...
    mc_indices(1), mc_indices(end), n_shards, n_mc_local);

% ========================= Full-size configuration ========================
p0 = base_for_print;
p0.enable_SI = true;
p0.beta_SI = beta_si;
p0.enable_SIC = false;
p0.precoder_type = 'zf';
p0.K_stream = 1;              % required by the integrated RIS target model
p0.K = 256;
p0.fast_estimator.R_min_gate = 20;
p0.fast_estimator.R_max_gate = 600;
p0.ris = struct();
p0.ris.enable = true;
p0.ris.N_ris = 64;
p0.ris.Nx = 8;
p0.ris.Ny = 8;
p0.ris.d_sep = 1.5 * p0.lambda;
p0.ris.eta = 0.8;
p0.ris.target_weights = p0.alpha(:).^2;
p0.ris.max_sweeps = 12;
p0.ris.randomize_order = false;

% The precoder W is deterministic for fixed geometry. Build and optimize the
% RIS once; QAM data changes only the transmitted symbols, not W.
rng(2026100201, 'twister');
tx_for_model = generate_mimo_ofdm_waveform(p0);
model_template = build_ris_target_model(p0, tx_for_model, zeros(p0.ris.N_ris,1));
[phi_cont, opt_cont] = optimize_ris_target_phase(model_template, p0, Inf, ...
    ones(p0.ris.N_ris,1));
[phi_tau4, opt_tau4] = optimize_ris_target_phase(model_template, p0, 4, phi_cont);
scheme_phi = {zeros(p0.ris.N_ris,1), phi_cont, phi_tau4};
scheme_opt = {struct(), opt_cont, opt_tau4};

% ========================= Checkpoint handling ============================
rmse_theta = NaN(n_scheme, n_snr, n_mc_total);
rmse_phi   = NaN(n_scheme, n_snr, n_mc_total);
rmse_R     = NaN(n_scheme, n_snr, n_mc_total);
rmse_v     = NaN(n_scheme, n_snr, n_mc_total);
detected   = NaN(n_scheme, n_snr, n_mc_total);
done_mc    = false(1, n_mc_total);

if isfile(ckpt_path)
    try
        C = load(ckpt_path, 'rmse_theta','rmse_phi','rmse_R','rmse_v', ...
            'detected','done_mc','snr_list','beta_si','n_mc_total');
        if isequal(C.snr_list, snr_list) && C.beta_si == beta_si && ...
                C.n_mc_total == n_mc_total
            rmse_theta = C.rmse_theta;
            rmse_phi   = C.rmse_phi;
            rmse_R     = C.rmse_R;
            rmse_v     = C.rmse_v;
            detected   = C.detected;
            done_mc    = C.done_mc;
            fprintf('Resuming checkpoint: %d/%d global MC complete.\n', ...
                sum(done_mc), n_mc_total);
        end
    catch ME
        fprintf('Checkpoint ignored: %s\n', ME.message);
    end
end

% ========================= Main MC loop ===================================
t_all = tic;
for local_i = 1:n_mc_local
    mc = mc_indices(local_i);
    if done_mc(mc)
        fprintf('Skipping completed MC=%d\n', mc);
        continue;
    end

    % Same waveform across schemes and SNR values for this global MC trial.
    rng(2026101000 + mc, 'twister');
    tx = generate_mimo_ofdm_waveform(p0);

    % No-RIS, no-SI reference fixes the actual AWGN level at each SNR.
    p_ref = p0;
    p_ref.enable_SI = false;
    p_ref.beta_SI = 0;
    p_ref.ris_target_model = [];
    p_ref.SNR = Inf;
    rng(2026102000 + mc, 'twister');
    [~, ref_info] = simulate_radar_channel_3d(tx.X, p_ref);
    p_ref_target_power = ref_info.target_signal_power;

    fprintf('MC=%d/%d started\n', mc, n_mc_total);
    for snr_i = 1:n_snr
        snr_val = snr_list(snr_i);
        for si = 1:n_scheme
            p = p0;
            p.SNR = snr_val;
            p.noise_reference_target_power = p_ref_target_power;
            if si == 1
                p.ris_target_model = [];
            else
                p.ris_target_model = model_template;
                p.ris_target_model.phi = scheme_phi{si};
            end

            % Identical AWGN for all RIS schemes at a given MC/SNR pair.
            rng(2026103000 + 1000*mc + snr_i, 'twister');
            [rx_cube, ~] = simulate_radar_channel_3d(tx.X, p);
            [theta_est, phi_est, R_est, v_est, est_info] = ...
                joint_estimator_fast(rx_cube, tx.X, p);
            cmp = evaluate_estimation(theta_est, phi_est, R_est, v_est, p, false);
            rmse_theta(si,snr_i,mc) = cmp.rmse_theta;
            rmse_phi(si,snr_i,mc) = cmp.rmse_phi;
            rmse_R(si,snr_i,mc) = cmp.rmse_R;
            rmse_v(si,snr_i,mc) = cmp.rmse_v;
            detected(si,snr_i,mc) = est_info.detected_targets;
            clear rx_cube;
        end
        fprintf('  MC=%d/%d SNR=%+d dB done\n', mc, n_mc_total, snr_val);
    end

    done_mc(mc) = true;
    save(ckpt_path, 'rmse_theta','rmse_phi','rmse_R','rmse_v','detected', ...
        'done_mc','snr_list','beta_si','n_mc_total','mc_indices','shard_id', ...
        'scheme_names','-v7.3');
    fprintf('Completed MC=%d/%d in %.1f min; checkpoint saved.\n', ...
        mc, n_mc_total, toc(t_all)/60);
end

% Save a self-contained shard result. The aggregator waits for all four.
out = struct();
out.shard_id = shard_id;
out.n_shards = n_shards;
out.n_mc_total = n_mc_total;
out.mc_indices = mc_indices;
out.snr_list = snr_list;
out.beta_si = beta_si;
out.scheme_names = scheme_names;
out.scheme_phi = scheme_phi;
out.optimization = scheme_opt;
out.rmse_theta = rmse_theta;
out.rmse_phi = rmse_phi;
out.rmse_R = rmse_R;
out.rmse_v = rmse_v;
out.detected = detected;
out.done_mc = done_mc;
out.elapsed_min = toc(t_all)/60;
out.timestamp = char(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss'));
save(final_path, '-struct', 'out', '-v7.3');
fprintf('FINAL_RESULT=%s\n', final_path);
fprintf('Worker %d finished in %.2f min.\n', shard_id, out.elapsed_min);
diary off;
end
