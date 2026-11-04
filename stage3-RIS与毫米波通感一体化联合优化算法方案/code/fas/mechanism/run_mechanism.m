function run_mechanism(profile,original,prior,output,worker,workers)
root=fileparts(mfilename('fullpath')); code=fileparts(fileparts(root));
cd(code); addpath(root,fileparts(root),fullfile(fileparts(root),'localization'),code); maxNumCompThreads(2);
if nargin<5, worker=0; workers=1; end
assert(ismember(profile,{'full','smoke'}) && (~ispc || strcmp(profile,'smoke')));
assert(worker>=0 && worker<workers && worker==fix(worker));
base=fas_source_identity(); source=struct('file',{},'sha256',{});
folders={fullfile(fileparts(root),'localization'),root};
for folder=folders
    files=dir(fullfile(folder{1},'*.m'));
    for k=1:numel(files)
        path=fullfile(files(k).folder,files(k).name); f=fopen(path,'rb'); bytes=fread(f,inf,'*uint8'); fclose(f);
        source(end+1)=struct('file',strrep(path(numel(code)+2:end),'\','/'),'sha256',fas_hash(bytes));
    end
end
options=fas_options(profile); options.snr_db=10;
settings=struct('iterations',40,'ris_rounds',1);
losses=[0 20 40 60 80]; input_id='generated-smoke'; prior_id='generated-smoke';
if strcmp(profile,'full')
    a=jsondecode(fileread(fullfile(original,'manifest.json'))); b=jsondecode(fileread(fullfile(prior,'manifest.json')));
    audit=jsondecode(fileread(fullfile(prior,'audit','verification.json')));
    assert(strcmp(a.source.sha256,base.sha256) && strcmp(b.input_manifest_id,a.id));
    assert(a.options.mc==300 && b.total_cases==3900 && audit.complete && audit.count==3900);
    input_id=a.id; prior_id=b.id;
else
    losses=[0 40]; settings=struct('iterations',5,'ris_rounds',0);
end
names={'Fixed_uniform_RIS','Fixed_edge_RIS','FAS_RIS_guard0','FAS_RIS_guard4', ...
    'Fixed_uniform_noRIS','FAS_noRIS_guard0','FAS_noRIS_guard4'};
manifest=struct('profile',profile,'options',options,'dd_loss_db',losses,'settings',settings, ...
    'base_source',base,'source',source,'original_input_id',input_id,'localization_input_id',prior_id, ...
    'methods',{names},'total_cases',options.mc*numel(losses), ...
    'attenuation','Reciprocal BS-target amplitude factors [h^2 h h 1], h=10^(-DD_power_loss_dB/40)', ...
    'noise_policy','Original unblocked 10 dB noise variance, unchanged across attenuation and methods', ...
    'prior_policy','Shared original unblocked coarse prior; conditional fine-stage experiment, not a blocked coarse-acquisition test', ...
    'resource_policy','Original arrays, subcarriers, CPI, RF chains, aperture, power and user SINR; guard0/4 paired', ...
    'communication_policy','Controlled target-link attenuation only; user links are unchanged');
manifest.id=fas_hash(unicode2native(jsonencode(manifest),'UTF-8'));
if ~exist(output,'dir'), mkdir(output); end
if ~exist(fullfile(output,'samples'),'dir'), mkdir(fullfile(output,'samples')); end
mp=fullfile(output,'manifest.json');
if exist(mp,'file')
    saved=jsondecode(fileread(mp)); assert(strcmp(saved.id,manifest.id),'Manifest mismatch; use a new output directory.');
else
    fas_write_json(mp,manifest);
end
progress=struct('worker',worker,'workers',workers,'pid',feature('getpid'),'manifest_id',manifest.id, ...
    'state','RUNNING','completed',0,'assigned',numel(worker:workers:manifest.total_cases-1), ...
    'trial',0,'dd_loss_db',0,'phase','initializing','updated_utc','');
update('initializing');
try
    for trial=0:options.mc-1
        loaded=false;
        for li=1:numel(losses)
            if mod(trial*numel(losses)+li-1,workers)~=worker, continue; end
            progress.trial=trial; progress.dd_loss_db=losses(li);
            dest=fullfile(output,'samples',sprintf('loss_%02d_mc_%04d.mat',li,trial));
            if exist(dest,'file')
                saved=load(dest,'manifest_id'); assert(strcmp(saved.manifest_id,manifest.id));
                progress.completed=progress.completed+1; update('resumed checkpoint'); continue;
            end
            if ~loaded
                if strcmp(profile,'full')
                    file=sprintf('snr_13_mc_%04d.mat',trial);
                    a=load(fullfile(original,'samples',file),'result','manifest_id');
                    b=load(fullfile(prior,'samples',file),'result','manifest_id');
                    assert(strcmp(a.manifest_id,input_id) && strcmp(b.manifest_id,prior_id)); old=a.result; previous=b.result;
                    assert(old.trial==trial && previous.trial==trial && old.snr_index==13 && previous.snr_index==13);
                    assert(old.p.N==12672 && old.p.K==256 && old.p.Mx*old.p.My==64 && old.p.ris_side^2==256);
                else
                    smoke=fas_options('smoke'); old=fas_run_case(smoke,trial,2,@update);
                    previous=loc_case(old,struct('iterations',5,'ris_rounds',0,'oracle',false),@update);
                end
                loaded=true;
            end
            result=mech_case(old,previous,losses(li),settings,@update);
            manifest_id=manifest.id; temporary=[dest,'.tmp.mat'];
            save(temporary,'result','manifest_id','-v7'); movefile(temporary,dest,'f');
            progress.completed=progress.completed+1; update('checkpoint saved');
        end
    end
    progress.state='COMPLETE'; update('worker complete');
catch err
    progress.state='FAILED'; update(getReport(err,'extended','hyperlinks','off')); rethrow(err);
end
if workers==1, aggregate_mechanism(output); end
    function update(phase)
        progress.phase=phase; progress.updated_utc=char(datetime('now','TimeZone','UTC','Format','yyyy-MM-dd''T''HH:mm:ss''Z'''));
        fas_write_json(fullfile(output,sprintf('worker_%d.json',worker)),progress);
        fprintf('[%s] worker=%d MC=%d DD-loss=%g saved=%d/%d %s\n',progress.updated_utc,worker, ...
            progress.trial,progress.dd_loss_db,progress.completed,progress.assigned,phase);
    end
end
