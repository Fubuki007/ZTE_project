function result=loc_case(old,settings,notify)
% Uses the original paired coarse estimate, symbols, noise and resource window.
if nargin<3, notify=@(s) fprintf('%s\n',s); end
t=tic; p=old.p; p.ris_enabled=true;
names={'Fixed_energy','FAS_energy_guard0','FAS_energy_guard4', ...
    'Fixed_localization','FAS_localization_guard0','FAS_localization_guard4'};
result=struct('trial',old.trial,'snr_index',old.snr_index,'snr_db',old.snr_db, ...
    'seed',old.seed,'p',p,'coarse',old.coarse,'locked',old.locked,'methods',{names}, ...
    'position_errors',zeros(p.Q,6),'estimates',zeros(p.Q,4,6), ...
    'peb',nan(1,6),'feasible',false(1,6),'failure',true(1,6), ...
    'positions',{cell(1,2)},'design',{cell(1,2)},'search',{cell(1,2)});
legacy=[2,find(strcmp(old.methods,'FAS_RIS_guard0')),4];
for k=1:3
    result.position_errors(:,k)=old.position_errors(:,legacy(k));
    result.estimates(:,:,k)=old.estimates(:,:,legacy(k));
    result.feasible(k)=old.feasible(legacy(k)); result.failure(k)=old.failure(legacy(k));
end
for k=4:6
    compare=evaluate_estimation(old.coarse,p); result.estimates(:,:,k)=compare.estimate;
    g=channel_geometry(compare.estimate,p); truth=channel_geometry(p.truth,p);
    result.position_errors(:,k)=vecnorm(g.position-truth.position,2,1).';
end
if ~old.locked || ~all(old.feasible([2 4]))
    result.seconds=toc(t); return;
end
[obs,noise]=fas_fine_observations(old.coarse,p,0,old.seed+20);
[guarded,guardnoise]=fas_fine_observations(old.coarse,p,4,old.seed+20);
% Coarse-estimate design uses equal nominal target amplitudes, not test truth.
cache=loc_information_cache(old.coarse,p,obs,ones(p.Q,1));
truth_cache=loc_information_cache(p.truth,p,obs,p.alpha);
guard_cache=loc_information_cache(p.truth,p,guarded,p.alpha);
pf=p; pf.tx_positions=old.design_info{2}.positions;
pm=p; pm.tx_positions=old.design_info{4}.positions;
fixed_start=struct('positions',pf.tx_positions,'design',{old.design{2}});
alternate=fas_transport_beams(old.coarse,pm,pf,old.design{4});
perturbed=old.design{2};
for s=1:2
    v=reshape(sin((1:numel(perturbed{s}.W))*sqrt(2))+1j*cos((1:numel(perturbed{s}.W))*sqrt(3)),size(perturbed{s}.W));
    perturbed{s}.W=perturbed{s}.W+.05*v/norm(v,'fro');
    perturbed{s}.W=perturbed{s}.W/norm(perturbed{s}.W,'fro');
end
starts={fixed_start,struct('positions',pf.tx_positions,'design',{alternate}), ...
    struct('positions',pf.tx_positions,'design',{perturbed})};
[fixed,df,infof]=loc_search(cache,starts,false,settings,notify);
[gx,gy]=ndgrid([0 .4 1.1 1.5]); edge=p; edge.tx_positions=p.lambda*[gx(:),gy(:),zeros(16,1)];
edge_design=fas_transport_beams(old.coarse,pf,edge,df);
starts={struct('positions',fixed,'design',{df}), ...
    struct('positions',pm.tx_positions,'design',{old.design{4}}), ...
    struct('positions',edge.tx_positions,'design',{edge_design})};
[fluid,dm,infom]=loc_search(cache,starts,true,settings,notify);
result.positions={fixed,fluid}; result.design={df,dm}; result.search={infof,infom};
result.peb(1)=loc_information(truth_cache,pf.tx_positions,old.design{2},old.noise_power);
result.peb(2)=loc_information(truth_cache,pm.tx_positions,old.design{4},old.noise_power);
result.peb(3)=loc_information(guard_cache,pm.tx_positions,old.design{4},old.noise_power);
for k=4:6
    pc=p;
    if k==4, pc.tx_positions=fixed; d=df; else, pc.tx_positions=fluid; d=dm; end
    if k==6, o=guarded; e=guardnoise; c=guard_cache; else, o=obs; e=noise; c=truth_cache; end
    [~,feasible]=fas_design_score(old.coarse,pc,d); assert(feasible);
    yy=cell(2,1);
    for s=1:2, yy{s}=fas_echo(pc,o{s},d{s},old.noise_power,e{s}); end
    [estimate,fit]=refine_ris_parameters(vertcat(yy{:}),o,d,old.coarse,pc);
    compare=evaluate_estimation(estimate,p); g=channel_geometry(compare.estimate,p); truth=channel_geometry(p.truth,p);
    result.position_errors(:,k)=vecnorm(g.position-truth.position,2,1).';
    result.estimates(:,:,k)=compare.estimate; result.feasible(k)=true;
    result.failure(k)=any(result.position_errors(:,k)>5);
    result.peb(k)=loc_information(c,pc.tx_positions,d,old.noise_power);
    result.fit{k}=fit;
end
% At 10 dB all 300 geometries also receive a matched truth-assisted reference.
if old.snr_db==10 && settings.oracle
    starts={fixed_start,struct('positions',fixed,'design',{df}), ...
        struct('positions',fixed,'design',{perturbed})};
    [fo,dfo,ifo]=loc_search(truth_cache,starts,false,settings,notify);
    starts={struct('positions',fo,'design',{dfo}),struct('positions',fluid,'design',{dm}), ...
        struct('positions',edge.tx_positions,'design',{edge_design})};
    [mo,dmo,imo]=loc_search(truth_cache,starts,true,settings,notify);
    result.oracle=struct('fixed_positions',fo,'fas_positions',mo,'fixed_design',{dfo}, ...
        'fas_design',{dmo},'fixed_search',ifo,'fas_search',imo, ...
        'fixed_peb',loc_information(truth_cache,fo,dfo,old.noise_power), ...
        'fas_peb',loc_information(truth_cache,mo,dmo,old.noise_power), ...
        'fas_guard4_peb',loc_information(guard_cache,mo,dmo,old.noise_power));
end
result.seconds=toc(t); notify(sprintf('case complete MC=%d SNR=%g seconds=%.1f',old.trial,old.snr_db,result.seconds));
end
