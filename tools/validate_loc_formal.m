function validate_loc_formal(code,oldrun,audit_file,output)
cd(code); addpath(code,fullfile(code,'fas'),fullfile(code,'fas','localization')); maxNumCompThreads(2);
assert(~ispc,'Formal-size validation is server-only.');
references=jsondecode(fileread(audit_file)); rows=struct([]);
for trial=0:2
    a=load(fullfile(oldrun,'samples',sprintf('snr_13_mc_%04d.mat',trial)),'result'); r=a.result;
    p=r.p; p.ris_enabled=true;
    assert(p.N==12672 && p.K==256 && p.Mx*p.My==64 && p.Ntx*p.Nty==16 && p.ris_side^2==256);
    [obs,~]=fas_fine_observations(r.coarse,p,0,r.seed+20);
    cache=loc_information_cache(p.truth,p,obs,p.alpha);
    for b=[2 4]
        [peb,information]=loc_information(cache,r.design_info{b}.positions,r.design{b},r.noise_power);
        if b==2, reference=references(trial+1).fixed; else, reference=references(trial+1).fas; end
        fisher_error=norm(information.F-reference.fisher_information,'fro')/norm(reference.fisher_information,'fro');
        peb_error=abs(peb/reference.peb_m-1);
        assert(fisher_error<1e-4 && peb_error<1e-5,'New cache disagrees with prior independent full-size diagnostic.');
        entry=struct('trial',trial,'method',r.methods{b},'fisher_relative_error',fisher_error,'peb_relative_error',peb_error);
        if isempty(rows), rows=entry; else, rows(end+1)=entry; end
    end
end
fas_write_json(output,struct('passed',true,'scope','Three formal-size cases, compared with independent echo finite differences', ...
    'checks',rows,'matlab',version));
disp(struct2table(rows));
end
