function run_fas_experiment(profile,output,worker,workers,mc,snrs)
% Resumable runner. Each worker owns disjoint samples; no parallel toolbox needed.
root=fileparts(mfilename('fullpath')); addpath(root,fileparts(root));
assert(strcmp(which('build_default_params'),fullfile(fileparts(root),'build_default_params.m')), ...
    'Wrong Stage-3 source on MATLAB path; change directory to this code/fas folder.');
if nargin<1, profile='smoke'; end
if nargin<2, output=fullfile(root,['results_',profile]); end
if nargin<3, worker=0; end
if nargin<4, workers=1; end
options=fas_options(profile);
if nargin>=5 && ~isempty(mc), options.mc=mc; end
if nargin>=6 && ~isempty(snrs), options.snr_db=snrs; end
assert(~(ispc && strcmp(profile,'full')),'Full runs are server-only.');
assert(worker>=0 && worker<workers && workers>=1 && fix(workers)==workers);
assert(options.mc>=1 && fix(options.mc)==options.mc && all(isfinite(options.snr_db)) && all(diff(options.snr_db)>0));
maxNumCompThreads(options.threads);
if ~exist(output,'dir'), mkdir(output); end
if ~exist(fullfile(output,'samples'),'dir'), mkdir(fullfile(output,'samples')); end
source=fas_source_identity(); template=fas_parameters(options,0,options.snr_db(1));
manifest=struct('options',options,'parameters',template,'source',source, ...
    'basis','User supplied MATLAB Stage-3, backup 8dcf95f25fd70e948e347b12f6d25b660e164f90', ...
    'total_cases',options.mc*numel(options.snr_db),'methods',{fas_methods(options)}, ...
    'model','Narrowband spatial steering, wideband delay; original physical RIS gain; no mutual coupling', ...
    'fine_sampling','Inherited 256 subcarriers / 64 symbols over full spans; guard removes samples', ...
    'timing','256 coarse + 256 fine symbols; offline processing time reported separately', ...
    'geometry_sampling','Original random target generator reseeded once per MC; paired across SNR');
manifest.id=fas_hash(unicode2native(jsonencode(manifest),'UTF-8'));
mp=fullfile(output,'manifest.json');
if exist(mp,'file')
    old=jsondecode(fileread(mp)); assert(strcmp(old.id,manifest.id),'Manifest mismatch: use a new output directory.');
else
    fas_write_json(mp,manifest);
end
progress_path=fullfile(output,sprintf('worker_%d.json',worker));
progress=struct('worker',worker,'workers',workers,'pid',feature('getpid'), ...
    'manifest_id',manifest.id,'state','RUNNING','completed',0,'assigned',0,'phase','initializing', ...
    'trial',0,'snr_db',options.snr_db(1),'updated_utc','');
total=manifest.total_cases; progress.assigned=numel(worker:workers:total-1); update('initializing');
try
    for trial=0:options.mc-1
        for si=1:numel(options.snr_db)
            if mod(trial*numel(options.snr_db)+si-1,workers)~=worker, continue; end
            progress.trial=trial; progress.snr_db=options.snr_db(si);
            dest=fullfile(output,'samples',sprintf('snr_%02d_mc_%04d.mat',si,trial));
            if exist(dest,'file')
                saved=load(dest,'manifest_id'); assert(strcmp(saved.manifest_id,manifest.id),'Checkpoint mismatch.');
                progress.completed=progress.completed+1; update('resumed checkpoint'); continue;
            end
            result=fas_run_case(options,trial,si,@update);
            manifest_id=manifest.id; temp=[dest,'.tmp.mat'];
            save(temp,'result','manifest_id','-v7'); movefile(temp,dest,'f');
            progress.completed=progress.completed+1; update('checkpoint saved');
        end
    end
    progress.state='COMPLETE'; update('worker complete');
catch err
    progress.state='FAILED'; update(getReport(err,'extended','hyperlinks','off')); rethrow(err);
end
if workers==1, aggregate_fas(output,false); end
    function update(phase)
        progress.phase=phase;
        progress.updated_utc=char(datetime('now','TimeZone','UTC','Format','yyyy-MM-dd''T''HH:mm:ss''Z'''));
        fas_write_json(progress_path,progress);
        fprintf('[%s] worker=%d MC=%d/%d SNR=%g saved=%d/%d %s\n', ...
            progress.updated_utc,worker,progress.trial+1,options.mc,progress.snr_db, ...
            progress.completed,progress.assigned,phase);
    end
end
