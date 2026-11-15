function run_path_reliability(profile,original,localization,output,worker,workers)
root=fileparts(mfilename('fullpath')); code=fileparts(root);
cd(code); addpath(root,code,fullfile(code,'fas'),fullfile(code,'fas','localization')); maxNumCompThreads(2);
assert(strcmp(which('build_default_params'),fullfile(code,'build_default_params.m')));
if nargin<5, worker=0; workers=1; end
assert(strcmp(profile,'full') && ~ispc,'Formal simulation runs on the Linux server only.');
assert(worker>=0 && worker<workers && worker==fix(worker));
input=jsondecode(fileread(fullfile(original,'manifest.json')));
loc=jsondecode(fileread(fullfile(localization,'manifest.json')));
base=fas_source_identity();
assert(strcmp(base.sha256,input.source.sha256) && strcmp(base.sha256,loc.base_source.sha256));
assert(strcmp(loc.input_manifest_id,input.id));
assert(input.options.mc==300 && numel(input.options.snr_db)==13 && input.parameters.N==12672 && ...
    input.parameters.K==256 && input.parameters.Mx*input.parameters.My==64 && input.parameters.ris_side==16);
settings=struct('no_ris_iterations',40,'ridge_lambdas',[1e-6 1e-4 1e-2 1 1e2 1e4], ...
    'mask_policy','Eight common target masks, always including DD','failure_position_m',5);
files=[dir(fullfile(root,'*.m'));dir(fullfile(root,'*.sh'));dir(fullfile(code,'fas','localization','*.m'))];
source=struct('file',{},'sha256',{});
for k=1:numel(files)
    path=fullfile(files(k).folder,files(k).name); f=fopen(path,'rb'); b=fread(f,inf,'*uint8'); fclose(f);
    source(end+1)=struct('file',strrep(path(numel(code)+2:end),'\','/'),'sha256',fas_hash(b));
end
[~,order]=sort({source.file}); source=source(order);
manifest=struct('profile',profile,'input_manifest_id',input.id,'localization_manifest_id',loc.id, ...
    'options',input.options,'parameters',input.parameters,'settings',settings,'source',source, ...
    'base_source',base,'total_cases',3900,'formal_observations','Original dimensions, bandwidth and CPI; two RIS configurations', ...
    'primary_snr_db',-20:5:10,'oracle_policy','Per-realization hindsight bank selection; diagnostic only, not a bound or achievable method');
manifest.id=fas_hash(unicode2native(jsonencode(manifest),'UTF-8'));
if ~exist(fullfile(output,'samples'),'dir'), mkdir(fullfile(output,'samples')); end
mp=fullfile(output,'manifest.json');
if exist(mp,'file')
    prior=jsondecode(fileread(mp)); assert(strcmp(prior.id,manifest.id),'Manifest mismatch.');
else, fas_write_json(mp,manifest); end
progress=struct('worker',worker,'workers',workers,'pid',feature('getpid'),'manifest_id',manifest.id, ...
    'state','RUNNING','completed',0,'assigned',numel(worker:workers:3899),'trial',0,'snr_db',0,'phase','','updated_utc','');
update('initializing');
try
    for trial=0:299
        for si=1:13
            if mod(trial*13+si-1,workers)~=worker, continue; end
            progress.trial=trial; progress.snr_db=input.options.snr_db(si);
            name=sprintf('snr_%02d_mc_%04d.mat',si,trial); dest=fullfile(output,'samples',name);
            if exist(dest,'file')
                prior=load(dest,'manifest_id'); assert(strcmp(prior.manifest_id,manifest.id));
                progress.completed=progress.completed+1; update('resumed checkpoint'); continue;
            end
            oldpath=fullfile(original,'samples',name); locpath=fullfile(localization,'samples',name);
            old=load(oldpath,'result','manifest_id'); located=load(locpath,'result','manifest_id');
            assert(strcmp(old.manifest_id,input.id) && strcmp(located.manifest_id,loc.id));
            assert(old.result.trial==trial && old.result.snr_index==si && old.result.snr_db==progress.snr_db);
            result=pr_case(old.result,located.result,settings,@update);
            result.input_sha256={hash_file(oldpath),hash_file(locpath)};
            manifest_id=manifest.id; temporary=[dest,'.tmp.mat'];
            save(temporary,'result','manifest_id','-v7'); movefile(temporary,dest,'f');
            progress.completed=progress.completed+1; update('checkpoint saved');
        end
    end
    progress.state='COMPLETE'; update('worker complete');
catch err
    progress.state='FAILED'; update(getReport(err,'extended','hyperlinks','off')); rethrow(err);
end
if workers==1, aggregate_path_reliability(output,original,localization); end
    function update(phase)
        progress.phase=phase; progress.updated_utc=char(datetime('now','TimeZone','UTC','Format','yyyy-MM-dd''T''HH:mm:ss''Z'''));
        fas_write_json(fullfile(output,sprintf('worker_%d.json',worker)),progress);
        fprintf('[%s] worker=%d MC=%d SNR=%g saved=%d/%d %s\n',progress.updated_utc,worker,progress.trial, ...
            progress.snr_db,progress.completed,progress.assigned,phase);
    end
end

function value=hash_file(path)
f=fopen(path,'rb'); assert(f>=0); bytes=fread(f,inf,'*uint8'); fclose(f); value=fas_hash(bytes);
end
