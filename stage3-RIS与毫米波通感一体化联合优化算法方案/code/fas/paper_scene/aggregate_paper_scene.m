function verification=aggregate_paper_scene(output)
root=fileparts(mfilename('fullpath')); addpath(root,fileparts(root));
manifest=jsondecode(fileread(fullfile(output,'manifest.json')));
files=dir(fullfile(output,'samples','rice_*_mc_*.mat')); assert(numel(files)==manifest.total_cases);
mc=manifest.mc; gains=zeros(mc,3,5); pebgain=nan(mc,3,5); rows={}; designrows={}; seen=false(mc,3);
for k=1:numel(files)
    a=load(fullfile(files(k).folder,files(k).name)); r=a.result; c=r.scene;
    assert(strcmp(a.manifest_id,manifest.id)); t=r.trial+1; ri=r.rice_index;
    assert(~seen(t,ri)); seen(t,ri)=true; index=[1 2 3 4 4 5 6 6]; guards=[0 0 0 0 4 0 0 4];
    for j=1:6
        d=r.design{j}; assert(all(d.X>=-1e-9,'all') && all(d.X<=c.aperture+1e-9,'all'));
        assert(max(abs(d.X/c.grid-round(d.X/c.grid)),[],'all')<1e-8);
        for u=1:size(d.X,1), for v=u+1:size(d.X,1), assert(norm(d.X(u,:)-d.X(v,:))>=c.spacing-1e-8); end; end
        assert(norm(d.w)^2<=c.power*(1+1e-8) && all(diff(d.trace)>=-1e-8*max(d.trace)));
        if j<=4, assert(max(abs(d.v.^4-1))<1e-8); else, assert(all(d.v==0)); end
        cc=c; if j>4, cc.reflected=0; end
        b=paper_controls(cc,d.X,d.v,d.w);
        assert(abs(b.score-d.score)<1e-7*max(1,d.score));
        assert(abs(b.h'*d.w)^2>=c.gamma*c.comm_noise*(1-1e-8));
        designrows(end+1,:)={r.trial,ri,j,d.seconds,d.score,d.sinr,norm(d.X-c.uniform,'fro')};
    end
    assert(isequal(r.design{1}.X,c.uniform));
    for m=1:8
        cc=c; if m>5, cc.reflected=0; end
        peb=paper_information(cc,r.design{index(m)},guards(m));
        assert((isinf(peb)&&isinf(r.peb(m))) || abs(peb-r.peb(m))<1e-6*max(1,peb));
        rows(end+1,:)={r.trial,ri,r.methods{m},r.snr_db(m),r.net_energy_snr_db(m),r.peb(m),r.sinr(m),r.seconds};
    end
    comparisons=[4 1;4 2;4 3;5 3;7 6];
    for j=1:5
        x=comparisons(j,1); y=comparisons(j,2);
        gains(t,ri,j)=r.net_energy_snr_db(x)-r.net_energy_snr_db(y);
        if isfinite(r.peb(x)) && isfinite(r.peb(y)), pebgain(t,ri,j)=100*(1-r.peb(x)/r.peb(y)); end
    end
end
assert(all(seen,'all'));
writetable(cell2table(rows,'VariableNames',{'trial','rice_index','method','snr_db','net_energy_snr_db','peb_m','sinr','seconds'}),fullfile(output,'case_metrics.csv'));
writetable(cell2table(designrows,'VariableNames',{'trial','rice_index','design','seconds','score','sinr','move_lambda'}),fullfile(output,'design_checks.csv'));
summary={}; rng(9043,'twister'); comparisons={'FAS_RIS_vs_uniform','FAS_RIS_vs_edge', ...
    'FAS_RIS_vs_refined_fixed','FAS_RIS_guard4_vs_refined_fixed','FAS_noRIS_vs_uniform'};
for ri=1:3
    for j=1:5
        g=gains(:,ri,j); boot=median(g(randi(mc,mc,2000)),1); ci=prctile(boot,[2.5 97.5]);
        q=pebgain(:,ri,j); finite=isfinite(q); med=nan; low=nan; high=nan;
        if any(finite)
            % Resample whole cases; undefined bounds remain counted separately.
            b=nan(1,2000);
            for n=1:2000, v=q(randi(mc,mc,1)); v=v(isfinite(v)); if ~isempty(v), b(n)=median(v); end; end
            med=median(q(finite)); z=b(isfinite(b)); interval=prctile(z,[2.5 97.5]); low=interval(1); high=interval(2);
        end
        summary(end+1,:)={manifest.rice_labels{ri},comparisons{j},mc,median(g),ci(1),ci(2),med,low,high,sum(finite),mc-sum(finite)};
    end
end
writetable(cell2table(summary,'VariableNames',{'channel','comparison','count','median_snr_gain_db','snr_ci_low','snr_ci_high', ...
    'median_peb_reduction_pct','peb_ci_low','peb_ci_high','finite_bound_pairs','undefined_bound_pairs'}),fullfile(output,'paired_gain.csv'));
verification=struct('complete',true,'manifest_id',manifest.id,'count',numel(files),'per_channel',sum(seen,1), ...
    'constraints_and_metrics_verified',true,'actual_RMSE_provided',false,'oracle_normalized_diagnostic_only',true);
fas_write_json(fullfile(output,'verification.json'),verification);
disp(cell2table(summary,'VariableNames',{'channel','comparison','count','SNR_gain_dB','low','high','PEB_reduction_pct','peb_low','peb_high','finite','undefined'}));
end
