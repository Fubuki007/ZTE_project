function out = run_ris_rmse_snr_sic_worker(shard_id)
%RUN_RIS_RMSE_SNR_SIC_WORKER Full-size paired RIS/SI/SIC RMSE sweep.
% Four remote MATLAB jobs call this with shard_id=1..4.  Each MC trial
% shares the same matrix SI channel, waveform, pilot and AWGN across the
% six SIC/RIS cases, so the effect of SIC and RIS is directly comparable.

if nargin < 1 || isempty(shard_id), shard_id = 1; end
out = struct();
case_budget = str2double(getenv('RIS_CASES_PER_PROCESS'));
if isnan(case_budget), case_budget = Inf; end
if case_budget <= 0 || (isfinite(case_budget) && case_budget ~= fix(case_budget))
    error('RIS_CASES_PER_PROCESS must be a positive integer.');
end
saved_this_process = 0;
[config, result_prefix, n_shards] = ris_sic_run_config;
n_mc_total = config.n_mc_total;
use_single = config.use_single;
if shard_id ~= fix(shard_id) || shard_id < 1 || shard_id > n_shards
    error('shard_id must be an integer in 1..%d', n_shards);
end

root = fileparts(mfilename('fullpath'));
if isempty(root), root = pwd; end
addpath(root);

% ========================= Experiment definition =========================
snr_list = config.snr_list;
beta_si = config.beta_si;
mc_indices = shard_id:n_shards:n_mc_total;
n_mc_local = numel(mc_indices);

scheme_names = {'No RIS (SIC off)', 'RIS continuous (SIC off)', ...
    'RIS tau=4 (SIC off)', 'No RIS (SIC on)', ...
    'RIS continuous (SIC on)', 'RIS tau=4 (SIC on)'};
n_scheme = numel(scheme_names);
n_snr = numel(snr_list);

stem = sprintf('%s_shard%d', result_prefix, shard_id);
log_path = fullfile(root, [stem '.log']);
ckpt_path = fullfile(root, [stem '_checkpoint.mat']);
final_path = fullfile(root, [stem '.mat']);
sample_dir = fullfile(root, [result_prefix '_samples']);
if ~isfolder(sample_dir), mkdir(sample_dir); end
diary(log_path); diary on;
diary_cleanup = onCleanup(@() diary('off')); %#ok<NASGU>

fprintf('===============================================================\n');
base_for_print = build_default_params();
fprintf(' RIS + matrix SI + pilot-LS SIC worker %d/%d\n', shard_id, n_shards);
fprintf(' Ns=%d, CPI=%d, Tx=%d, Rx=%d, SNR=%s, beta_SI=%.3g\n', ...
    base_for_print.N, 256, 16, 64, mat2str(snr_list), beta_si);
fprintf(' MC total=%d; shard indices %d..%d (stride %d), local=%d\n', ...
    n_mc_total, mc_indices(1), mc_indices(end), n_shards, n_mc_local);
fprintf(' SIC: LS pilot estimate, true_channel=false, pilot_len=128\n');
fprintf(' Memory mode: use_single=%d; per-case atomic checkpoints=%s\n', ...
    use_single, sample_dir);

% ========================= Full-size configuration ========================
p0 = base_for_print;
p0.enable_SI = true;
p0.beta_SI = beta_si;
p0.enable_SIC = false;
p0.sic_use_true_channel = false;
p0.SIC_pilot_len = 128;
p0.SIC_pilot = [];
p0.sic_error_db = [];
p0.precoder_type = 'zf';
p0.K_stream = 1;
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
config.params = p0;

% Generate a fixed geometry/template for RIS phase design. ZF's W does not
% depend on the SI channel, so this only builds the target-path codebook.
hsi_cfg = struct('model','ura_rician', ...
    'Nt_total',p0.Ntx*p0.Nty, 'Nr_total',p0.Mx*p0.My, ...
    'kappa_SI',10, 'Ntx',p0.Ntx, 'Nty',p0.Nty, ...
    'Mx',p0.Mx, 'My',p0.My, 'd_lambda',0.5, ...
    'theta_tx_deg',p0.theta_SI, 'phi_tx_deg',p0.phi_SI, ...
    'theta_rx_deg',p0.theta_SI, 'phi_rx_deg',p0.phi_SI);
rng(2026100201, 'twister');
H_template = generate_HSI(hsi_cfg);
p0.H_SI = H_template;
p0.H_SI_matrix = H_template;
rng(2026100202, 'twister');
tx_for_model = generate_mimo_ofdm_waveform(p0);
model_template = build_ris_target_model(p0, tx_for_model, zeros(p0.ris.N_ris,1));
[phi_cont, opt_cont] = optimize_ris_target_phase(model_template, p0, Inf, ...
    ones(p0.ris.N_ris,1));
[phi_tau4, opt_tau4] = optimize_ris_target_phase(model_template, p0, 4, phi_cont);
scheme_phi = {zeros(p0.ris.N_ris,1), phi_cont, phi_tau4};
scheme_opt = {struct(), opt_cont, opt_tau4};
clear tx_for_model;

% ========================= Checkpoint handling ============================
rmse_theta = NaN(n_scheme, n_snr, n_mc_total);
rmse_phi   = NaN(n_scheme, n_snr, n_mc_total);
rmse_R     = NaN(n_scheme, n_snr, n_mc_total);
rmse_v     = NaN(n_scheme, n_snr, n_mc_total);
detected   = NaN(n_scheme, n_snr, n_mc_total);
sic_suppression_db = NaN(n_scheme, n_snr, n_mc_total);
done_mc    = false(1, n_mc_total);
completed = false(n_scheme, n_snr, n_mc_total);

% Per-MC files are the authoritative resume points.  They survive a native
% MATLAB crash that occurs before the aggregate shard checkpoint is written.
for kk = 1:numel(mc_indices)
    mc0 = mc_indices(kk);
    sample_path = fullfile(sample_dir, sprintf('mc_%05d.mat', mc0));
    [T, valid, reason] = ris_sic_load_sample(sample_path, config, mc0);
    if valid
        rmse_theta(:,:,mc0) = T.rmse_theta;
        rmse_phi(:,:,mc0) = T.rmse_phi;
        rmse_R(:,:,mc0) = T.rmse_R;
        rmse_v(:,:,mc0) = T.rmse_v;
        detected(:,:,mc0) = T.detected;
        sic_suppression_db(:,:,mc0) = T.sic_suppression_db;
        completed(:,:,mc0) = T.completed;
        done_mc(mc0) = all(T.completed(:));
        fprintf('Resumed MC=%d: %d/%d cases saved.\n',mc0,nnz(T.completed),numel(T.completed));
    elseif isfile(sample_path)
        error('RIS:InvalidCheckpoint','Checkpoint %s rejected: %s',sample_path,reason);
    end
end
fprintf('Resume scan: %d/%d assigned MC samples complete.\n', ...
    sum(done_mc(mc_indices)), n_mc_local);

% ========================= Main MC loop ===================================
t_all = tic;
for local_i = 1:n_mc_local
    mc = mc_indices(local_i);
    if done_mc(mc)
        fprintf('Skipping completed MC=%d\n', mc);
        continue;
    end

    % Vary the SI channel, waveform and pilot by MC; share each realization
    % across all six cases for a paired comparison.
    rng(2026106000 + mc, 'twister');
    H_SI_matrix = generate_HSI(hsi_cfg);
    p_mc = p0;
    p_mc.H_SI = H_SI_matrix;
    p_mc.H_SI_matrix = H_SI_matrix;
    rng(2026101000 + mc, 'twister');
    tx_full = generate_mimo_ofdm_waveform(p_mc);
    % Retain only the signal consumed by the channel/estimator.  In single
    % precision the large tx/rx arrays use roughly half the memory.
    tx = struct('X', tx_full.X);
    if use_single
        tx.X = single(tx.X);
        p_mc.H_SI = single(p_mc.H_SI);
        p_mc.H_SI_matrix = single(p_mc.H_SI_matrix);
    end
    clear tx_full H_SI_matrix;
    rng(2026105000 + mc, 'twister');
    pilot = (randn(p0.Ntx*p0.Nty, p0.SIC_pilot_len) + ...
        1j*randn(p0.Ntx*p0.Nty, p0.SIC_pilot_len)) / sqrt(2);
    if use_single, pilot = single(pilot); end

    % Fix noise power against the no-SI, no-RIS target-only signal.
    p_ref = p_mc;
    p_ref.enable_SI = false;
    p_ref.enable_SIC = false;
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
            if completed(si,snr_i,mc)
                fprintf('Skipping saved MC=%d SNR=%+g scheme=%d\n',mc,snr_val,si);
                continue;
            end
            p = p_mc;
            p.SNR = snr_val;
            p.noise_reference_target_power = p_ref_target_power;
            p.SIC_pilot = pilot;
            if si <= 3
                sic_on = false;
                scheme_idx = si;
            else
                sic_on = true;
                scheme_idx = si - 3;
            end
            p.enable_SIC = sic_on;
            if scheme_idx == 1
                p.ris_target_model = [];
            else
                p.ris_target_model = model_template;
                p.ris_target_model.phi = scheme_phi{scheme_idx};
            end

            % SIC estimation consumes two Nr-by-Lp Gaussian arrays before
            % AWGN generation. Consume the same draws in SIC-off cases so
            % all six cases receive exactly paired data AWGN.
            rng(2026103000 + 1000*mc + snr_i, 'twister');
            if ~sic_on
                Nr = p.Mx * p.My;
                Lp = p.SIC_pilot_len;
                randn(Nr,Lp,'like',p_mc.H_SI); randn(Nr,Lp,'like',p_mc.H_SI);
            end
            fprintf('CASE_START MC=%d/%d SNR=%+g scheme=%d channel\n',mc,n_mc_total,snr_val,si);
            [rx_cube, sim_info] = simulate_radar_channel_3d(tx.X, p);
            if sic_on && (~isfield(sim_info,'sic') || ...
                    ~isfield(sim_info.sic,'applied') || ~sim_info.sic.applied)
                error('SIC was requested but not applied at MC=%d SNR=%g.', mc, snr_val);
            end
            fprintf('CASE_STAGE MC=%d SNR=%+g scheme=%d estimator\n',mc,snr_val,si);
            [theta_est, phi_est, R_est, v_est, est_info] = ...
                joint_estimator_fast(rx_cube, tx.X, p);
            cmp = evaluate_estimation(theta_est, phi_est, R_est, v_est, p, false);
            rmse_theta(si,snr_i,mc) = cmp.rmse_theta;
            rmse_phi(si,snr_i,mc) = cmp.rmse_phi;
            rmse_R(si,snr_i,mc) = cmp.rmse_R;
            rmse_v(si,snr_i,mc) = cmp.rmse_v;
            detected(si,snr_i,mc) = est_info.detected_targets;
            if sic_on && isfield(sim_info.sic, 'suppression_db')
                sic_suppression_db(si,snr_i,mc) = sim_info.sic.suppression_db;
            end
            clear rx_cube;
            completed(si,snr_i,mc) = true;
            sample = struct('mc',mc,'config',config,'completed',completed(:,:,mc), ...
                'rmse_theta',rmse_theta(:,:,mc),'rmse_phi',rmse_phi(:,:,mc), ...
                'rmse_R',rmse_R(:,:,mc),'rmse_v',rmse_v(:,:,mc), ...
                'detected',detected(:,:,mc),'sic_suppression_db',sic_suppression_db(:,:,mc));
            ris_sic_save_atomic(fullfile(sample_dir,sprintf('mc_%05d.mat',mc)),sample);
            fprintf('CASE_SAVED MC=%d/%d SNR=%+g scheme=%d (%d/%d)\n', ...
                mc,n_mc_total,snr_val,si,nnz(sample.completed),numel(sample.completed));
            saved_this_process = saved_this_process + 1;
            assigned_completed = completed(:,:,mc_indices);
            if saved_this_process >= case_budget && ~all(assigned_completed(:))
                % Return normally after a short batch; the supervisor starts
                % a fresh runtime and restores all already committed cases.
                fprintf('BATCH_YIELD saved=%d; checkpoints committed.\n',saved_this_process);
                diary off;
                return;
            end
        end
        fprintf('  MC=%d/%d SNR=%+d dB done\n', mc, n_mc_total, snr_val);
    end
    clear tx p_mc pilot p_ref rx_cube;

    done_mc(mc) = true;
    checkpoint = struct('config',config,'done_mc',done_mc,'completed',completed, ...
        'mc_indices',mc_indices,'shard_id',shard_id);
    ris_sic_save_atomic(ckpt_path,checkpoint);
    fprintf('Completed MC=%d/%d in %.1f min; checkpoint saved.\n', ...
        mc, n_mc_total, toc(t_all)/60);
end

% Save a self-contained shard result.
out = struct();
out.shard_id = shard_id;
out.config = config;
out.n_shards = n_shards;
out.n_mc_total = n_mc_total;
out.mc_indices = mc_indices;
out.snr_list = snr_list;
out.beta_si = beta_si;
out.scheme_names = scheme_names;
out.sic_mode = 'pilot LS with thermal AWGN, no genie channel';
out.sic_pilot_len = p0.SIC_pilot_len;
out.sic_error_db = [];
out.scheme_phi = scheme_phi;
out.optimization = scheme_opt;
out.rmse_theta = rmse_theta;
out.rmse_phi = rmse_phi;
out.rmse_R = rmse_R;
out.rmse_v = rmse_v;
out.detected = detected;
out.sic_suppression_db = sic_suppression_db;
out.done_mc = done_mc;
out.elapsed_min = toc(t_all)/60;
out.timestamp = char(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss'));
ris_sic_save_atomic(final_path,out);
fprintf('FINAL_RESULT=%s\n', final_path);
fprintf('Worker %d finished in %.2f min.\n', shard_id, out.elapsed_min);
diary off;
end
