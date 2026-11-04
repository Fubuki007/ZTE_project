function report=paper_pilot(output)
root=fileparts(mfilename('fullpath')); code=fileparts(fileparts(root));
cd(code); addpath(root,code,fileparts(root)); maxNumCompThreads(2);
if ~exist(output,'dir'), mkdir(output); end
rice=[-inf 10 inf]; labels={'Rayleigh','Rician_10dB','LoS'}; report=struct([]);
for i=1:numel(rice)
    rng(917300,'twister'); p=build_default_params();
    result=paper_case(p,0,rice(i),struct('rounds',4,'iterations',40));
    save(fullfile(output,sprintf('pilot_%d.mat',i)),'result','-v7');
    entry=struct('channel',labels{i},'seconds',result.seconds,'snr_db',result.snr_db, ...
        'peb',result.peb,'peb_isinf',isinf(result.peb),'sinr',result.sinr, ...
        'fas_move_lambda',norm(result.design{4}.X-result.design{3}.X,'fro'),'passed',true);
    if i==1, report=entry; else, report(i)=entry; end
    fas_write_json(fullfile(output,'pilot.json'),report); disp(report(i));
end
end
