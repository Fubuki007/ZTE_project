function run_uav_snr_angle(profile,output,worker,workers)
root=fileparts(mfilename('fullpath')); uav=fileparts(root); code=fileparts(uav);
addpath(root,uav,code); maxNumCompThreads(2);
if nargin<3, worker=0; workers=1; end
assert(ismember(profile,{'pilot','full'}) && ~ispc);
assert(worker>=0 && worker<workers && worker==fix(worker));
cfg=uav_snr_angle_config('full');
trials=0:cfg.mc-1; if strcmp(profile,'pilot'), trials=0; end
source_files=[dir(fullfile(root,'*.m'));dir(fullfile(root,'*.sh'))];
uav_files={'uav_config.m','uav_parameters.m','uav_design.m','uav_coarse.m', ...
    'uav_echo.m','uav_hash.m','uav_write_json.m'};
code_files={'build_default_params.m','channel_geometry.m','prepare_ris_observation.m', ...
    'refine_ris_parameters.m','evaluate_estimation.m','joint_estimator_fast.m', ...
    'coarse_array_angles.m'};
source=repmat(struct('file','','sha256',''), ...
    1,numel(source_files)+numel(uav_files)+numel(code_files));
source_index=0;
for k=1:numel(source_files)
    path=fullfile(source_files(k).folder,source_files(k).name);
    source_index=source_index+1;
    source(source_index)=struct('file',strrep(path(numel(code)+2:end),'\','/'), ...
        'sha256',filehash(path));
end
for k=1:numel(uav_files)
    path=fullfile(uav,uav_files{k});
    source_index=source_index+1;
    source(source_index)=struct('file',strrep(path(numel(code)+2:end),'\','/'), ...
        'sha256',filehash(path));
end
for k=1:numel(code_files)
    path=fullfile(code,code_files{k});
    source_index=source_index+1;
    source(source_index)=struct('file',strrep(path(numel(code)+2:end),'\','/'), ...
        'sha256',filehash(path));
end
[~,order]=sort({source.file}); source=source(order);
total_cases=numel(trials)*numel(cfg.rcs_m2)*numel(cfg.snr_db);
manifest=struct('profile',profile,'config',cfg,'trials',trials, ...
    'total_cases',total_cases,'source',source, ...
    'angle_metric','Spherical direction error in degrees; RMSE over both targets and trials with RIS fine acquisition', ...
    'snr_definition','Reference SNR at 200 m and 1 m^2 RCS, normalized to the unit-RCS reference echo', ...
    'ris_scope','RIS enabled for fine acquisition after direct-path coarse range/angle capture', ...
    'assumptions',{{'Fixed 80 m hover point and stationary targets', ...
    'Same paired geometry and random seeds across RCS and SNR', ...
    'Thermal receiver noise scaled to set reference SNR; power, array, subcarriers and CPI unchanged', ...
    'Failed capture or infeasible RIS fine designs remain in coverage/failure statistics'}});
manifest.id=uav_hash(unicode2native(jsonencode(manifest),'UTF-8'));
if ~exist(fullfile(output,'samples'),'dir'), mkdir(fullfile(output,'samples')); end
manifest_path=fullfile(output,'manifest.json');
if exist(manifest_path,'file')
    previous=jsondecode(fileread(manifest_path)); assert(strcmp(previous.id,manifest.id));
else
    uav_write_json(manifest_path,manifest);
end
progress=struct('worker',worker,'workers',workers,'pid',feature('getpid'), ...
    'manifest_id',manifest.id,'state','RUNNING','completed',0, ...
    'assigned',numel(worker:workers:total_cases-1),'trial',0,'rcs_m2',0, ...
    'snr_db',0,'phase','','updated_utc','');
update('initializing');
try
    for trial=trials
        for ri=1:numel(cfg.rcs_m2)
            for si=1:numel(cfg.snr_db)
                index=(trial*numel(cfg.rcs_m2)+ri-1)*numel(cfg.snr_db)+si-1;
                if mod(index,workers)~=worker, continue; end
                progress.trial=trial; progress.rcs_m2=cfg.rcs_m2(ri);
                progress.snr_db=cfg.snr_db(si);
                name=sprintf('mc_%04d_rcs_%02d_snr_%02d.mat',trial,ri,si);
                dest=fullfile(output,'samples',name);
                if exist(dest,'file')
                    old=load(dest,'manifest_id'); assert(strcmp(old.manifest_id,manifest.id));
                    progress.completed=progress.completed+1; update('resumed checkpoint'); continue;
                end
                started=tic;
                result=uav_snr_angle_case(cfg,trial,ri,si,@update);
                result.seconds=toc(started); manifest_id=manifest.id;
                temp=[dest,'.tmp.mat']; save(temp,'result','manifest_id','-v7');
                movefile(temp,dest,'f'); progress.completed=progress.completed+1;
                update('checkpoint saved');
            end
        end
    end
    progress.state='COMPLETE'; update('worker complete');
catch err
    progress.state='FAILED'; update(getReport(err,'extended','hyperlinks','off')); rethrow(err);
end
if workers==1, aggregate_uav_snr_angle(output); end
    function update(phase)
        progress.phase=phase;
        progress.updated_utc=char(datetime('now','TimeZone','UTC', ...
            'Format','yyyy-MM-dd''T''HH:mm:ss''Z'''));
        uav_write_json(fullfile(output,sprintf('worker_%d.json',worker)),progress);
        fprintf('[%s] worker=%d MC=%d RCS=%g SNR=%g dB saved=%d/%d %s\n', ...
            progress.updated_utc,worker,progress.trial,progress.rcs_m2, ...
            progress.snr_db,progress.completed,progress.assigned,phase);
    end
end

function h=filehash(path)
f=fopen(path,'rb'); assert(f>=0); bytes=fread(f,inf,'*uint8'); fclose(f);
h=uav_hash(bytes);
end
