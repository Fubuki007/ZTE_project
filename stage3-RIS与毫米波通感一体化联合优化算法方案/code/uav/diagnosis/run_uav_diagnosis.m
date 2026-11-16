function run_uav_diagnosis(profile,output,worker,workers)
root=fileparts(mfilename('fullpath')); uav=fileparts(root); code=fileparts(uav);
addpath(root,uav,code,fullfile(code,'path_reliability')); maxNumCompThreads(2);
if nargin<3, worker=0; workers=1; end
assert(ismember(profile,{'pilot','full'}) && (~strcmp(profile,'full') || ~ispc));
assert(worker>=0 && worker<workers && worker==fix(worker));
parent='/home/jzm123/AAA_ZTEproject/RIS_UAV_foundation/releases/ad35a777ca7f697f2ea369db834f60f9f9f24277/code/uav/results_full';
pv=jsondecode(fileread(fullfile(parent,'verification.json')));
pm=jsondecode(fileread(fullfile(parent,'manifest.json')));
assert(pv.passed && pv.cases==900 && strcmp(strtrim(fileread(fullfile(parent,'state'))),'COMPLETE'));
if strcmp(profile,'pilot'), trials=0; else, trials=0:299; end
files=[dir(fullfile(root,'*.m'));dir(fullfile(root,'*.sh'));dir(fullfile(uav,'*.m'))];
base={'build_default_params.m','channel_geometry.m','joint_estimator_fast.m','prepare_ris_observation.m', ...
    'refine_ris_parameters.m','evaluate_estimation.m','path_reliability/pr_dictionary.m','path_reliability/pr_refine.m'};
for k=1:numel(base), files(end+1)=dir(fullfile(code,base{k})); end
source=struct('file',{},'sha256',{});
for k=1:numel(files)
    path=fullfile(files(k).folder,files(k).name);
    source(end+1)=struct('file',strrep(path(numel(code)+2:end),'\','/'),'sha256',filehash(path));
end
[~,ix]=sort({source.file}); source=source(ix);
manifest=struct('profile',profile,'parent',parent,'parent_manifest_id',pm.id,'parent_manifest_sha256', ...
    filehash(fullfile(parent,'manifest.json')),'config',pm.config,'waveform',pm.waveform, ...
    'total_cases',numel(trials)*3,'source',source,'bootstrap_seed',20261118,'bootstrap_repeats',4000, ...
    'primary_contrasts',{{'RCS10 receiver beam: failure-rate decrease', ...
    'RCS100 matched RIS: BIC versus full position RMSE reduction'}}, ...
    'assumptions',{{'Full-band coherent receive combination of the existing 64 calibrated channels', ...
    'Same radio resources; additional digital preprocessing and candidate fitting compute', ...
    'Same 300 previously observed geometries; diagnostic replay, not independent holdout', ...
    'Noiseless and frozen-beam variants are diagnostics, not deployable performance'}});
manifest.id=uav_hash(unicode2native(jsonencode(manifest),'UTF-8'));
if ~exist(fullfile(output,'samples'),'dir'), mkdir(fullfile(output,'samples')); end
mp=fullfile(output,'manifest.json');
if exist(mp,'file'), previous=jsondecode(fileread(mp)); assert(strcmp(previous.id,manifest.id));
else, uav_write_json(mp,manifest); end
progress=struct('worker',worker,'workers',workers,'pid',feature('getpid'),'manifest_id',manifest.id, ...
    'state','RUNNING','completed',0,'assigned',numel(worker:workers:manifest.total_cases-1), ...
    'trial',0,'rcs_m2',0,'phase','','updated_utc',''); update('initializing');
try
    for trial=trials
        for ri=1:3
            if mod(trial*3+ri-1,workers)~=worker, continue; end
            progress.trial=trial; progress.rcs_m2=pm.config.rcs_m2(ri);
            name=sprintf('mc_%04d_rcs_%02d.mat',trial,ri); dest=fullfile(output,'samples',name);
            if exist(dest,'file')
                previous=load(dest,'manifest_id'); assert(strcmp(previous.manifest_id,manifest.id));
                progress.completed=progress.completed+1; update('resumed checkpoint'); continue;
            end
            input=fullfile(parent,'samples',name); old=load(input,'result','manifest_id');
            assert(strcmp(old.manifest_id,pm.id));
            result=ud_case(old.result,@update); result.parent_sha256=filehash(input); manifest_id=manifest.id;
            temporary=[dest,'.tmp.mat']; save(temporary,'result','manifest_id','-v7'); movefile(temporary,dest,'f');
            progress.completed=progress.completed+1; update('checkpoint saved');
        end
    end
    progress.state='COMPLETE'; update('worker complete');
catch err
    progress.state='FAILED'; update(getReport(err,'extended','hyperlinks','off')); rethrow(err);
end
if workers==1, aggregate_uav_diagnosis(output); end
    function update(phase)
        progress.phase=phase;
        progress.updated_utc=char(datetime('now','TimeZone','UTC','Format','yyyy-MM-dd''T''HH:mm:ss''Z'''));
        uav_write_json(fullfile(output,sprintf('worker_%d.json',worker)),progress);
        fprintf('[%s] worker=%d MC=%d RCS=%g saved=%d/%d %s\n',progress.updated_utc, ...
            worker,progress.trial,progress.rcs_m2,progress.completed,progress.assigned,phase);
    end
end

function h=filehash(path)
f=fopen(path,'rb'); assert(f>=0); bytes=fread(f,inf,'*uint8'); fclose(f); h=uav_hash(bytes);
end
