function loc_convergence_audit(code,input,output)
% Predetermined MC 0,1,2 at 10 dB; extend both controls' optimization budget.
cd(code); addpath(code,fullfile(code,'fas'),fullfile(code,'fas','localization')); maxNumCompThreads(2);
assert(~ispc,'Full-size convergence audit is server-only.');
if ~exist(output,'dir'), mkdir(output); end
manifest=jsondecode(fileread(fullfile(input,'manifest.json')));
assert(strcmp(manifest.profile,'full') && manifest.total_cases==3900);
settings=struct('iterations',160,'ris_rounds',2,'oracle',true);
progress=struct('state','RUNNING','pid',feature('getpid'),'completed',0,'expected',3, ...
    'input_manifest_id',manifest.id,'trial',0,'phase','initializing','updated_utc','');
update('initializing');
try
    for trial=0:2
        progress.trial=trial;
        dest=fullfile(output,sprintf('audit_mc_%04d.mat',trial));
        if exist(dest,'file')
            saved=load(dest,'input_manifest_id','settings');
            assert(strcmp(saved.input_manifest_id,manifest.id) && isequal(saved.settings,settings));
            progress.completed=progress.completed+1; update('resumed audit checkpoint'); continue;
        end
        source=fullfile(input,'samples',sprintf('snr_13_mc_%04d.mat',trial));
        while ~exist(source,'file')
            update('waiting for original full-run checkpoint');
            state=strtrim(fileread(fullfile(input,'state')));
            assert(strcmp(state,'RUNNING'),'Input experiment stopped before required checkpoint.');
            pause(30);
        end
        loaded=load(source,'result','manifest_id'); r=loaded.result;
        assert(strcmp(loaded.manifest_id,manifest.id) && r.trial==trial && r.snr_db==10 && isfield(r,'oracle'));
        p=r.p; assert(p.N==12672 && p.K==256 && p.Ntx*p.Nty==16 && p.Mx*p.My==64);
        [obs,~]=fas_fine_observations(r.coarse,p,0,r.seed+20);
        truth=loc_information_cache(p.truth,p,obs,p.alpha);
        audit=struct('trial',trial,'snr_db',10,'input_seed',r.seed,'groups',{cell(1,2)});
        for group=1:2
            if group==1
                cache=loc_information_cache(r.coarse,p,obs,ones(p.Q,1));
                pf=r.positions{1}; pm=r.positions{2}; df=r.design{1}; dm=r.design{2};
                oldfixed=r.search{1}.peb; oldfas=r.search{2}.peb; label='coarse design';
            else
                cache=truth; o=r.oracle; pf=o.fixed_positions; pm=o.fas_positions;
                df=o.fixed_design; dm=o.fas_design; oldfixed=o.fixed_search.peb; oldfas=o.fas_search.peb; label='oracle design';
            end
            before=loc_information(cache,pf,df); assert(abs(before/oldfixed-1)<1e-9);
            before=loc_information(cache,pm,dm); assert(abs(before/oldfas-1)<1e-9);
            p0=p; p0.tx_positions=pf; p1=p; p1.tx_positions=pm;
            transported=fas_transport_beams(cache.z,p1,p0,dm);
            starts={struct('positions',pf,'design',{df}),struct('positions',pf,'design',{transported})};
            update([label,' fixed budget extension']);
            [fixed,fd,fi]=loc_search(cache,starts,false,settings,@update);
            starts={struct('positions',pm,'design',{dm}),struct('positions',fixed,'design',{fd})};
            update([label,' FAS budget extension']);
            [fluid,md,mi]=loc_search(cache,starts,true,settings,@update);
            assert(fi.peb<=oldfixed*(1+1e-9) && mi.peb<=oldfas*(1+1e-9));
            audit.groups{group}=struct('label',label,'old_fixed_objective',oldfixed,'old_fas_objective',oldfas, ...
                'new_fixed_objective',fi.peb,'new_fas_objective',mi.peb, ...
                'fixed_improvement_percent',100*(1-fi.peb/oldfixed), ...
                'fas_improvement_percent',100*(1-mi.peb/oldfas), ...
                'old_relative_gain_percent',100*(1-oldfas/oldfixed), ...
                'new_relative_gain_percent',100*(1-mi.peb/fi.peb), ...
                'true_fixed_peb',loc_information(truth,fixed,fd), ...
                'true_fas_peb',loc_information(truth,fluid,md), ...
                'fixed_positions',fixed,'fas_positions',fluid,'fixed_design',{fd},'fas_design',{md}, ...
                'fixed_search',fi,'fas_search',mi);
        end
        input_manifest_id=manifest.id; temporary=[dest,'.tmp.mat'];
        save(temporary,'audit','input_manifest_id','settings','-v7'); movefile(temporary,dest,'f');
        summary=audit;
        for group=1:2
            summary.groups{group}=rmfield(summary.groups{group},{'fixed_positions','fas_positions','fixed_design','fas_design','fixed_search','fas_search'});
        end
        fas_write_json(fullfile(output,sprintf('audit_mc_%04d.json',trial)),summary);
        progress.completed=progress.completed+1; update('audit checkpoint saved');
    end
    assert(progress.completed==3); progress.state='COMPLETE'; update('all convergence comparisons complete');
catch err
    progress.state='FAILED'; update(getReport(err,'extended','hyperlinks','off')); rethrow(err);
end
    function update(phase)
        progress.phase=phase;
        progress.updated_utc=char(datetime('now','TimeZone','UTC','Format','yyyy-MM-dd''T''HH:mm:ss''Z'''));
        fas_write_json(fullfile(output,'progress.json'),progress);
        fprintf('[%s] MC=%d audits=%d/3 %s\n',progress.updated_utc,progress.trial,progress.completed,phase);
    end
end
