function run_uav_foundation(profile,output,worker,workers)
root=fileparts(mfilename('fullpath')); code=fileparts(root); addpath(root,code); maxNumCompThreads(2);
if nargin<3, worker=0; workers=1; end
cfg=uav_config(profile);
assert(~strcmp(profile,'full') || ~ispc,'Formal simulations run on the server.');
assert(worker>=0 && worker<workers && worker==fix(worker));
if strcmp(profile,'pilot'), trials=0; else, trials=0:cfg.mc-1; end
files=[dir(fullfile(root,'*.m'));dir(fullfile(root,'*.sh'))];
base={'build_default_params.m','channel_geometry.m','joint_estimator_fast.m','coarse_array_angles.m', ...
    'prepare_ris_observation.m','refine_ris_parameters.m','evaluate_estimation.m'};
for k=1:numel(base), files(end+1)=dir(fullfile(code,base{k})); end
source=struct('file',{},'sha256',{});
for k=1:numel(files)
    path=fullfile(files(k).folder,files(k).name); f=fopen(path,'rb'); assert(f>=0);
    bytes=fread(f,inf,'*uint8'); fclose(f);
    source(end+1)=struct('file',strrep(path(numel(code)+2:end),'\','/'),'sha256',uav_hash(bytes));
end
[~,ix]=sort({source.file}); source=source(ix);
example=struct('targets',cfg.targets,'prior',cfg.targets,'scatter_phase',[0 0]);
p=uav_parameters(cfg,example,cfg.hover,1);
manifest=struct('config',cfg,'source',source,'total_cases',numel(trials)*numel(cfg.rcs_m2), ...
    'waveform',struct('fc',p.fc,'N',p.N,'K_per_stage',p.K,'Tx',p.Ntx*p.Nty, ...
    'Rx',p.Mx*p.My,'RIS',p.ris_side^2,'ris_bits',p.ris_bits,'bandwidth_hz',p.B, ...
    'coarse_n',p.coarse_n,'coarse_l',p.coarse_l,'fine_n',p.fine_n,'fine_l',p.fine_l, ...
    'acquisition_s',2*p.K*p.Ts,'noise_w',p.noise_w), ...
    'scope','LoS, stationary targets, independent hover deployments; no trajectory/flight-energy claim');
manifest.id=uav_hash(unicode2native(jsonencode(manifest),'UTF-8'));
if ~exist(fullfile(output,'samples'),'dir'), mkdir(fullfile(output,'samples')); end
mp=fullfile(output,'manifest.json');
if exist(mp,'file')
    previous=jsondecode(fileread(mp)); assert(strcmp(previous.id,manifest.id),'Manifest mismatch.');
else, uav_write_json(mp,manifest); end
progress=struct('worker',worker,'workers',workers,'pid',feature('getpid'),'manifest_id',manifest.id, ...
    'state','RUNNING','completed',0,'assigned',numel(worker:workers:manifest.total_cases-1), ...
    'trial',0,'rcs_m2',0,'phase','','updated_utc','');
update('initializing');
try
    for trial=trials
        for ri=1:numel(cfg.rcs_m2)
            index=trial*numel(cfg.rcs_m2)+ri-1;
            if mod(index,workers)~=worker, continue; end
            progress.trial=trial; progress.rcs_m2=cfg.rcs_m2(ri);
            dest=fullfile(output,'samples',sprintf('mc_%04d_rcs_%02d.mat',trial,ri));
            if exist(dest,'file')
                previous=load(dest,'manifest_id'); assert(strcmp(previous.manifest_id,manifest.id));
                progress.completed=progress.completed+1; update('resumed checkpoint'); continue;
            end
            result=uav_case(cfg,trial,ri,@update); manifest_id=manifest.id;
            temporary=[dest,'.tmp.mat']; save(temporary,'result','manifest_id','-v7');
            movefile(temporary,dest,'f'); progress.completed=progress.completed+1; update('checkpoint saved');
        end
    end
    progress.state='COMPLETE'; update('worker complete');
catch err
    progress.state='FAILED'; update(getReport(err,'extended','hyperlinks','off')); rethrow(err);
end
if workers==1, aggregate_uav_foundation(output); end
    function update(phase)
        progress.phase=phase;
        progress.updated_utc=char(datetime('now','TimeZone','UTC','Format','yyyy-MM-dd''T''HH:mm:ss''Z'''));
        uav_write_json(fullfile(output,sprintf('worker_%d.json',worker)),progress);
        fprintf('[%s] worker=%d MC=%d RCS=%g saved=%d/%d %s\n',progress.updated_utc, ...
            worker,progress.trial,progress.rcs_m2,progress.completed,progress.assigned,phase);
    end
end
