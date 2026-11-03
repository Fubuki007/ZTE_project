function loc_pilot(oldrun,output)
root=fileparts(mfilename('fullpath')); code=fileparts(fileparts(root));
cd(code); addpath(root,fileparts(root),code); maxNumCompThreads(2);
assert(~ispc,'Formal-size pilot is server-only.');
if ~exist(output,'dir'), mkdir(output); end
old=load(fullfile(oldrun,'samples','snr_13_mc_0000.mat'),'result');
settings=struct('iterations',40,'ris_rounds',1,'oracle',true);
result=loc_case(old.result,settings);
save(fullfile(output,'pilot.mat'),'result','settings','-v7');
summary=struct('completed',true,'profile','full-size pilot, not MC conclusion', ...
    'trial',result.trial,'snr_db',result.snr_db,'seconds',result.seconds, ...
    'methods',{result.methods},'peb',result.peb,'position_rmse',sqrt(mean(result.position_errors.^2,1)), ...
    'fixed_search_seconds',result.search{1}.seconds,'fas_search_seconds',result.search{2}.seconds, ...
    'oracle_fixed_peb',result.oracle.fixed_peb,'oracle_fas_peb',result.oracle.fas_peb);
fas_write_json(fullfile(output,'pilot.json'),summary); disp(summary);
end
