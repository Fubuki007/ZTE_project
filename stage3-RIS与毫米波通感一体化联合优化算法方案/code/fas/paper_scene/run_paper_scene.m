function run_paper_scene(profile,output,worker,workers)
root=fileparts(mfilename('fullpath')); code=fileparts(fileparts(root));
cd(code); addpath(root,code,fileparts(root)); maxNumCompThreads(2);
if nargin<3, worker=0; workers=1; end
assert(ismember(profile,{'full','smoke'}) && (~ispc || strcmp(profile,'smoke')));
settings=struct('rounds',4,'iterations',40); mc=300;
if strcmp(profile,'smoke'), mc=1; settings=struct('rounds',1,'iterations',5); end
rice=[-inf 10 inf]; labels={'Rayleigh','Rician_10dB','LoS'};
files=dir(fullfile(root,'*.m')); sources=struct('file',{},'sha256',{});
for k=1:numel(files)
    path=fullfile(root,files(k).name); f=fopen(path,'rb'); bytes=fread(f,inf,'*uint8'); fclose(f);
    sources(end+1)=struct('file',files(k).name,'sha256',fas_hash(bytes));
end
manifest=struct('profile',profile,'mc',mc,'settings',settings,'rice_labels',{labels}, ...
    'source',sources,'base_source',fas_source_identity(),'total_cases',mc*numel(rice), ...
    'scene','Paper-inspired weak direct DD/RR model; original full arrays, bandwidth, CPI and Tx footprint', ...
    'normalization','G fixed-reference Frobenius norm sqrt(Ntx); direct user reference norm sqrt(Ntx); fixed across methods/ports', ...
    'known_channel','Oracle full field and target geometry as in paper; one target and one user', ...
    'metrics','Paper narrowband SNR and oracle wideband expected-symbol position bound; no actual localization RMSE', ...
    'limitations','Not a physical pathloss reproduction; no port-training cost; only 4 guard symbols deducted; finite 32 plane-wave scattering model');
manifest.id=fas_hash(unicode2native(jsonencode(manifest),'UTF-8'));
if ~exist(output,'dir'), mkdir(output); end
if ~exist(fullfile(output,'samples'),'dir'), mkdir(fullfile(output,'samples')); end
path=fullfile(output,'manifest.json');
if exist(path,'file'), old=jsondecode(fileread(path)); assert(strcmp(old.id,manifest.id));
else, fas_write_json(path,manifest); end
progress=struct('worker',worker,'workers',workers,'pid',feature('getpid'),'manifest_id',manifest.id, ...
    'state','RUNNING','completed',0,'assigned',numel(worker:workers:manifest.total_cases-1),'trial',0,'rice_label','','phase','','updated_utc','');
update('initializing');
try
    for trial=0:mc-1
        for ri=1:numel(rice)
            if mod(trial*numel(rice)+ri-1,workers)~=worker, continue; end
            progress.trial=trial; progress.rice_label=labels{ri};
            dest=fullfile(output,'samples',sprintf('rice_%02d_mc_%04d.mat',ri,trial));
            if exist(dest,'file')
                old=load(dest,'manifest_id'); assert(strcmp(old.manifest_id,manifest.id));
                progress.completed=progress.completed+1; update('resumed checkpoint'); continue;
            end
            rng(917300+trial,'twister'); p=build_default_params();
            assert(p.N==12672 && p.K==256 && p.Ntx*p.Nty==16 && p.Mx*p.My==64 && p.ris_side^2==256);
            if strcmp(profile,'smoke')
                p.N=128; p.K=16; p.Mx=3; p.My=3; p.ris_side=4; p.fine_n=32; p.fine_l=12;
                p.B=p.N*p.delta_f; p.fref=p.fc-floor(p.N/2)*p.delta_f;
            end
            result=paper_case(p,trial,rice(ri),settings,@update); result.rice_index=ri;
            manifest_id=manifest.id; temporary=[dest,'.tmp.mat']; save(temporary,'result','manifest_id','-v7');
            movefile(temporary,dest,'f'); progress.completed=progress.completed+1; update('checkpoint saved');
        end
    end
    progress.state='COMPLETE'; update('worker complete');
catch err
    progress.state='FAILED'; update(getReport(err,'extended','hyperlinks','off')); rethrow(err);
end
if workers==1, aggregate_paper_scene(output); end
    function update(phase)
        progress.phase=phase; progress.updated_utc=char(datetime('now','TimeZone','UTC','Format','yyyy-MM-dd''T''HH:mm:ss''Z'''));
        fas_write_json(fullfile(output,sprintf('worker_%d.json',worker)),progress);
        fprintf('[%s] worker=%d MC=%d %s saved=%d/%d %s\n',progress.updated_utc,worker, ...
            progress.trial,progress.rice_label,progress.completed,progress.assigned,phase);
    end
end
