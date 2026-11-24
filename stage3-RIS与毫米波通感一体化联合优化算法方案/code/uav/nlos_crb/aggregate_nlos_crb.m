function summary = aggregate_nlos_crb(output)
% AGGREGATE_NLOS_CRB  Strict verification, CSV export, paired bootstrap 95% CIs,
% dual (Success Rate, Conditional 3D RMSE) metrics, pure-NLoS subset breakdown,
% and publication-grade comparison figure generation.
root = fileparts(mfilename('fullpath'));
uav_dir = fileparts(root);
code_dir = fileparts(uav_dir);
addpath(root, uav_dir, code_dir);
maxNumCompThreads(2);

manifest = jsondecode(fileread(fullfile(output, 'manifest.json')));
cfg = manifest.config;
nmc = cfg.mc;
nr = numel(cfg.rcs_m2);
nm = numel(cfg.methods);
assert(manifest.total_cases == nmc * nr, 'Manifest case count mismatch.');

% 1. Re-verify source file SHA256 hashes
for k = 1:numel(manifest.source)
    p_abs = fullfile(code_dir, manifest.source(k).file);
    f = fopen(p_abs, 'rb'); assert(f >= 0); bytes = fread(f, inf, '*uint8'); fclose(f);
    assert(strcmp(uav_hash(bytes), manifest.source(k).sha256), 'Source modified during run: %s', manifest.source(k).file);
end

files = dir(fullfile(output, 'samples', 'mc_*_rcs_*.mat'));
assert(numel(files) == manifest.total_cases, 'Incomplete checkpoints: %d/%d', numel(files), manifest.total_cases);

% Preallocate metric tensors (nmc x nr x nm)
mse_all  = zeros(nmc, nr, nm);
mse_t1   = zeros(nmc, nr, nm);
mse_t2   = zeros(nmc, nr, nm);
peb_all  = nan(nmc, nr, nm);
cap_both = false(nmc, nr, nm);
feas_m   = false(nmc, nr, nm);
via_ris  = false(nmc, nr, nm);
succ_rel = false(nmc, nr, nm);
succ_1m  = false(nmc, nr, nm);
succ_5m  = false(nmc, nr, nm);
misalign = false(nmc, nr, nm);
opt_sec  = zeros(nmc, nr, nm);
ang_cond = nan(nmc, nr, nm);
retent   = nan(nmc, nr, nm);
clutter  = nan(nmc, nr, nm);
elapsed  = zeros(nmc, nr);

max_pow = 0; min_sinr = inf; min_ff = inf;
n_rows = manifest.total_cases * nm;
csv_rows = cell(n_rows, 30);
ridx = 0;

for trial = 1:nmc
    for ri = 1:nr
        p_mat = fullfile(output, 'samples', sprintf('mc_%04d_rcs_%02d.mat', trial, ri));
        item = load(p_mat, 'result', 'manifest_id');
        res = item.result;
        assert(strcmp(item.manifest_id, manifest.id) && res.trial == trial && res.rcs_index == ri);
        assert(res.seed == cfg.seed + 10000 * trial && res.rcs_m2 == cfg.rcs_m2(ri));
        elapsed(trial, ri) = res.seconds;

        for m = 1:nm
            r = res.rows{m};
            assert(strcmp(r.method, cfg.methods{m}));
            if r.feasible
                max_pow  = max(max_pow, r.max_pow_frac);
                min_sinr = min(min_sinr, r.min_sinr_db);
                min_ff   = min(min_ff, r.far_field_m);
                assert(r.max_pow_frac <= 1 + 1e-5);
                assert(r.min_sinr_db >= cfg.comm_sinr_db(1) - 1e-4);
                assert(r.far_field_m >= cfg.far_field_min_m - 1e-6);
            end
            mse_all(trial, ri, m)  = mean(r.fine_err_m.^2);
            mse_t1(trial, ri, m)   = r.fine_err_m(1)^2;
            mse_t2(trial, ri, m)   = r.fine_err_m(2)^2;
            peb_all(trial, ri, m)  = r.predicted_peb_m;
            cap_both(trial, ri, m) = r.captured_both;
            feas_m(trial, ri, m)   = r.feasible;
            via_ris(trial, ri, m)  = r.t2_via_ris;
            succ_rel(trial, ri, m) = r.success_rel2pct;
            succ_1m(trial, ri, m)  = r.success_1m;
            succ_5m(trial, ri, m)  = r.success_5m;
            misalign(trial, ri, m) = r.beam_misaligned;
            opt_sec(trial, ri, m)  = r.opt_seconds;
            ang_cond(trial, ri, m) = r.ang_cond_t2;
            retent(trial, ri, m)   = r.rr_win_retention_db;
            clutter(trial, ri, m)  = r.peak_to_clutter_db;

            ridx = ridx + 1;
            csv_rows(ridx, :) = { ...
                trial, r.rcs_m2, r.method, r.seed, r.yc, ...
                r.q(1), r.q(2), r.q(3), ...
                double(r.feasible), double(r.det_feasible), double(r.t2_via_ris), ...
                double(r.locked(1)), double(r.locked(2)), double(r.captured_both), ...
                r.fine_err_m(1), r.fine_err_m(2), r.scene_rmse_m, r.coarse_scene_rmse_m, ...
                r.rel_err(1), r.rel_err(2), ...
                double(r.success_rel2pct), double(r.success_1m), double(r.success_5m), ...
                r.predicted_peb_m, r.ang_cond_t2, r.min_sinr_db, r.max_pow_frac, ...
                r.rr_win_retention_db, r.peak_to_clutter_db, r.opt_seconds};
        end
    end
end

var_names = {'trial','rcs_m2','method','seed','yc','qx','qy','qz', ...
    'feasible','det_feasible','t2_via_ris','locked1','locked2','captured_both', ...
    'err_t1_m','err_t2_m','scene_rmse_m','coarse_rmse_m','rel_err1','rel_err2', ...
    'success_rel2pct','success_1m','success_5m','peb_m','ang_cond_t2', ...
    'min_sinr_db','max_pow_frac','rr_win_retention_db','peak_to_clutter_db','opt_seconds'};
tbl = cell2table(csv_rows, 'VariableNames', var_names);
writetable(tbl, fullfile(output, 'case_metrics.csv'));

% Compute group summaries: overall RMSE, conditional RMSE | captured, success rates, & pure-NLoS subset
rmse_all      = zeros(nr, nm);
rmse_cond     = nan(nr, nm);
rmse_t2_cond  = nan(nr, nm);
med_rmse_cond = nan(nr, nm);
cap_rate      = zeros(nr, nm);
succ_rel_rate = zeros(nr, nm);
succ_1m_rate  = zeros(nr, nm);
succ_5m_rate  = zeros(nr, nm);
nlos_cap_rate = nan(nr, nm);
nlos_succ_1m  = nan(nr, nm);
nlos_t2_rmse  = nan(nr, nm);
mean_opt_s    = zeros(nr, nm);
med_ang_cond  = nan(nr, nm);
nlos_counts   = zeros(nr, 1);

for ri = 1:nr
    % Pure-NLoS subset defined by scenes where Proposed_Joint_CRB (method 8) uses RR-only path
    nlos_mask = via_ris(:, ri, 8);
    nlos_counts(ri) = sum(nlos_mask);
    for m = 1:nm
        rmse_all(ri, m)      = sqrt(mean(mse_all(:, ri, m)));
        cap_rate(ri, m)      = mean(cap_both(:, ri, m));
        succ_rel_rate(ri, m) = mean(succ_rel(:, ri, m));
        succ_1m_rate(ri, m)  = mean(succ_1m(:, ri, m));
        succ_5m_rate(ri, m)  = mean(succ_5m(:, ri, m));
        mean_opt_s(ri, m)    = mean(opt_sec(:, ri, m));
        cm = cap_both(:, ri, m);
        if any(cm)
            rmse_cond(ri, m)     = sqrt(mean(mse_all(cm, ri, m)));
            rmse_t2_cond(ri, m)  = sqrt(mean(mse_t2(cm, ri, m)));
            med_rmse_cond(ri, m) = median(sqrt(mse_all(cm, ri, m)));
        end
        ac = ang_cond(:, ri, m); ac = ac(isfinite(ac));
        if ~isempty(ac), med_ang_cond(ri, m) = median(ac); end
        if any(nlos_mask)
            nlos_cap_rate(ri, m) = mean(cap_both(nlos_mask, ri, m));
            nlos_succ_1m(ri, m)  = mean(succ_1m(nlos_mask, ri, m));
            cm_n = nlos_mask & cap_both(:, ri, m);
            if any(cm_n)
                nlos_t2_rmse(ri, m) = sqrt(mean(mse_t2(cm_n, ri, m)));
            end
        end
    end
end

% Paired geometry bootstrap (4,000 repeats, seed 20261125) on key predeclared comparisons
% Pairs: [baseline, proposed]
pairs = [2 8; 5 8; 4 8; 7 8; 6 8; 3 2];
labels = { ...
    'Proposed_vs_FixedOpt_RIS', ...
    'Proposed_vs_MatchedPos_NoRIS', ...
    'Proposed_vs_OnlineUAV_NoRIS', ...
    'Proposed_vs_Lit_EnergyMax_AO', ...
    'Proposed_vs_GridSelect_RIS', ...
    'FixedOpt_RIS_vs_RandomRIS'};

rng(cfg.bootstrap_seed, 'twister');
B_rep = cfg.bootstrap_repeats;
b_idx = randi(nmc, nmc, B_rep);
comps = repmat(struct('name','','rcs_m2',0,'rmse_gain_pct',0,'rmse_ci95_pct',[0 0], ...
    'succ1m_diff_pp',0,'succ1m_ci95_pp',[0 0],'succ_rel2_diff_pp',0,'succ_rel2_ci95_pp',[0 0]), ...
    nr * numel(labels), 1);
ci_i = 0;
for ri = 1:nr
    for k = 1:numel(labels)
        ci_i = ci_i + 1;
        a_m = pairs(k, 1); b_m = pairs(k, 2);
        ma = mse_all(:, ri, a_m); mb = mse_all(:, ri, b_m);
        sa = double(succ_1m(:, ri, a_m)); sb = double(succ_1m(:, ri, b_m));
        ra = double(succ_rel(:, ri, a_m)); rb = double(succ_rel(:, ri, b_m));

        boot_rmse = sort(100 * (1 - sqrt(mean(mb(b_idx), 1)) ./ max(sqrt(mean(ma(b_idx), 1)), realmin)));
        boot_s1   = sort(100 * (mean(sb(b_idx), 1) - mean(sa(b_idx), 1)));
        boot_sr   = sort(100 * (mean(rb(b_idx), 1) - mean(ra(b_idx), 1)));
        lo = round(0.025 * B_rep); hi = round(0.975 * B_rep);

        comps(ci_i) = struct( ...
            'name', labels{k}, 'rcs_m2', cfg.rcs_m2(ri), ...
            'rmse_gain_pct', 100 * (1 - sqrt(mean(mb)) / max(sqrt(mean(ma)), realmin)), ...
            'rmse_ci95_pct', [boot_rmse(lo), boot_rmse(hi)], ...
            'succ1m_diff_pp', 100 * (mean(sb) - mean(sa)), ...
            'succ1m_ci95_pp', [boot_s1(lo), boot_s1(hi)], ...
            'succ_rel2_diff_pp', 100 * (mean(rb) - mean(ra)), ...
            'succ_rel2_ci95_pp', [boot_sr(lo), boot_sr(hi)]);
    end
end

summary = struct( ...
    'manifest_id', manifest.id, 'complete_cases', manifest.total_cases, ...
    'methods', {cfg.methods}, 'rcs_m2', cfg.rcs_m2, ...
    'rmse_all_m', rmse_all, 'rmse_cond_m', rmse_cond, 'rmse_t2_cond_m', rmse_t2_cond, ...
    'med_rmse_cond_m', med_rmse_cond, 'capture_rate', cap_rate, ...
    'success_rel2pct_rate', succ_rel_rate, 'success_1m_rate', succ_1m_rate, 'success_5m_rate', succ_5m_rate, ...
    'nlos_scene_counts', nlos_counts, 'nlos_capture_rate', nlos_cap_rate, ...
    'nlos_success_1m_rate', nlos_succ_1m, 'nlos_t2_cond_rmse_m', nlos_t2_rmse, ...
    'mean_opt_seconds', mean_opt_s, 'median_ang_cond_t2', med_ang_cond, ...
    'total_compute_s', sum(elapsed, 'all'), 'comparisons', comps);
uav_write_json(fullfile(output, 'summary.json'), summary);

% Plot 3-panel summary figure
fig = figure('Visible', 'off', 'Position', [40 40 1500 460]);
subplot(1, 3, 1);
plot(cfg.rcs_m2, 100 * succ_1m_rate, '-o', 'LineWidth', 1.5);
xlabel('Target RCS (m^2)'); ylabel('Strict <1 m Success Rate (%)');
title('End-to-End Success Rate (All Scenes)'); grid on;
legend(cfg.methods, 'Interpreter', 'none', 'Location', 'best', 'FontSize', 7);

subplot(1, 3, 2);
semilogy(cfg.rcs_m2, rmse_all, '-s', 'LineWidth', 1.5);
xlabel('Target RCS (m^2)'); ylabel('Pooled 3D Position RMSE (m)');
title('All-Sample 3D RMSE (Failures Retained)'); grid on;

subplot(1, 3, 3);
% Joint (Success Rate, Conditional RMSE) Pareto at primary RCS
pri_i = find(cfg.rcs_m2 == cfg.primary_rcs_m2, 1); if isempty(pri_i), pri_i = 1; end
scatter(100 * succ_1m_rate(pri_i, :), rmse_cond(pri_i, :), 80, 'filled'); hold on;
for m = 1:nm
    if isfinite(rmse_cond(pri_i, m))
        text(100 * succ_1m_rate(pri_i, m) + 0.8, rmse_cond(pri_i, m), cfg.methods{m}, 'Interpreter', 'none', 'FontSize', 7);
    end
end
xlabel('<1 m Success Rate (%)'); ylabel('Conditional 3D RMSE | Captured (m)');
title(sprintf('Joint Pareto @ RCS=%g m^2', cfg.rcs_m2(pri_i))); grid on;
saveas(fig, fullfile(output, 'comparison.png'));
close(fig);

verification = struct( ...
    'passed', true, 'manifest_id', manifest.id, 'cases', manifest.total_cases, ...
    'metric_rows', height(tbl), 'maximum_power_fraction', max_pow, ...
    'minimum_feasible_sinr_db', min_sinr, 'minimum_far_field_m', min_ff, ...
    'all_failures_retained', true, 'source_hashes_verified', true);
uav_write_json(fullfile(output, 'verification.json'), verification);

fprintf('Aggregation COMPLETE: %d cases, %d metric rows, max_pow=%.6f, min_sinr=%.4f dB, min_ff=%.2f m\n', ...
    manifest.total_cases, height(tbl), max_pow, min_sinr, min_ff);
end
