function result = nc_case(cfg, trial, rcs_index, fixed_sites, notify)
% NC_CASE  Runs all 8 paired methods for a single (trial, rcs) full-scale scenario.
% Enforces paired random seeds, strict physical constraint verification, scale-invariant
% and legacy accuracy metrics, and zero dropped failure samples.
if nargin < 5, notify = @(s) []; end

t_start = tic;
rcs = cfg.rcs_m2(rcs_index);
scene = nc_geometry('scene', cfg, trial);
M = numel(cfg.methods);

% Run Proposed_Joint_CRB first so MatchedPos_NoRIS gets its exact position!
order = [8, 1, 2, 3, 4, 5, 6, 7];
rows = cell(M, 1);

for idx = 1:M
    m = order(idx);
    mname = cfg.methods{m};
    notify(sprintf('method %d/%d (%s)', idx, M, mname));
    use_ris = ~contains(mname, 'NoRIS');

    fs = fixed_sites;
    if strcmp(mname, 'MatchedPos_NoRIS')
        fs.q_matched = rows{8}.q;
    end

    opt = nc_optimizer('solve_method', mname, scene, rcs, fs, cfg);
    ev = opt.eval;

    row = struct();
    row.trial = trial;
    row.rcs_index = rcs_index;
    row.rcs_m2 = rcs;
    row.method = mname;
    row.seed = scene.seed;
    row.yc = scene.yc;
    row.feasible = ev.feasible;
    row.det_feasible = ev.det_feasible;
    row.t2_via_ris = ev.t2_via_ris;
    row.q = ev.q;
    row.opt_seconds = opt.opt_seconds;
    row.min_sinr_db = ev.min_sinr_db;
    row.max_pow_frac = ev.max_pow_frac;
    row.predicted_peb_m = ev.worst_peb;
    row.predicted_peb_t1_m = sqrt(max(0, ev.speb(1)));
    row.predicted_peb_t2_m = sqrt(max(0, ev.speb(2)));
    row.ang_cond_t2 = ev.ang_cond_t2;
    row.cond_num_t2 = ev.cond_num_t2;
    row.predicted_coarse_snr_t1_db = ev.coarse_snr_db(1);
    row.predicted_coarse_snr_t2_db = ev.coarse_snr_db(2);
    row.hist_speb = opt.hist_speb;
    row.hist_cond = opt.hist_cond;

    % Default fallback values (retained in all statistics if infeasible!)
    row.locked = [false; false];
    row.coarse_pos = scene.prior;
    row.fine_pos = scene.prior;
    row.coarse_err_m = vecnorm(scene.prior - scene.targets, 2, 2);
    row.fine_err_m = row.coarse_err_m;
    row.coarse_range_err_m = [nan; nan];
    row.meas_coarse_snr_db = [nan; nan];
    row.rr_win_retention_db = nan;
    row.peak_to_clutter_db = nan;
    row.beam_misaligned = false;
    row.los_vis = [false; false];
    row.far_field_m = nan;

    if ev.feasible
        row.far_field_m = norm(ev.q - cfg.ris_pos);
        % Strict physical assertions
        assert(row.max_pow_frac <= 1.0 + 1e-5, 'Power budget violated: %.6f', row.max_pow_frac);
        assert(row.min_sinr_db >= cfg.comm_sinr_db(1) - 1e-4, 'Comm SINR violated: %.4f dB', row.min_sinr_db);
        assert(row.far_field_m >= cfg.far_field_min_m - 1e-6, 'Far-field violated: %.3f m', row.far_field_m);

        % Paired waveform seeds across all methods for this trial!
        [c_pos, c_info] = nc_coarse_capture(ev.q, scene, ev.d_coarse, ev.d_coarse_ris, rcs, scene.seed + 101, cfg, use_ris);

        % Re-center fine-stage 8-config RIS beams & beams on measured coarse estimate c_pos
        % (mirrors Stage-3 two-stage closed loop; uses ZERO truth information!)
        ev_fine = ev;
        if use_ris && c_info.locked(2) && ~c_info.los_vis(2) && ~strcmp(mname, 'FixedOpt_RandomRIS')
            if strcmp(mname, 'Lit_EnergyMax_AO')
                ev_tmp = nc_optimizer('eval_point', ev.q, c_pos, scene.users, rcs, true, 'lit_energy', cfg);
            else
                ev_tmp = nc_optimizer('eval_point', ev.q, c_pos, scene.users, rcs, true, 'proposed', cfg);
            end
            if ev_tmp.feasible
                ev_fine = ev_tmp;
                if strcmp(mname, 'Proposed_Joint_CRB') || strcmp(mname, 'FixedOpt_RIS')
                    % Quick 4-iter Wirtinger refinement around measured coarse estimate
                    cfg_q = cfg; cfg_q.ris_grad_iters = 4;
                    ev_tmp_opt = nc_optimizer('solve_method', 'FixedOpt_RIS', ...
                        struct('prior', c_pos, 'users', scene.users, 'seed', scene.seed), ...
                        rcs, struct('q_ris', ev.q), cfg_q);
                    if ev_tmp_opt.eval.feasible
                        ev_fine = ev_tmp_opt.eval;
                    end
                end
            end
        end

        [f_pos, f_info] = nc_fine_stage(ev.q, scene, c_pos, c_info, ev_fine, rcs, scene.seed + 202, cfg, use_ris);

        row.locked = c_info.locked(:);
        row.los_vis = c_info.los_vis(:);
        row.coarse_pos = c_pos;
        row.fine_pos = f_pos;
        row.coarse_err_m = vecnorm(c_pos - scene.targets, 2, 2);
        row.fine_err_m = vecnorm(f_pos - scene.targets, 2, 2);
        row.coarse_range_err_m = c_info.coarse_range_err_m(:);
        row.meas_coarse_snr_db = c_info.coarse_snr_db(:);
        row.rr_win_retention_db = f_info.rr_win_retention_db;
        row.peak_to_clutter_db = c_info.stage_b.peak_to_clutter_db;
        row.beam_misaligned = c_info.stage_b.beam_misaligned;
    end

    % Compute anchor distances for scale-invariant relative error metric (< 2% of range)
    if ev.feasible
        d1_anc = norm(scene.targets(1, :).' - ev.q);
        if row.los_vis(2)
            d2_anc = norm(scene.targets(2, :).' - ev.q);
        else
            d2_anc = norm(scene.targets(2, :).' - cfg.ris_pos);
        end
    else
        d1_anc = 100.0; d2_anc = norm(scene.targets(2, :).' - cfg.ris_pos);
    end
    row.rel_err = row.fine_err_m ./ max([d1_anc; d2_anc], 1.0);
    row.scene_rmse_m = sqrt(mean(row.fine_err_m.^2));
    row.coarse_scene_rmse_m = sqrt(mean(row.coarse_err_m.^2));
    row.captured_both = ev.feasible && all(row.locked);

    % Three accuracy criteria: (1) scale-invariant <2%, (2) high-precision <1m, (3) legacy <5m
    row.success_rel2pct = row.captured_both && all(row.rel_err <= cfg.rel_error_limit);
    row.success_1m      = row.captured_both && all(row.fine_err_m <= cfg.abs_error_limit_m);
    row.success_5m      = row.captured_both && all(row.fine_err_m <= cfg.legacy_error_limit_m);
    row.failure_rel2pct = ~row.success_rel2pct;
    row.failure_1m      = ~row.success_1m;
    row.failure_5m      = ~row.success_5m;

    rows{m} = row;
end

result = struct('trial', trial, 'rcs_index', rcs_index, 'rcs_m2', rcs, ...
    'seed', scene.seed, 'scene', scene, 'methods', {cfg.methods}, ...
    'rows', {rows}, 'seconds', toc(t_start));
end
