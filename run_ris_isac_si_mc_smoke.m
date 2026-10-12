function out = run_ris_isac_si_mc_smoke(n_mc, beta_list)
%RUN_RIS_ISAC_SI_MC_SMOKE  Full-size, low-Monte-Carlo RIS + SI smoke test
%
%   out = run_ris_isac_si_mc_smoke()
%   out = run_ris_isac_si_mc_smoke(2, [0.001 0.1])
%
% The experiment keeps the project's full-size 28 GHz MIMO-OFDM setup and
% compares no RIS, continuous-phase RIS, and 4-state RIS.  Every method in
% one Monte-Carlo trial uses the same transmit waveform, SI channel, and AWGN
% realization.  The noise reference is fixed to the no-RIS target power, so
% an RIS target-path gain is not normalized away by the simulator.

if nargin < 1 || isempty(n_mc), n_mc = 2; end
if nargin < 2 || isempty(beta_list), beta_list = [0.001 0.1]; end
n_mc = max(1, round(n_mc));
beta_list = beta_list(:).';

root = fileparts(mfilename('fullpath'));
addpath(root);
warning('off', 'all');
t_all = tic;

% Fixed experiment configuration: full project dimensions, single stream so
% the integrated RIS target model remains exactly compatible with the chain.
p0 = build_default_params();
p0.enable_SI = true;
p0.enable_SIC = false;
p0.precoder_type = 'zf';
p0.K_stream = 1;
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

fprintf('===============================================================\n');
fprintf(' Full-size RIS + self-interference smoke test\n');
fprintf(' Ns=%d, CPI=%d, Tx=%d, Rx=%d, RIS=%d, SNR=%.1f dB, MC=%d\n', ...
    p0.N, p0.K, p0.Ntx*p0.Nty, p0.Mx*p0.My, p0.ris.N_ris, p0.SNR, n_mc);
fprintf(' beta_SI = [%s], SIC = off, precoder = ZF\n', num2str(beta_list));

% The point-scatterer SI model is the same one used by the existing main
% chain.  It is deterministic, so all RIS methods see exactly the same SI.
% A fixed H_SI matrix is intentionally not introduced here: this smoke test
% isolates the RIS target-assistance effect in the project's default SI path.

% Build the waveform once to derive deterministic W and the RIS optimization.
rng(2026100201, 'twister');
tx_template = generate_mimo_ofdm_waveform(p0);
model_template = build_ris_target_model(p0, tx_template, zeros(p0.ris.N_ris, 1));
[phi_cont, opt_cont] = optimize_ris_target_phase(model_template, p0, Inf, ...
    ones(p0.ris.N_ris, 1));
[phi_tau4, opt_tau4] = optimize_ris_target_phase(model_template, p0, 4, phi_cont);

scheme_names = {'No RIS', 'RIS continuous', 'RIS tau=4'};
scheme_phi = {zeros(p0.ris.N_ris,1), phi_cont, phi_tau4};
scheme_opt = {struct(), opt_cont, opt_tau4};
n_scheme = numel(scheme_names);
n_beta = numel(beta_list);

% Fixed noise reference: generate a no-RIS, no-SI target once.  This keeps
% the AWGN floor identical for every beta and every RIS state.
p_ref = p0;
p_ref.enable_SI = false;
p_ref.beta_SI = 0;
p_ref.ris_target_model = [];
rng(2026100202, 'twister');
[~, ref_info] = simulate_radar_channel_3d(tx_template.X, p_ref);
noise_ref_target_power = ref_info.target_signal_power;

% Allocate scalar metrics. Dimensions: scheme x beta x Monte-Carlo.
target_gain_db = NaN(n_scheme, n_beta, n_mc);
target_gain_q_db = NaN(n_scheme, n_beta, n_mc, p0.num_targets);
detected_targets = NaN(n_scheme, n_beta, n_mc);
rmse_theta = NaN(n_scheme, n_beta, n_mc);
rmse_phi = NaN(n_scheme, n_beta, n_mc);
rmse_R = NaN(n_scheme, n_beta, n_mc);
rmse_v = NaN(n_scheme, n_beta, n_mc);
runtime_sim = NaN(n_scheme, n_beta, n_mc);
runtime_est = NaN(n_scheme, n_beta, n_mc);

% Expected per-target power ratios are independent of the random QAM symbols
% because the RIS model operates on the deterministic precoder W.
target_ref_q = local_target_powers(model_template, scheme_phi{1}, p0.alpha);
target_scheme_q = zeros(n_scheme, p0.num_targets);
for si = 1:n_scheme
    target_scheme_q(si,:) = local_target_powers(model_template, scheme_phi{si}, p0.alpha).';
end
expected_gain_q_db = 10*log10(max(target_scheme_q, eps) ./ max(target_ref_q.', eps));

for mc = 1:n_mc
    % Same random data for all schemes and beta values in this trial.
    rng(2026101000 + mc, 'twister');
    tx = generate_mimo_ofdm_waveform(p0);
    if mc == 1
        % W is deterministic for the fixed geometry; assert that the model
        % used for optimization is the same as the current waveform.
        if max(abs(tx.W(:) - tx_template.W(:))) > 1e-10
            error('Transmit precoder changed unexpectedly between MC trials');
        end
    end

    for bi = 1:n_beta
        beta_si = beta_list(bi);
        for si = 1:n_scheme
            p = p0;
            p.beta_SI = beta_si;
            p.noise_reference_target_power = noise_ref_target_power;
            if si == 1
                p.ris_target_model = [];
            else
                % The precoder W and geometry are fixed across MC trials;
                % only the RIS phase vector changes between schemes.
                p.ris_target_model = model_template;
                p.ris_target_model.phi = scheme_phi{si};
            end

            % Reset RNG before each scheme so the AWGN sample is paired.
            rng(2026200000 + 100*mc + 10*bi, 'twister');
            t_sim = tic;
            [rx_cube, sim_info] = simulate_radar_channel_3d(tx.X, p);
            runtime_sim(si,bi,mc) = toc(t_sim);

            t_est = tic;
            [theta_est, phi_est, R_est, v_est, est_info] = ...
                joint_estimator_fast(rx_cube, tx.X, p);
            runtime_est(si,bi,mc) = toc(t_est);
            cmp = evaluate_estimation(theta_est, phi_est, R_est, v_est, p, false);

            % Target-power gain is relative to the same no-RIS reference.
            target_gain_db(si,bi,mc) = 10*log10(max(sim_info.target_signal_power, eps) / ...
                max(ref_info.target_signal_power, eps));
            target_gain_q_db(si,bi,mc,:) = expected_gain_q_db(si,:);
            detected_targets(si,bi,mc) = est_info.detected_targets;
            rmse_theta(si,bi,mc) = cmp.rmse_theta;
            rmse_phi(si,bi,mc) = cmp.rmse_phi;
            rmse_R(si,bi,mc) = cmp.rmse_R;
            rmse_v(si,bi,mc) = cmp.rmse_v;

            fprintf('[MC %d/%d] beta=%g, %-15s gain=%7.3f dB, detected=%d, ', ...
                mc, n_mc, beta_si, scheme_names{si}, target_gain_db(si,bi,mc), ...
                est_info.detected_targets);
            fprintf('RMSE(theta)=%.4f deg, R=%.4f m, v=%.4f m/s\n', ...
                cmp.rmse_theta, cmp.rmse_R, cmp.rmse_v);
            clear rx_cube;
        end
    end
end

% Aggregate mean and standard deviation over MC trials.
mean_gain_db = mean(target_gain_db, 3, 'omitnan');
std_gain_db = std(target_gain_db, 0, 3, 'omitnan');
mean_detected = mean(detected_targets, 3, 'omitnan');
mean_rmse_theta = mean(rmse_theta, 3, 'omitnan');
mean_rmse_phi = mean(rmse_phi, 3, 'omitnan');
mean_rmse_R = mean(rmse_R, 3, 'omitnan');
mean_rmse_v = mean(rmse_v, 3, 'omitnan');

fprintf('\n==================== MC mean results ====================\n');
for bi = 1:n_beta
    fprintf('beta_SI=%g\n', beta_list(bi));
    for si = 1:n_scheme
        fprintf('  %-15s gain=%7.3f +/- %.3f dB, detected=%.2f, ', ...
            scheme_names{si}, mean_gain_db(si,bi), std_gain_db(si,bi), mean_detected(si,bi));
        fprintf('RMSE(theta)=%.4f deg, phi=%.4f deg, R=%.4f m, v=%.4f m/s\n', ...
            mean_rmse_theta(si,bi), mean_rmse_phi(si,bi), mean_rmse_R(si,bi), mean_rmse_v(si,bi));
    end
    fprintf('  RIS continuous vs no RIS: Δgain=%+.3f dB, ΔRMSE(theta)=%+.4f deg, ', ...
        mean_gain_db(2,bi)-mean_gain_db(1,bi), ...
        mean_rmse_theta(2,bi)-mean_rmse_theta(1,bi));
    fprintf('ΔRMSE(R)=%+.4f m, ΔRMSE(v)=%+.4f m/s\n', ...
        mean_rmse_R(2,bi)-mean_rmse_R(1,bi), mean_rmse_v(2,bi)-mean_rmse_v(1,bi));
end

out = struct();
out.mode = 'full-size-low-MC-with-SI';
out.n_mc = n_mc;
out.beta_list = beta_list;
out.params = p0;
out.scheme_names = scheme_names;
out.scheme_phi = scheme_phi;
out.optimization = scheme_opt;
out.noise_reference_target_power = noise_ref_target_power;
out.expected_gain_q_db = expected_gain_q_db;
out.target_gain_db = target_gain_db;
out.target_gain_q_db = target_gain_q_db;
out.detected_targets = detected_targets;
out.rmse_theta = rmse_theta;
out.rmse_phi = rmse_phi;
out.rmse_R = rmse_R;
out.rmse_v = rmse_v;
out.runtime_sim = runtime_sim;
out.runtime_est = runtime_est;
out.mean_gain_db = mean_gain_db;
out.std_gain_db = std_gain_db;
out.mean_detected = mean_detected;
out.mean_rmse_theta = mean_rmse_theta;
out.mean_rmse_phi = mean_rmse_phi;
out.mean_rmse_R = mean_rmse_R;
out.mean_rmse_v = mean_rmse_v;
out.elapsed_min = toc(t_all)/60;
out.timestamp = char(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss'));

save(fullfile(root, 'ris_isac_si_mc_smoke_results.mat'), '-struct', 'out', '-v7.3');
fid = fopen(fullfile(root, 'ris_isac_si_mc_smoke_summary.csv'), 'w');
fprintf(fid, 'beta_SI,scheme,mean_gain_dB,std_gain_dB,mean_detected,rmse_theta_deg,rmse_phi_deg,rmse_range_m,rmse_velocity_mps\n');
for bi = 1:n_beta
    for si = 1:n_scheme
        fprintf(fid, '%.12g,%s,%.8f,%.8f,%.8f,%.8f,%.8f,%.8f,%.8f\n', ...
            beta_list(bi), scheme_names{si}, mean_gain_db(si,bi), std_gain_db(si,bi), ...
            mean_detected(si,bi), mean_rmse_theta(si,bi), mean_rmse_phi(si,bi), ...
            mean_rmse_R(si,bi), mean_rmse_v(si,bi));
    end
end
fclose(fid);
fprintf('\nSaved ris_isac_si_mc_smoke_results.mat/.csv (%.2f min).\n', out.elapsed_min);
end

function p_q = local_target_powers(model, phi, alpha)
Ns = size(model.direct_beam, 2);
Q = size(model.direct_beam, 1);
p_q = zeros(Q, 1);
phi = phi(:);
for q = 1:Q
    ris_q = squeeze(sum(model.ris_beam(:,q,:) .* reshape(phi,[],1,1), 1));
    ris_q = reshape(ris_q, Ns, 1);
    eff = model.direct_beam(q,:).' + ris_q;
    p_q(q) = alpha(q)^2 * mean(abs(eff).^2);
end
end
