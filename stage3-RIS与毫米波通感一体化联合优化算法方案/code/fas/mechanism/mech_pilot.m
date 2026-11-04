function mech_pilot(original,prior,output)
root=fileparts(mfilename('fullpath')); code=fileparts(fileparts(root));
cd(code); addpath(root,fileparts(root),fullfile(fileparts(root),'localization'),code); maxNumCompThreads(2);
assert(~ispc,'Full-size pilot is server-only.'); if ~exist(output,'dir'), mkdir(output); end
file='snr_13_mc_0000.mat'; a=load(fullfile(original,'samples',file),'result'); b=load(fullfile(prior,'samples',file),'result');
settings=struct('iterations',40,'ris_rounds',1); summary=struct([]);
for loss=[0 80]
    result=mech_case(a.result,b.result,loss,settings,@(s) fprintf('%s\n',s));
    assert(all(isfinite(result.position_errors),'all'));
    for k=1:5
        pc=result.p; pc.ris_enabled=k<=3; pc.tx_positions=result.positions{k};
        [~,ok]=fas_design_score(result.coarse,pc,result.design{k}); assert(ok);
        assert(fas_positions_valid(pc.tx_positions,pc,fas_options('full')));
    end
    save(fullfile(output,sprintf('pilot_loss_%02d.mat',loss)),'result','settings','-v7');
    entry=struct('dd_loss_db',loss,'profile','server-full-size-pilot','passed',true,'seconds',result.seconds, ...
        'methods',{result.methods},'peb',result.peb,'peb_isinf',isinf(result.peb), ...
        'rmse',sqrt(mean(result.position_errors.^2,1)),'failure',result.failure);
    if isempty(summary), summary=entry; else, summary(end+1)=entry; end
end
fas_write_json(fullfile(output,'pilot.json'),summary);
end
