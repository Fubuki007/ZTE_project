function run_nlos_crb(profile, output, worker, workers)
% RUN_NLOS_CRB  Full-scale server runner for 3GPP UMi UAV-BS + passive 32x32 RIS ISAC.
% Saves source SHA256 manifest, offline-optimal fixed BS sites (calibrated on separate
% independent scenes 10001..10100), atomic per-case checkpoints, and live UTC progress.
root = fileparts(mfilename('fullpath'));
uav_dir = fileparts(root);
code_dir = fileparts(uav_dir);
addpath(root, uav_dir, code_dir);
maxNumCompThreads(2);

if nargin < 1, profile = 'pilot'; end
if nargin < 2, output = fullfile(root, ['results_' profile]); end
if nargin < 3, worker = 0; end
if nargin < 4, workers = 1; end

cfg = nc_config(profile);
assert(~strcmp(profile, 'full') || ~ispc, 'Formal full-scale simulations MUST run on the server.');
assert(worker >= 0 && worker < workers && worker == fix(worker));

% Evaluation trials: 1..cfg.mc (completely disjoint from offline calibration trials 10001..10100!)
trials = 1:cfg.mc;
total_cases = numel(trials) * numel(cfg.rcs_m2);

% Collect SHA256 hashes of all active source files
files = [dir(fullfile(root, '*.m')); dir(fullfile(root, '*.sh'))];
shared = {'uav/uav_hash.m', 'uav/uav_write_json.m', 'coarse_array_angles.m'};
source = struct('file', {}, 'sha256', {});
for k = 1:numel(files)
    p_abs = fullfile(files(k).folder, files(k).name);
    f = fopen(p_abs, 'rb'); assert(f >= 0); bytes = fread(f, inf, '*uint8'); fclose(f);
    rel = strrep(p_abs(numel(code_dir)+2:end), '\', '/');
    source(end+1) = struct('file', rel, 'sha256', uav_hash(bytes)); %#ok<AGROW>
end
for k = 1:numel(shared)
    p_abs = fullfile(code_dir, shared{k});
    f = fopen(p_abs, 'rb'); assert(f >= 0); bytes = fread(f, inf, '*uint8'); fclose(f);
    source(end+1) = struct('file', shared{k}, 'sha256', uav_hash(bytes)); %#ok<AGROW>
end
[~, ix] = sort({source.file}); source = source(ix);

if ~exist(fullfile(output, 'samples'), 'dir')
    mkdir(fullfile(output, 'samples'));
end

% Offline-optimal fixed BS calibration (shared across all workers via manifest.json)
% Only worker 0 computes & writes manifest.json; workers 1..W-1 wait for manifest.json.
mp = fullfile(output, 'manifest.json');
if worker == 0
    if exist(mp, 'file')
        manifest = jsondecode(fileread(mp));
        % Verify source hashes match existing manifest on resume
        assert(isequal({manifest.source.sha256}, {source.sha256}), ...
            'Source files changed relative to existing manifest.json!');
        fixed_sites = manifest.fixed_sites;
    else
        fprintf('[%s] Calibrating offline-optimal fixed BS sites on 100 independent scenes...\n', utc_now());
        n_cal = 100;
        if strcmp(profile, 'smoke'), n_cal = 20; end
        cal_scenes = cell(n_cal, 1);
        for i = 1:n_cal
            cal_scenes{i} = nc_geometry('scene', cfg, 10000 + i);
        end
        cfg_cal = cfg; cfg_cal.freq_knots = 16; % exact < 1e-12, 2x faster
        fixed_sites = struct();
        fixed_sites.cal_trials = [10001, 10000 + n_cal];
        fixed_sites.q_noris = nc_optimizer('offline_fixed', cfg_cal, cal_scenes, false, cfg.primary_rcs_m2);
        fixed_sites.q_ris   = nc_optimizer('offline_fixed', cfg_cal, cal_scenes, true,  cfg.primary_rcs_m2);

        manifest = struct( ...
            'config', cfg, ...
            'source', source, ...
            'fixed_sites', fixed_sites, ...
            'total_cases', total_cases, ...
            'waveform', struct('fc', cfg.fc, 'N', cfg.N, 'K_coarse', cfg.K_coarse, ...
                'K_fine', cfg.K_fine, 'Tx', cfg.Nt, 'Rx', cfg.Mr, 'RIS', cfg.N_ris, ...
                'ris_bits', cfg.ris_bits, 'bandwidth_hz', cfg.B, 'noise_w', cfg.noise_w, ...
                'fraunhofer_m', cfg.fraunhofer_m, 'wideband', cfg.wideband), ...
            'scope', '3GPP UMi 300 m street-canyon stationary-target quasi-static UAV-BS + 32x32 passive 2-bit RIS');
        manifest.id = uav_hash(unicode2native(jsonencode(manifest), 'UTF-8'));
        uav_write_json(mp, manifest);
    end
else
    % Wait up to 300 s for worker 0 to publish manifest.json with calibrated fixed_sites
    t_wait = tic;
    while ~exist(mp, 'file')
        pause(1.0);
        assert(toc(t_wait) < 300, 'Timed out waiting for worker 0 manifest.json');
    end
    pause(0.5);
    manifest = jsondecode(fileread(mp));
    assert(isequal({manifest.source.sha256}, {source.sha256}), 'Manifest source hash mismatch.');
    fixed_sites = manifest.fixed_sites;
end

% Normalize fixed_sites column vectors after jsondecode
fixed_sites.q_noris = fixed_sites.q_noris(:);
fixed_sites.q_ris   = fixed_sites.q_ris(:);

progress = struct('worker', worker, 'workers', workers, 'pid', feature('getpid'), ...
    'manifest_id', manifest.id, 'state', 'RUNNING', 'completed', 0, ...
    'assigned', numel(worker:workers:total_cases-1), 'trial', 0, 'rcs_m2', 0, ...
    'phase', '', 'updated_utc', '');
update('initialized');

try
    for ti = 1:numel(trials)
        trial = trials(ti);
        for ri = 1:numel(cfg.rcs_m2)
            idx = (ti - 1) * numel(cfg.rcs_m2) + (ri - 1);
            if mod(idx, workers) ~= worker, continue; end

            progress.trial = trial;
            progress.rcs_m2 = cfg.rcs_m2(ri);
            dest = fullfile(output, 'samples', sprintf('mc_%04d_rcs_%02d.mat', trial, ri));

            if exist(dest, 'file')
                prev = load(dest, 'manifest_id');
                assert(strcmp(prev.manifest_id, manifest.id), 'Checkpoint manifest_id mismatch.');
                progress.completed = progress.completed + 1;
                update('resumed checkpoint');
                continue;
            end

            result = nc_case(cfg, trial, ri, fixed_sites, @update);
            manifest_id = manifest.id; %#ok<NASGU>
            tmp_file = [dest, '.tmp.mat'];
            save(tmp_file, 'result', 'manifest_id', '-v7');
            movefile(tmp_file, dest, 'f');
            progress.completed = progress.completed + 1;
            update('checkpoint saved');
        end
    end
    progress.state = 'COMPLETE';
    update('worker complete');
catch err
    progress.state = 'FAILED';
    update(getReport(err, 'extended', 'hyperlinks', 'off'));
    rethrow(err);
end

if workers == 1
    aggregate_nlos_crb(output);
end

    function update(phase)
        progress.phase = phase;
        progress.updated_utc = utc_now();
        uav_write_json(fullfile(output, sprintf('worker_%d.json', worker)), progress);
        fprintf('[%s] worker=%d trial=%d RCS=%g saved=%d/%d %s\n', ...
            progress.updated_utc, worker, progress.trial, progress.rcs_m2, ...
            progress.completed, progress.assigned, phase);
    end
end

function s = utc_now()
s = char(datetime('now', 'TimeZone', 'UTC', 'Format', 'yyyy-MM-dd''T''HH:mm:ss''Z'''));
end
