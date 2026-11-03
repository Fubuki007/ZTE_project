function audit_loc_results(code,run,output,original)
% Final read-only audit of every completed simulation checkpoint.
if nargin<4, original=''; end
cd(code); addpath(code,fullfile(code,'fas')); maxNumCompThreads(2);
manifest=jsondecode(fileread(fullfile(run,'manifest.json')));
progress=jsondecode(fileread(fullfile(run,'progress.json')));
full=strcmp(manifest.profile,'full'); options=manifest.options;
assert(full || strcmp(manifest.profile,'smoke'));
assert(~full || ~ispc,'Full-result audit is server-only.');
assert(progress.complete && progress.total_completed==manifest.total_cases);
assert(strcmp(manifest.id,progress.manifest_id) && all(progress.counts==options.mc));
revision=struct('aggregation_sha256','smoke-only'); expected_oracles=0;
if full
    revision=jsondecode(fileread(fullfile(run,'aggregation_revision.json')));
    assert(revision.complete && strcmp(manifest.id,revision.input_manifest_id));
    assert(manifest.total_cases==3900 && options.mc==300 && numel(options.snr_db)==13);
    old_manifest=jsondecode(fileread(fullfile(original,'manifest.json')));
    assert(strcmp(old_manifest.id,manifest.input_manifest_id)); expected_oracles=300;
end
assert(progress.oracle_completed==expected_oracles);
if ~exist(output,'dir'), mkdir(output); end
rows=struct([]); designs=struct([]); count=0; oracles=0;
names=cellstr(manifest.methods); phase_levels=exp(1j*2*pi*(0:3)/4);
for trial=0:options.mc-1
    for si=1:numel(options.snr_db)
        a=load(fullfile(run,'samples',sprintf('snr_%02d_mc_%04d.mat',si,trial)),'result','manifest_id');
        r=a.result; p=r.p;
        assert(strcmp(a.manifest_id,manifest.id) && r.trial==trial && r.snr_index==si);
        assert(isequal(r.methods(:),names(:)) && r.snr_db==manifest.options.snr_db(si));
        assert(r.seed==options.seed+trial*10000+si*100);
        if full
            assert(p.N==12672 && p.K==256 && p.Ntx*p.Nty==16 && p.Mx*p.My==64 && p.ris_side^2==256 && p.ris_bits==2);
            assert(p.fine_n==256 && p.fine_l==64 && p.coarse_n==384 && p.coarse_l==64 && p.K_stream==2);
            old=load(fullfile(original,'samples',sprintf('snr_%02d_mc_%04d.mat',si,trial)),'result','manifest_id');
            assert(strcmp(old.manifest_id,manifest.input_manifest_id)); old=old.result;
            op=old.p; op.ris_enabled=true;
            assert(isequaln(p,op) && isequaln(r.coarse,old.coarse) && r.seed==old.seed && r.locked==old.locked);
            legacy=[2,find(strcmp(old.methods,'FAS_RIS_guard0')),4];
            assert(isequal(r.estimates(:,:,1:3),old.estimates(:,:,legacy)));
            assert(isequal(r.position_errors(:,1:3),old.position_errors(:,legacy)));
            assert(isequal(r.feasible(1:3),old.feasible(legacy)) && isequal(r.failure(1:3),old.failure(legacy)));
        end
        assert(all(isfinite(r.estimates),'all') && all(isfinite(r.position_errors),'all'));
        truth=channel_geometry(p.truth,p);
        for m=1:6
            g=channel_geometry(r.estimates(:,:,m),p); errors=vecnorm(g.position-truth.position,2,1).';
            assert(norm(errors-r.position_errors(:,m))<1e-8);
            expected_failure=~r.locked || ~r.feasible(m) || any(errors>options.failure_position_m);
            assert(r.failure(m)==expected_failure);
            entry=struct('trial',trial,'snr_db',r.snr_db,'method',string(names{m}), ...
                'locked',r.locked,'feasible',r.feasible(m),'failure',r.failure(m), ...
                'position_mse_m2',mean(errors.^2),'peb_m',r.peb(m),'case_seconds',r.seconds);
            if isempty(rows), rows=entry; else, rows(end+1)=entry; end
        end
        designed=r.locked && all(r.feasible([1 3]));
        assert(all(r.feasible(4:6)==designed));
        if designed
            [x,y]=ndgrid(0:p.Ntx-1,0:p.Nty-1); fixed=p.d*[x(:),y(:),zeros(p.Ntx*p.Nty,1)];
            assert(norm(r.positions{1}-fixed,'fro')<1e-12);
            assert(r.search{2}.peb<=r.search{1}.peb*(1+1e-9));
            for b=1:2
                positions=r.positions{b}; d=r.design{b}; pc=p; pc.tx_positions=positions;
                assert(fas_positions_valid(positions,p,options));
                assert(max(abs(positions/p.lambda/.1-round(positions/p.lambda/.1)),[],'all')<1e-8);
                [~,ok,sinr]=fas_design_score(r.coarse,pc,d); assert(ok);
                for s=1:2
                    assert(max(min(abs(d{s}.phase-phase_levels),[],2))<1e-10);
                    assert(norm(d{s}.W,'fro')<=1+1e-6);
                end
                trace=vertcat(r.search{b}.runs.trace);
                for k=1:numel(trace), assert(all(diff(trace(k).accepted_peb)<=1e-12)); end
                delta=vecnorm(positions-fixed,2,2)/p.lambda;
                entry=struct('trial',trial,'snr_db',r.snr_db,'method',string(names{3+b}), ...
                    'max_displacement_lambda',max(delta),'moved_elements',sum(delta>1e-8), ...
                    'minimum_sinr',min(sinr,[],'all'),'search_seconds',r.search{b}.seconds, ...
                    'objective',r.search{b}.peb,'continuous_objective',r.search{b}.continuous_peb, ...
                    'solver_runs',numel(trace),'iteration_limit_runs',sum([trace.exitflag]==0), ...
                    'negative_exit_runs',sum([trace.exitflag]<0));
                if isempty(designs), designs=entry; else, designs(end+1)=entry; end
            end
        end
        if isfield(r,'oracle')
            assert(r.snr_db==10); oracles=oracles+1; o=r.oracle;
            assert(o.fas_search.peb<=o.fixed_search.peb*(1+1e-9));
            pp={o.fixed_positions,o.fas_positions}; dd={o.fixed_design,o.fas_design};
            for b=1:2
                assert(fas_positions_valid(pp{b},p,options)); pc=p; pc.tx_positions=pp{b};
                [~,ok]=fas_design_score(p.truth,pc,dd{b}); assert(ok);
                assert(max(abs(pp{b}/p.lambda/.1-round(pp{b}/p.lambda/.1)),[],'all')<1e-8);
                for s=1:2
                    assert(max(min(abs(dd{b}{s}.phase-phase_levels),[],2))<1e-10);
                    assert(norm(dd{b}{s}.W,'fro')<=1+1e-6);
                end
            end
        end
        count=count+1;
    end
    if mod(trial+1,25)==0, fprintf('VERIFIED %d/%d localization checkpoints\n',count,manifest.total_cases); end
end
assert(count==manifest.total_cases && oracles==expected_oracles);
cases=struct2table(rows); design_table=struct2table(designs); metrics=readtable(fullfile(run,'metrics.csv')); difference=0; peb_difference=0;
assert(height(metrics)==6*numel(options.snr_db));
for k=1:height(metrics)
    selected=cases(cases.snr_db==metrics.snr_db(k) & cases.method==string(metrics.method{k}),:);
    assert(height(selected)==options.mc);
    difference=max(difference,abs(sqrt(mean(selected.position_mse_m2))-metrics.position_rmse_m(k)));
    assert(abs(mean(selected.failure)-metrics.failure_rate(k))<1e-12);
    assert(abs(mean(selected.feasible)-metrics.feasible_rate(k))<1e-12);
    assert(sum(isinf(selected.peb_m))==metrics.singular_information_cases(k));
    available=~isnan(selected.peb_m); assert(sum(available)==metrics.information_cases(k));
    value=sqrt(mean(selected.peb_m(available).^2));
    if isnan(value)
        assert(isnan(metrics.peb_rms_m(k)));
    elseif isinf(value)
        assert(isinf(metrics.peb_rms_m(k)));
    else
        assert(isfinite(metrics.peb_rms_m(k)));
        peb_difference=max(peb_difference,abs(value-metrics.peb_rms_m(k))/max(value,eps));
    end
end
assert(difference<1e-8 && peb_difference<1e-10);
writetable(cases,fullfile(output,'case_metrics.csv')); writetable(design_table,fullfile(output,'design_checks.csv'));
f=fopen([mfilename('fullpath'),'.m'],'rb'); bytes=fread(f,inf,'*uint8'); fclose(f);
fas_write_json(fullfile(output,'verification.json'),struct('complete',true,'profile',manifest.profile,'count',count,'oracle_count',oracles, ...
    'input_manifest_id',manifest.id,'aggregation_sha256',revision.aggregation_sha256, ...
    'audit_sha256',fas_hash(bytes),'rmse_max_difference',difference,'peb_max_relative_difference',peb_difference, ...
    'singular_information_entries',sum(isinf(cases.peb_m))));
fprintf('RESULT AUDIT PASSED: %s, %d cases, %d oracle comparisons\n',manifest.profile,count,oracles);
end
