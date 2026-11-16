function summary=aggregate_uav_foundation(output)
root=fileparts(mfilename('fullpath')); code=fileparts(root); addpath(root,code); maxNumCompThreads(2);
manifest=jsondecode(fileread(fullfile(output,'manifest.json'))); cfg=manifest.config;
if strcmp(cfg.profile,'pilot'), nmc=1; else, nmc=cfg.mc; end
nr=numel(cfg.rcs_m2); assert(manifest.total_cases==nmc*nr);
for k=1:numel(manifest.source)
    path=fullfile(code,manifest.source(k).file); f=fopen(path,'rb'); assert(f>=0);
    bytes=fread(f,inf,'*uint8'); fclose(f);
    assert(strcmp(uav_hash(bytes),manifest.source(k).sha256),'Source changed during run.');
end
files=dir(fullfile(output,'samples','mc_*_rcs_*.mat'));
assert(numel(files)==manifest.total_cases,'Expected every paired case before aggregation.');
mse=zeros(nmc,nr,4); coarse=mse; velocity=mse; failures=false(nmc,nr,4);
locked=failures; feasible=failures; elapsed=zeros(nmc,nr); row=0;
rows=cell(manifest.total_cases*4,18); min_sinr=inf; max_power=0; max_error_delta=0;
for trial=0:nmc-1
    for ri=1:nr
        path=fullfile(output,'samples',sprintf('mc_%04d_rcs_%02d.mat',trial,ri));
        item=load(path,'result','manifest_id'); r=item.result;
        assert(strcmp(item.manifest_id,manifest.id) && r.trial==trial && r.rcs_index==ri);
        assert(r.seed==cfg.seed+10000*trial && r.rcs_m2==cfg.rcs_m2(ri));
        assert(isequal(r.methods(:),cfg.methods(:)) && isequal(r.coarse(:,:,1),r.coarse(:,:,2)));
        for method=1:4
            p=r.parameters{method};
            assert(p.N==manifest.waveform.N && p.K==manifest.waveform.K_per_stage && p.fc==28e9);
            assert(p.Ntx*p.Nty==16 && p.Mx*p.My==64 && p.ris_side^2==256 && p.ris_bits==2);
            assert(p.coarse_n==manifest.waveform.coarse_n && p.coarse_l==manifest.waveform.coarse_l);
            assert(p.fine_n==manifest.waveform.fine_n && p.fine_l==manifest.waveform.fine_l);
            assert(p.noise_w==manifest.waveform.noise_w && r.noise_w(method)==p.noise_w);
            assert(r.noise_power(method)==r.noise_power(1) && isequal(p.hover,r.hover(method,:)));
            gt=channel_geometry(p.truth,p); g=channel_geometry(r.estimates(:,:,method),p);
            world=(p.world_to_local'*gt.position).'+p.hover;
            assert(max(abs(world-r.scene.targets),[],'all')<1e-8);
            errors=vecnorm(g.position-gt.position,2,1).';
            delta=max(abs(errors-r.position_errors(:,method))); max_error_delta=max(max_error_delta,delta);
            assert(delta<1e-8 && all(isfinite(errors)));
            assert(r.failure(method)==(~r.locked(method) || ~r.feasible(method) ...
                || any(errors>cfg.failure_position_m)));
            design=r.design{method};
            if ~isempty(design)
                for s=1:2
                    power=norm(design{s}.W,'fro')^2; max_power=max(max_power,power);
                    assert(power<=1+1e-6);
                    ph=angle(design{s}.phase)*4/(2*pi);
                    assert(max(abs(ph-round(ph)))<1e-10);
                    z=r.coarse(:,:,method); recomputed=uav_design(z,p,mod(method,2)==0,s);
                    assert(norm(recomputed.W-design{s}.W,'fro')<1e-9);
                    assert(norm(recomputed.sinr-design{s}.sinr)<1e-8);
                    if r.feasible(method)
                        min_sinr=min(min_sinr,min(10*log10(design{s}.sinr)));
                        assert(all(design{s}.sinr>=10.^(p.comm_sinr_db/10)));
                    end
                end
            end
            mse(trial+1,ri,method)=mean(errors.^2);
            coarse(trial+1,ri,method)=mean(r.coarse_position_errors(:,method).^2);
            velocity(trial+1,ri,method)=mean(r.velocity_errors(:,method).^2);
            failures(trial+1,ri,method)=r.failure(method);
            locked(trial+1,ri,method)=r.locked(method); feasible(trial+1,ri,method)=r.feasible(method);
            row=row+1;
            rows(row,:)={trial,r.rcs_m2,cfg.methods{method},r.hover(method,1),r.hover(method,2), ...
                r.hover(method,3),errors(1),errors(2),sqrt(mean(errors.^2)), ...
                sqrt(mean(r.coarse_position_errors(:,method).^2)),sqrt(mean(r.velocity_errors(:,method).^2)), ...
                r.locked(method),r.feasible(method),r.failure(method),min(r.sinr_db(:,method)), ...
                r.tx_power_fraction(method),r.input_snr_db(method),r.seed};
        end
        for enabled=0:1
            scores=r.candidate_scores(:,enabled+1); mask=r.candidate_feasible(:,enabled+1);
            ix=find(all(abs(cfg.candidates-r.hover(enabled+3,:))<1e-12,2)); assert(numel(ix)==1);
            if any(mask), assert(mask(ix) && abs(scores(ix)-max(scores(mask)))<1e-8); end
        end
        elapsed(trial+1,ri)=r.seconds;
    end
end
metrics=cell2table(rows,'VariableNames',{'trial','rcs_m2','method','hover_x','hover_y','hover_z', ...
    'target1_error_m','target2_error_m','position_rmse_m','coarse_rmse_m','velocity_rmse_mps', ...
    'locked','feasible','failure','min_sinr_db','tx_power_fraction','input_snr_db','seed'});
writetable(metrics,fullfile(output,'case_metrics.csv'));
summary=struct('manifest_id',manifest.id,'complete_cases',manifest.total_cases,'methods',{cfg.methods}, ...
    'rcs_m2',cfg.rcs_m2,'position_rmse_m',reshape(sqrt(mean(mse,1)),nr,4), ...
    'coarse_position_rmse_m',reshape(sqrt(mean(coarse,1)),nr,4), ...
    'velocity_rmse_mps',reshape(sqrt(mean(velocity,1)),nr,4), ...
    'failure_rate',reshape(mean(failures,1),nr,4),'capture_rate',reshape(mean(locked,1),nr,4), ...
    'fine_feasible_rate',reshape(mean(feasible,1),nr,4),'total_compute_s',sum(elapsed,'all'), ...
    'primary_rcs_m2',cfg.primary_rcs_m2,'bootstrap_seed',cfg.bootstrap_seed,'bootstrap_repeats',4000, ...
    'scope','Stationary LoS hover deployment only; no flight trajectory or tracking gain demonstrated');
pairs=[1 3;2 4;1 2;3 4]; labels={'position_without_RIS','position_with_RIS','RIS_at_fixed_position','RIS_after_position_selection'};
comparisons=repmat(struct('name','','rcs_m2',0,'gain_percent',0,'ci95_percent',[0 0], ...
    'failure_rate_change',0,'primary',false),nr*4,1);
rng(cfg.bootstrap_seed,'twister'); indices=randi(nmc,nmc,4000); index=0;
for ri=1:nr
    for k=1:4
        index=index+1; a=mse(:,ri,pairs(k,1)); b=mse(:,ri,pairs(k,2));
        boot=sort(100*(1-sqrt(mean(b(indices),1))./sqrt(mean(a(indices),1))));
        comparisons(index)=struct('name',labels{k},'rcs_m2',cfg.rcs_m2(ri), ...
            'gain_percent',100*(1-sqrt(mean(b))/sqrt(mean(a))), ...
            'ci95_percent',boot([100 3900]),'failure_rate_change', ...
            mean(failures(:,ri,pairs(k,2)))-mean(failures(:,ri,pairs(k,1))), ...
            'primary',cfg.rcs_m2(ri)==cfg.primary_rcs_m2 && k==1);
    end
end
summary.comparisons=comparisons;
uav_write_json(fullfile(output,'summary.json'),summary);
fig=figure('Visible','off','Position',[50 50 1200 460]);
subplot(1,2,1); loglog(cfg.rcs_m2,summary.position_rmse_m,'-o','LineWidth',1.5);
xlabel('Target RCS scale (m^2)'); ylabel('3D position RMSE (m)'); grid on;
legend(cfg.methods,'Interpreter','none','Location','best'); title('All paired geometries, failures retained');
subplot(1,2,2); selected=comparisons([comparisons.rcs_m2]==cfg.primary_rcs_m2);
g=[selected.gain_percent]; ci=vertcat(selected.ci95_percent);
bar(1:4,g); hold on; errorbar(1:4,g,g-ci(:,1).',ci(:,2).'-g,'.k'); yline(0);
xticks(1:4); xticklabels({'Position / no RIS','Position / RIS','RIS / fixed','RIS / selected'}); xtickangle(20);
ylabel('RMSE reduction (%)'); grid on; title('RCS=10: marginal paired 95% bootstrap intervals');
saveas(fig,fullfile(output,'comparison.png')); close(fig);
verification=struct('passed',true,'manifest_id',manifest.id,'cases',manifest.total_cases,'metric_rows',height(metrics), ...
    'max_position_error_recompute_difference_m',max_error_delta,'maximum_power_fraction',max_power, ...
    'minimum_feasible_sinr_db',min_sinr,'all_failures_retained',true,'source_hashes_verified',true);
uav_write_json(fullfile(output,'verification.json'),verification);
disp(summary.position_rmse_m);
end
