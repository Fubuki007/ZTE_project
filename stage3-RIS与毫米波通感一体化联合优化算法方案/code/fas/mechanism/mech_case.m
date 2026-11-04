function result=mech_case(old,prior,loss_db,settings,notify)
% Conditional fine-stage diagnosis using the same previously acquired prior.
if nargin<5, notify=@(s) []; end
t=tic; p=old.p; p.ris_enabled=true; weights=mech_weights(loss_db);
assert(old.locked && prior.locked && old.seed==prior.seed && isequal(old.coarse,prior.coarse));
assert(old.snr_db==10 && prior.snr_db==10);
names={'Fixed_uniform_RIS','Fixed_edge_RIS','FAS_RIS_guard0','FAS_RIS_guard4', ...
    'Fixed_uniform_noRIS','FAS_noRIS_guard0','FAS_noRIS_guard4'};
result=struct('trial',old.trial,'seed',old.seed,'snr_db',10,'dd_loss_db',loss_db,'path_weights',weights, ...
    'p',p,'coarse',old.coarse,'prior_source','Original unblocked 10 dB coarse estimate, shared by all methods', ...
    'noise_power',old.noise_power,'methods',{names},'estimates',zeros(p.Q,4,7), ...
    'position_errors',zeros(p.Q,7),'peb',nan(1,7),'failure',true(1,7), ...
    'range_bound_m',inf(1,7),'angle_position_bound_m',inf(1,7),'scaled_min_eigenvalue',zeros(1,7), ...
    'path_power_ratio',nan(p.Q,7),'positions',{cell(1,5)},'design',{cell(1,5)},'search',{cell(1,5)});
priorg=channel_geometry(old.coarse,p); truthg=channel_geometry(p.truth,p);
result.prior_position_errors=vecnorm(priorg.position-truthg.position,2,1).';
[obs,noise]=fas_fine_observations(old.coarse,p,0,old.seed+20);
[guarded,guardnoise]=fas_fine_observations(old.coarse,p,4,old.seed+20);
cache=loc_information_cache(old.coarse,p,obs,ones(p.Q,1)); cache.path_weights=weights;
truth=loc_information_cache(p.truth,p,obs,p.alpha); truth.path_weights=weights;
guardtruth=loc_information_cache(p.truth,p,guarded,p.alpha); guardtruth.path_weights=weights;
fixed=prior.positions{1}; fluid=prior.positions{2}; df=prior.design{1}; dm=prior.design{2};
pf=p; pf.tx_positions=fixed; pm=p; pm.tx_positions=fluid;
[gx,gy]=ndgrid([0 .4 1.1 1.5]); edge=p; edge.tx_positions=p.lambda*[gx(:),gy(:),zeros(16,1)];
starts={entry(fixed,df),entry(fixed,fas_transport_beams(old.coarse,pm,pf,dm)),entry(fixed,perturb(df))};
notify('fixed uniform RIS search');
[pu,du,iu]=loc_search(cache,starts,false,settings,notify);
de=fas_transport_beams(old.coarse,pf,edge,du);
de=feasible_seed(old.coarse,edge,de);
starts={entry(edge.tx_positions,de),entry(edge.tx_positions,fas_transport_beams(old.coarse,pm,edge,dm)),entry(edge.tx_positions,perturb(de))};
notify('fixed nonuniform RIS search');
[pe,de,ie]=loc_search(cache,starts,false,settings,notify);
starts={entry(pu,du),entry(pe,de),entry(fluid,dm)};
notify('adaptive FAS RIS search');
[pr,dr,ir]=loc_search(cache,starts,true,settings,notify);
assert(ir.peb<=min(iu.peb,ie.peb)*(1+1e-9));

off=p; off.ris_enabled=false;
offcache=cache; offcache.p=off; offcache.g.V(:)=0;
for j=1:4, offcache.dg{j}.V(:)=0; end
offtruth=truth; offtruth.p=off; offtruth.g.V(:)=0;
offguard=guardtruth; offguard.p=off; offguard.g.V(:)=0;
for j=1:4, offtruth.dg{j}.V(:)=0; offguard.dg{j}.V(:)=0; end
offsettings=settings; offsettings.ris_rounds=0;
pno=off; pno.tx_positions=old.design_info{1}.positions;
pmno=off; pmno.tx_positions=old.design_info{3}.positions;
starts={entry(pno.tx_positions,old.design{1}), ...
    entry(pno.tx_positions,fas_transport_beams(old.coarse,pmno,pno,old.design{3})), ...
    entry(pno.tx_positions,perturb(old.design{1}))};
notify('fixed uniform noRIS search');
[pn,dn,in]=loc_search(offcache,starts,false,offsettings,notify);
edgeno=edge; edgeno.ris_enabled=false;
starts={entry(pn,dn),entry(pmno.tx_positions,old.design{3}), ...
    entry(edge.tx_positions,fas_transport_beams(old.coarse,pno,edgeno,dn))};
notify('adaptive FAS noRIS search');
[pa,da,ia]=loc_search(offcache,starts,true,offsettings,notify);
assert(ia.peb<=in.peb*(1+1e-9));
result.positions={pu,pe,pr,pn,pa}; result.design={du,de,dr,dn,da}; result.search={iu,ie,ir,in,ia};
index=[1 2 3 3 4 5 5]; guards=[0 0 0 4 0 0 4];
for m=1:7
    pc=p; pc.ris_enabled=m<=4; pc.tx_positions=result.positions{index(m)}; d=result.design{index(m)};
    [~,ok]=fas_design_score(old.coarse,pc,d); assert(ok);
    if guards(m), o=guarded; e=guardnoise; ct=guardtruth; else, o=obs; e=noise; ct=truth; end
    if m>4, if guards(m), ct=offguard; else, ct=offtruth; end; end
    y=cell(2,1);
    for s=1:2, y{s}=mech_echo(pc,o{s},d{s},old.noise_power,e{s},weights); end
    [estimate,fit]=refine_ris_parameters(vertcat(y{:}),o,d,old.coarse,pc);
    compare=evaluate_estimation(estimate,p); g=channel_geometry(compare.estimate,p); gt=channel_geometry(p.truth,pc);
    result.estimates(:,:,m)=compare.estimate; result.position_errors(:,m)=vecnorm(g.position-gt.position,2,1).';
    result.failure(m)=any(result.position_errors(:,m)>5); result.fit{m}=fit;
    result.sample_counts(m)=sum(cellfun(@(a) size(a.symbol,2),o));
    [result.peb(m),info]=loc_information(ct,pc.tx_positions,d,old.noise_power);
    result.scaled_min_eigenvalue(m)=info.min_eigenvalue;
    if isfinite(result.peb(m))
        covariance=info.covariance; radial=ct.P; angular=ct.P;
        radial(:,p.Q+1:end)=0; angular(:,1:2*p.Q)=0;
        result.range_bound_m(m)=sqrt(max(0,trace(radial*covariance*radial')/p.Q));
        result.angle_position_bound_m(m)=sqrt(max(0,trace(angular*covariance*angular')/p.Q));
    end
    power=zeros(p.Q,2);
    for s=1:2
        c=d{s}.phase.'*gt.V;
        direct=sum(abs(gt.transmit'*d{s}.W).^2,2).'; feed=sum(abs(gt.to_ris'*d{s}.W).^2,'all');
        power(:,s)=((abs(c).^2*feed*weights(2)^2+abs(c).^2.*direct*weights(3)^2 ...
            +abs(c).^4*feed*weights(4)^2)./(direct*weights(1)^2)).';
    end
    result.path_power_ratio(:,m)=mean(power,2);
end
result.seconds=toc(t); notify(sprintf('case saved-ready MC=%d DD-loss=%g seconds=%.1f',old.trial,loss_db,result.seconds));
end

function s=entry(positions,design)
s=struct('positions',positions,'design',{design});
end

function d=perturb(d)
for s=1:2
    v=reshape(sin((1:numel(d{s}.W))*sqrt(2))+1j*cos((1:numel(d{s}.W))*sqrt(3)),size(d{s}.W));
    d{s}.W=d{s}.W+.05*v/norm(v,'fro'); d{s}.W=d{s}.W/norm(d{s}.W,'fro');
end
end

function d=feasible_seed(z,p,d)
% A new fixed layout needs its own feasible communication incumbent.
[~,ok]=fas_design_score(z,p,d); if ok, return; end
users=[p.user_R(:),zeros(p.K_stream,1),p.user_theta(:),p.user_phi(:)];
u=channel_geometry(users,p);
u.V=u.V.*exp(-1j*2*pi*p.fc/p.c*(norm(p.ris_pos)+u.rr-p.user_R(:).'));
target=diag(sqrt(10.^(p.comm_sinr_db/10).*p.comm_noise*(1+1e-3)));
for s=1:2
    H=u.transmit+u.to_ris*conj(d{s}.phase.'*u.V);
    W=lsqminnorm(H',target); assert(norm(W,'fro')<=1,'Fixed layout has no feasible ZF seed under this power budget.');
    d{s}.W=W/norm(W,'fro');
end
[~,ok]=fas_design_score(z,p,d); assert(ok);
end
