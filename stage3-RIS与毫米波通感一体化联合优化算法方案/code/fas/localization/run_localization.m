function run_localization(profile,oldrun,output,worker,workers)
root=fileparts(mfilename('fullpath')); code=fileparts(fileparts(root));
cd(code); addpath(root,fileparts(root),code); maxNumCompThreads(2);
assert(strcmp(which('build_default_params'),fullfile(code,'build_default_params.m')));
if nargin<4, worker=0; workers=1; end
assert(ismember(profile,{'full','smoke'}) && (~ispc || strcmp(profile,'smoke')));
assert(worker>=0 && worker<workers && worker==fix(worker));
base=fas_source_identity(); files=dir(fullfile(root,'*.m')); source=struct([]);
for k=1:numel(files)
    f=fopen(fullfile(root,files(k).name),'rb'); bytes=fread(f,inf,'*uint8'); fclose(f);
    source(k).name=files(k).name; source(k).sha256=fas_hash(bytes);
end
settings=struct('iterations',40,'ris_rounds',1,'oracle',true);
if strcmp(profile,'full')
    original=jsondecode(fileread(fullfile(oldrun,'manifest.json')));
    assert(strcmp(base.sha256,original.source.sha256),'Original model source changed.');
    options=original.options; parameters=original.parameters; input_id=original.id;
    assert(options.mc==300 && numel(options.snr_db)==13 && parameters.N==12672 && parameters.K==256);
else
    options=fas_options('smoke'); parameters=fas_parameters(options,0,10); input_id='generated-smoke';
    settings=struct('iterations',5,'ris_rounds',0,'oracle',false);
end
options.snr_db=options.snr_db(:).';
names={'Fixed_energy','FAS_energy_guard0','FAS_energy_guard4','Fixed_localization','FAS_localization_guard0','FAS_localization_guard4'};
manifest=struct('profile',profile,'options',options,'parameters',parameters,'settings',settings, ...
    'source',source,'base_source',base,'input_manifest_id',input_id,'methods',{names}, ...
    'total_cases',options.mc*numel(options.snr_db),'seed_policy','Reuse original paired checkpoint seed', ...
    'design_information','Coarse location and equal nominal amplitudes; oracle only at 10 dB', ...
    'resources','Original aperture, RF chains, power, SINR and 512-symbol total; FAS guards 0/4');
manifest.id=fas_hash(unicode2native(jsonencode(manifest),'UTF-8'));
if ~exist(output,'dir'), mkdir(output); end
if ~exist(fullfile(output,'samples'),'dir'), mkdir(fullfile(output,'samples')); end
mp=fullfile(output,'manifest.json');
if exist(mp,'file')
    prior=jsondecode(fileread(mp)); assert(strcmp(prior.id,manifest.id),'Manifest mismatch; use a new run directory.');
else
    fas_write_json(mp,manifest);
end
progress=struct('worker',worker,'workers',workers,'pid',feature('getpid'),'manifest_id',manifest.id, ...
    'state','RUNNING','completed',0,'assigned',numel(worker:workers:manifest.total_cases-1), ...
    'trial',0,'snr_db',0,'phase','initializing','updated_utc','');
update('initializing');
try
    for trial=0:options.mc-1
        for si=1:numel(options.snr_db)
            if mod(trial*numel(options.snr_db)+si-1,workers)~=worker, continue; end
            progress.trial=trial; progress.snr_db=options.snr_db(si);
            name=sprintf('snr_%02d_mc_%04d.mat',si,trial); dest=fullfile(output,'samples',name);
            if exist(dest,'file')
                prior=load(dest,'manifest_id'); assert(strcmp(prior.manifest_id,manifest.id));
                progress.completed=progress.completed+1; update('resumed checkpoint'); continue;
            end
            if strcmp(profile,'full')
                old=load(fullfile(oldrun,'samples',name),'result','manifest_id');
                assert(strcmp(old.manifest_id,input_id)); old=old.result;
                assert(old.trial==trial && old.snr_index==si && old.snr_db==options.snr_db(si));
            else
                old=fas_run_case(options,trial,si,@update);
            end
            update('starting localization design'); result=loc_case(old,settings,@update);
            manifest_id=manifest.id; temporary=[dest,'.tmp.mat'];
            save(temporary,'result','manifest_id','-v7'); movefile(temporary,dest,'f');
            progress.completed=progress.completed+1; update('checkpoint saved');
        end
    end
    progress.state='COMPLETE'; update('worker complete');
catch err
    progress.state='FAILED'; update(getReport(err,'extended','hyperlinks','off')); rethrow(err);
end
if workers==1, aggregate_localization(output); end
    function update(phase)
        progress.phase=phase; progress.updated_utc=char(datetime('now','TimeZone','UTC','Format','yyyy-MM-dd''T''HH:mm:ss''Z'''));
        fas_write_json(fullfile(output,sprintf('worker_%d.json',worker)),progress);
        fprintf('[%s] worker=%d MC=%d SNR=%g saved=%d/%d %s\n',progress.updated_utc,worker,progress.trial, ...
            progress.snr_db,progress.completed,progress.assigned,phase);
    end
end
