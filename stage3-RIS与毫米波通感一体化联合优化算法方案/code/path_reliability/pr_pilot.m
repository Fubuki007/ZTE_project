function evidence=pr_pilot(original,localization,output)
root=fileparts(mfilename('fullpath')); code=fileparts(root); cd(code);
addpath(root,code,fullfile(code,'fas'),fullfile(code,'fas','localization')); maxNumCompThreads(2);
if ~exist(output,'dir'), mkdir(output); end
for k=1:2
    if k==1, si=7; else, si=13; end
    name=sprintf('snr_%02d_mc_0000.mat',si);
    a=load(fullfile(original,'samples',name)); b=load(fullfile(localization,'samples',name));
    p=a.result.p;
    assert(p.N==12672 && p.K==256 && p.Ntx*p.Nty==16 && p.Mx*p.My==64 && p.ris_side==16 && p.ris_bits==2);
    result=pr_case(a.result,b.result,struct('no_ris_iterations',40),@(s) fprintf('%s\n',s));
    save(fullfile(output,sprintf('pilot_%d.mat',k)),'result','-v7');
    evidence(k)=struct('snr_db',result.snr_db,'passed',all(result.feasible) && all(result.baseline_feasible), ...
        'N',p.N,'K',p.K,'tx',16,'rx',64,'ris',256,'fine_n',p.fine_n,'fine_l',p.fine_l, ...
        'seconds',result.seconds,'legacy_error',result.legacy_error, ...
        'rmse',squeeze(sqrt(mean(result.position_errors.^2,1))), ...
        'baseline_rmse',sqrt(mean(result.baseline_errors.^2,1)));
    assert(evidence(k).passed);
    fas_write_json(fullfile(output,'pilot.json'),evidence);
end
end
