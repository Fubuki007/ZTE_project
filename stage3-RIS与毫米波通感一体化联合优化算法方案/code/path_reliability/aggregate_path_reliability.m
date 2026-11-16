function aggregate_path_reliability(output,original,localization)
root=fileparts(mfilename('fullpath')); code=fileparts(root); cd(code);
addpath(root,code,fullfile(code,'fas'),fullfile(code,'fas','localization'));
m=jsondecode(fileread(fullfile(output,'manifest.json')));
assert(m.total_cases==3900 && numel(dir(fullfile(output,'samples','snr_*_mc_*.mat')))==3900, ...
    'PR:IncompleteRun','Incomplete run: all 3900 checkpoints are required.');
E=zeros(300,13,16); failed=false(300,13,16); locked=false(300,13); feasible=false(300,13,16);
max_error=0; max_replay=0; labels=cell(1,16);
selection_counts=zeros(13,2,3,14);
fid=fopen(fullfile(output,'case_metrics.csv'),'w'); assert(fid>=0); cleanup=onCleanup(@() fclose(fid));
fprintf(fid,'trial,snr_db,method,position_rmse_m,target1_error_m,target2_error_m,failure,feasible,locked\n');
for trial=0:299
    for si=1:13
        name=sprintf('snr_%02d_mc_%04d.mat',si,trial);
        item=load(fullfile(output,'samples',name)); r=item.result;
        oldpath=fullfile(original,'samples',name); locpath=fullfile(localization,'samples',name);
        a=load(oldpath); b=load(locpath); old=a.result; loc=b.result;
        assert(strcmp(item.manifest_id,m.id) && strcmp(a.manifest_id,m.input_manifest_id) && ...
            strcmp(b.manifest_id,m.localization_manifest_id));
        assert(r.trial==trial && r.snr_index==si && r.snr_db==m.options.snr_db(si));
        assert(isequaln(r.p,old.p) && isequal(r.coarse,old.coarse) && r.seed==old.seed && r.locked==old.locked);
        assert(strcmp(hash_file(oldpath),r.input_sha256{1}) && strcmp(hash_file(locpath),r.input_sha256{2}));
        locked(trial+1,si)=r.locked;
        for c=1:2
            if r.feasible(c)
                pc=r.p; pc.ris_enabled=true;
                if c==1, pc.tx_positions=old.design_info{2}.positions; else, pc.tx_positions=loc.positions{1}; end
                check_design(pc,r.design{c},r.coarse);
                bank=r.banks{c}; errors_bank=zeros(r.p.Q,size(bank.estimates,3));
                for k=1:size(bank.estimates,3), errors_bank(:,k)=position_errors(bank.estimates(:,:,k),r.p); end
                assert(max(abs(errors_bank-bank.candidate_position_errors),[],'all')<1e-7);
                [~,ia]=min(cellfun(@(f) f.aic,bank.fits(1:8)));
                [~,ib]=min(cellfun(@(f) f.bic,bank.fits(1:8)));
                ridge=[8,9:numel(bank.fits)]; [~,ig]=min(cellfun(@(f) f.gcv,bank.fits(ridge)));
                [~,io]=min(mean(errors_bank.^2,1));
                assert(isequal(bank.choice,[8 1 ia ib ridge(ig)]) && bank.oracle_choice==io);
                assert(isequal(bank.ridge_lambdas,m.settings.ridge_lambdas(:).'));
                for selector=1:3
                    chosen=bank.choice(selector+2);
                    selection_counts(si,c,selector,chosen)=selection_counts(si,c,selector,chosen)+1;
                end
                indices=[bank.choice,io];
                for k=2:7
                    assert(isequal(r.estimates(:,:,k,c),bank.estimates(:,:,indices(k-1))));
                end
                for k=1:numel(bank.fits)
                    f=bank.fits{k}; assert(all(diff(f.cost_history)<=1e-7*max(1,f.cost_history(1))));
                end
                expected=old.estimates(:,:,2); if c==2, expected=loc.estimates(:,:,4); end
                current=evaluate_estimation(r.estimates(:,:,1,c),r.p);
                max_replay=max(max_replay,max(abs(current.estimate-expected),[],'all'));
            end
            for k=1:7
                index=(c-1)*7+k; labels{index}=[r.conditions{c},'/',r.methods{k}];
                error=position_errors(r.estimates(:,:,k,c),r.p);
                max_error=max(max_error,max(abs(error-r.position_errors(:,k,c))));
                assert(r.failure(k,c)==(~r.locked || ~r.feasible(c) || any(error>5)));
                store(index,error,r.failure(k,c),r.feasible(c));
            end
        end
        for k=1:2
            index=14+k; labels{index}=r.baseline_names{k};
            error=position_errors(r.baseline_estimates(:,:,k),r.p);
            max_error=max(max_error,max(abs(error-r.baseline_errors(:,k))));
            assert(r.baseline_failure(k)==(~r.locked || ~r.baseline_feasible(k) || any(error>5)));
            store(index,error,r.baseline_failure(k),r.baseline_feasible(k));
        end
        if r.baseline_feasible(2)
            pn=r.p; pn.ris_enabled=false; pn.tx_positions=old.design_info{1}.positions;
            check_design(pn,r.no_ris_design,r.coarse);
        end
    end
end
assert(max_error<1e-7 && max_replay<1e-6);
rmse=squeeze(sqrt(mean(E,1))); failure_count=squeeze(sum(failed,1));
primary=find(ismember(m.options.snr_db,m.primary_snr_db)); assert(numel(primary)==7);
% Resample complete geometries, preserving every paired method and SNR.
rng(20261115,'twister'); B=4000; candidates=[3:6,10:13]; references=[repmat(2,1,4),repmat(9,1,4)];
draws=zeros(B,numel(candidates)); points=zeros(1,numel(candidates));
for k=1:numel(candidates)
    points(k)=100*mean(1-rmse(primary,candidates(k))./rmse(primary,references(k)));
end
for b=1:B
    rows=randi(300,300,1); boot=squeeze(sqrt(mean(E(rows,primary,:),1)));
    for k=1:numel(candidates), draws(b,k)=100*mean(1-boot(:,candidates(k))./boot(:,references(k))); end
end
comparisons=repmat(struct('method','','reference','', ...
    'mean_of_seven_snr_rmse_reductions_percent',0,'paired_bootstrap_95_percent',[0 0]), ...
    1,numel(candidates));
for k=1:numel(candidates)
    comparisons(k)=struct('method',labels{candidates(k)},'reference',labels{references(k)}, ...
        'mean_of_seven_snr_rmse_reductions_percent',points(k), ...
        'paired_bootstrap_95_percent',[quantile_local(draws(:,k),.025),quantile_local(draws(:,k),.975)]);
end
summary=struct('manifest_id',m.id,'cases',3900,'methods',{labels},'snr_db',m.options.snr_db, ...
    'rmse_m',rmse,'failure_count',failure_count,'coarse_locked',sum(locked,1), ...
    'feasible_count',squeeze(sum(feasible,1)),'primary_snr_db',m.primary_snr_db, ...
    'selection_counts',selection_counts,'selector_names',{{'AIC','BIC','Ridge_GCV'}}, ...
    'comparisons',comparisons,'bootstrap',struct('repetitions',B,'seed',20261115, ...
    'unit','Entire paired MC geometry across SNR','intervals','Exploratory marginal 95%, not multiplicity adjusted'), ...
    'oracle','Hindsight per-noise candidate selection; excludes legacy and is not achievable or a formal bound');
fas_write_json(fullfile(output,'summary.json'),summary);
save(fullfile(output,'summary.mat'),'E','failed','locked','feasible','labels','rmse','draws','-v7');
figure('Visible','off');
for c=1:2
    subplot(1,2,c); ix=(c-1)*7+[2 4 5 6];
    semilogy(m.options.snr_db,rmse(:,[ix 16]),'-o'); grid on;
    xlabel('Input SNR (dB)'); ylabel('Position RMSE (m)');
    legend([r.methods([2 4 5 6]),{'NoRIS PEB'}],'Interpreter','none','Location','southwest');
    title(r.conditions{c},'Interpreter','none');
end
set(gcf,'Position',[100 100 1200 460]); exportgraphics(gcf,fullfile(output,'comparison.png'),'Resolution',160); close(gcf);
verification=struct('complete',true,'cases',3900,'all_failures_retained',true, ...
    'manifest_id',m.id,'max_recomputed_position_error_difference_m',max_error, ...
    'max_legacy_parameter_replay_difference',max_replay, ...
    'audited','Input file hashes, seeds, parameters, selectors, estimates, errors, power, SINR, 2-bit phases and cost histories');
fas_write_json(fullfile(output,'verification.json'),verification);
    function store(index,error,isfailure,isfeasible)
        E(trial+1,si,index)=mean(error.^2); failed(trial+1,si,index)=isfailure; feasible(trial+1,si,index)=isfeasible;
        fprintf(fid,'%d,%g,%s,%.17g,%.17g,%.17g,%d,%d,%d\n',trial,r.snr_db,labels{index}, ...
            sqrt(mean(error.^2)),error(1),error(2),isfailure,isfeasible,r.locked);
    end
end

function error=position_errors(z,p)
c=evaluate_estimation(z,p); g=channel_geometry(c.estimate,p); truth=channel_geometry(p.truth,p);
error=vecnorm(g.position-truth.position,2,1).';
end

function check_design(p,d,z)
[~,ok]=fas_design_score(z,p,d); assert(ok);
for s=1:2
    assert(norm(d{s}.W,'fro')<=1+1e-6 && max(abs(abs(d{s}.phase)-1))<1e-8);
    quantized=angle(d{s}.phase)*2^p.ris_bits/(2*pi);
    assert(max(abs(quantized-round(quantized)))<1e-8);
end
end

function value=hash_file(path)
f=fopen(path,'rb'); bytes=fread(f,inf,'*uint8'); fclose(f); value=fas_hash(bytes);
end

function x=quantile_local(v,p)
v=sort(v); position=1+(numel(v)-1)*p; lo=floor(position); hi=ceil(position);
x=v(lo)+(position-lo)*(v(hi)-v(lo));
end
