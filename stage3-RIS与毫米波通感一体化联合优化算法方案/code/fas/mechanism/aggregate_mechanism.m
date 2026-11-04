function aggregate_mechanism(output)
root=fileparts(mfilename('fullpath')); code=fileparts(fileparts(root)); addpath(root,fileparts(root),code);
manifest=jsondecode(fileread(fullfile(output,'manifest.json'))); names=cellstr(manifest.methods);
losses=manifest.dd_loss_db; mc=manifest.options.mc; nm=numel(names);
metrics=struct([]); gains=struct([]); checks=struct([]); cases=struct([]); counts=zeros(size(losses));
rng(20261104,'twister'); options=fas_options('full');
for li=1:numel(losses)
    mse=zeros(mc,nm); pebs=mse; failure=mse; radial=mse; angular=mse; power=mse; prior=zeros(mc,1);
    for trial=0:mc-1
        a=load(fullfile(output,'samples',sprintf('loss_%02d_mc_%04d.mat',li,trial)),'result','manifest_id'); r=a.result;
        assert(strcmp(a.manifest_id,manifest.id) && r.trial==trial && r.dd_loss_db==losses(li));
        assert(isequal(r.methods(:),names(:)) && isequal(r.path_weights,mech_weights(losses(li))));
        assert(all(isfinite(r.estimates),'all') && all(isfinite(r.position_errors),'all') && r.noise_power>0);
        p=r.p; gt=channel_geometry(p.truth,p);
        if strcmp(manifest.profile,'full')
            assert(p.N==12672 && p.K==256 && p.Mx*p.My==64 && p.ris_side^2==256 && p.Ntx*p.Nty==16);
        end
        assert(r.search{3}.peb<=min(r.search{1}.peb,r.search{2}.peb)*(1+1e-9));
        assert(r.search{5}.peb<=r.search{4}.peb*(1+1e-9));
        [xx,yy]=ndgrid(0:3,0:3); uniform=p.d*[xx(:),yy(:),zeros(16,1)];
        [xx,yy]=ndgrid([0 .4 1.1 1.5]); edge=p.lambda*[xx(:),yy(:),zeros(16,1)];
        assert(norm(r.positions{1}-uniform,'fro')<1e-12 && norm(r.positions{4}-uniform,'fro')<1e-12);
        assert(norm(r.positions{2}-edge,'fro')<1e-12,'Nonuniform fixed control changed its layout.');
        for b=1:5
            pc=p; pc.ris_enabled=b<=3; pc.tx_positions=r.positions{b}; d=r.design{b};
            assert(fas_positions_valid(pc.tx_positions,p,options));
            assert(max(abs(pc.tx_positions/p.lambda/.1-round(pc.tx_positions/p.lambda/.1)),[],'all')<1e-8);
            [~,ok,sinr]=fas_design_score(r.coarse,pc,d); assert(ok);
            levels=exp(1j*2*pi*(0:3)/4);
            for s=1:2, assert(max(min(abs(d{s}.phase-levels),[],2))<1e-10); end
            traces=vertcat(r.search{b}.runs.trace);
            for k=1:numel(traces), assert(all(diff(traces(k).accepted_peb)<=1e-12)); end
            check=struct('trial',trial,'dd_loss_db',r.dd_loss_db,'design',b,'min_sinr',min(sinr,[],'all'), ...
                'search_seconds',r.search{b}.seconds,'objective',r.search{b}.peb, ...
                'continuous_objective',r.search{b}.continuous_peb,'iteration_limits',sum([traces.exitflag]==0), ...
                'negative_exit_runs',sum([traces.exitflag]<0));
            if isempty(checks), checks=check; else, checks(end+1)=check; end
        end
        for m=1:nm
            g=channel_geometry(r.estimates(:,:,m),p); errors=vecnorm(g.position-gt.position,2,1).';
            assert(norm(errors-r.position_errors(:,m))<1e-8 && r.failure(m)==any(errors>5));
            if isfinite(r.peb(m))
                assert(abs(r.range_bound_m(m)^2+r.angle_position_bound_m(m)^2-r.peb(m)^2)<1e-8*max(r.peb(m)^2,eps));
            end
            entry=struct('trial',trial,'dd_loss_db',r.dd_loss_db,'method',names{m}, ...
                'position_mse_m2',mean(errors.^2),'prior_position_mse_m2',mean(r.prior_position_errors.^2), ...
                'peb_m',r.peb(m),'failure',r.failure(m),'noise_power',r.noise_power, ...
                'range_bound_m',r.range_bound_m(m),'angle_position_bound_m',r.angle_position_bound_m(m), ...
                'ris_direct_power_ratio',mean(r.path_power_ratio(:,m)));
            if isempty(cases), cases=entry; else, cases(end+1)=entry; end
        end
        mse(trial+1,:)=mean(r.position_errors.^2,1); pebs(trial+1,:)=r.peb; failure(trial+1,:)=r.failure;
        radial(trial+1,:)=r.range_bound_m; angular(trial+1,:)=r.angle_position_bound_m;
        power(trial+1,:)=mean(r.path_power_ratio,1); prior(trial+1)=mean(r.prior_position_errors.^2);
        counts(li)=counts(li)+1;
    end
    assert(~any(isnan(pebs),'all'));
    rmse=sqrt(mean(mse,1)); boot=randi(mc,mc,2000); sampled=zeros(2000,nm);
    for m=1:nm
        values=mse(:,m); sampled(:,m)=sqrt(mean(values(boot),1)).';
        entry=struct('dd_loss_db',losses(li),'method',names{m},'mc_completed',mc, ...
            'position_rmse_m',rmse(m),'prior_position_rmse_m',sqrt(mean(prior)), ...
            'failure_rate',mean(failure(:,m)),'peb_rms_m',sqrt(mean(pebs(:,m).^2)), ...
            'singular_information_cases',sum(isinf(pebs(:,m))), ...
            'range_bound_rms_m',sqrt(mean(radial(:,m).^2)),'angle_position_bound_rms_m',sqrt(mean(angular(:,m).^2)), ...
            'ris_direct_power_ratio_median',median(power(:,m)));
        if isempty(metrics), metrics=entry; else, metrics(end+1)=entry; end
    end
    comparisons=[3 1;4 1;3 2;4 2;6 5;7 5;1 5;2 1];
    for k=1:size(comparisons,1)
        m=comparisons(k,1); b=comparisons(k,2); interval=quantile(100*(1-sampled(:,m)./sampled(:,b)),[.025 .975]);
        entry=struct('dd_loss_db',losses(li),'method',names{m},'reference',names{b}, ...
            'rmse_gain_percent',100*(1-rmse(m)/rmse(b)),'paired_ci95_low',interval(1),'paired_ci95_high',interval(2), ...
            'peb_gain_percent',100*(1-sqrt(mean(pebs(:,m).^2))/sqrt(mean(pebs(:,b).^2))));
        if isempty(gains), gains=entry; else, gains(end+1)=entry; end
    end
end
assert(all(counts==mc));
% Verify the same physical noise and coarse prior were used at every loss.
for trial=0:mc-1
    selected=cases([cases.trial]==trial); assert(numel(unique([selected.noise_power]))==1);
    assert(max([selected.prior_position_mse_m2])-min([selected.prior_position_mse_m2])<1e-12);
end
writetable(struct2table(metrics),fullfile(output,'metrics.csv'));
writetable(struct2table(gains),fullfile(output,'paired_gain.csv'));
writetable(struct2table(cases),fullfile(output,'case_metrics.csv'));
writetable(struct2table(checks),fullfile(output,'design_checks.csv'));
f=figure('Visible','off','Color','w','Position',[100 100 1250 800]); cleanup=onCleanup(@() close(f));
for m=1:nm
    rows=metrics(strcmp({metrics.method},names{m}));
    subplot(2,2,1); semilogy(losses,[rows.position_rmse_m],'-o'); hold on;
    subplot(2,2,2); semilogy(losses,[rows.peb_rms_m],'-o'); hold on;
end
subplot(2,2,1); rows=metrics(strcmp({metrics.method},names{1})); semilogy(losses,[rows.prior_position_rmse_m],'k--');
grid on; xlabel('DD round-trip power loss (dB)'); ylabel('Conditional position RMSE (m)'); legend([names;{'Shared prior'}],'Interpreter','none','Location','best');
subplot(2,2,2); grid on; xlabel('DD round-trip power loss (dB)'); ylabel('Conditional PEB RMS (m)');
for pair=[3 4 6 7]
    if pair<5, reference=names{1}; else, reference=names{5}; end
    rows=gains(strcmp({gains.method},names{pair}) & strcmp({gains.reference},reference));
    subplot(2,2,3); plot(losses,[rows.rmse_gain_percent],'-o','DisplayName',names{pair}); hold on;
    subplot(2,2,4); plot(losses,[rows.peb_gain_percent],'-o','DisplayName',names{pair}); hold on;
end
subplot(2,2,3); yline(0); grid on; xlabel('DD round-trip power loss (dB)'); ylabel('FAS RMSE reduction (%)'); legend('Interpreter','none','Location','best');
subplot(2,2,4); yline(0); grid on; xlabel('DD round-trip power loss (dB)'); ylabel('FAS PEB reduction (%)');
sgtitle('Controlled target-link attenuation | fixed original noise | shared unblocked prior');
exportgraphics(f,fullfile(output,'comparison.png'),'Resolution',180);
fas_write_json(fullfile(output,'progress.json'),struct('complete',true,'manifest_id',manifest.id, ...
    'counts',counts,'total_completed',sum(counts),'total_expected',manifest.total_cases));
fas_write_json(fullfile(output,'verification.json'),struct('complete',true,'profile',manifest.profile, ...
    'manifest_id',manifest.id,'cases',sum(counts),'noise_and_prior_constant',true,'constraints_checked',true, ...
    'limitations','Conditional shared-prior fine localization; no blocked coarse acquisition or global optimality claim'));
fprintf('AGGREGATED AND VERIFIED %d/%d controlled attenuation cases\n',sum(counts),manifest.total_cases);
end
