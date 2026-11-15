function result=pr_case(old,localized,settings,notify)
if nargin<4, notify=@(s) []; end
t=tic; p=old.p;
assert(old.trial==localized.trial && old.snr_index==localized.snr_index && ...
    old.seed==localized.seed && isequal(old.coarse,localized.coarse));
methods={'Full_legacy','Full_normalized','DD_only','AIC','BIC','Ridge_GCV','Oracle_bank_hindsight'};
result=struct('trial',old.trial,'snr_index',old.snr_index,'snr_db',old.snr_db, ...
    'seed',old.seed,'p',p,'coarse',old.coarse,'locked',old.locked,'noise_power',old.noise_power, ...
    'methods',{methods},'conditions',{{'RIS_energy','RIS_PEB'}}, ...
    'estimates',repmat(old.coarse,1,1,numel(methods),2), ...
    'position_errors',zeros(p.Q,numel(methods),2),'feasible',false(1,2), ...
    'failure',true(numel(methods),2),'banks',{cell(1,2)},'design',{cell(1,2)}, ...
    'legacy_error',zeros(1,2),'baseline_errors',zeros(p.Q,2), ...
    'baseline_names',{{'NoRIS_energy_refined','NoRIS_PEB_refined'}}, ...
    'baseline_estimates',repmat(old.coarse,1,1,2),'baseline_feasible',false(1,2), ...
    'baseline_failure',true(1,2));
coarse_error=errors(old.coarse,p);
result.position_errors=repmat(coarse_error,1,numel(methods),2);
result.baseline_errors=repmat(coarse_error,1,2);
if ~old.locked, result.seconds=toc(t); return; end
[obs,noise]=fas_fine_observations(old.coarse,p,0,old.seed+20);
for condition=1:2
    pc=p; pc.ris_enabled=true;
    if condition==1
        d=old.design{2}; pc.tx_positions=old.design_info{2}.positions;
        available=old.feasible(2); expected=old.estimates(:,:,2);
    else
        d=localized.design{1}; pc.tx_positions=localized.positions{1};
        available=localized.feasible(4); expected=localized.estimates(:,:,4);
    end
    if ~available, continue; end
    [~,ok]=fas_design_score(old.coarse,pc,d); assert(ok);
    yy=cell(2,1); clean=cell(2,1);
    for s=1:2, [yy{s},clean{s}]=fas_echo(pc,obs{s},d{s},old.noise_power,noise{s}); end
    y=vertcat(yy{:});
    [legacy,legacy_fit]=refine_ris_parameters(y,obs,d,old.coarse,pc);
    evaluated=evaluate_estimation(legacy,p);
    result.legacy_error(condition)=max(abs(evaluated.estimate-expected),[],'all');
    assert(result.legacy_error(condition)<1e-6,'Replayed Stage-3 reference differs from saved checkpoint.');
    notify(sprintf('condition %d/%d',condition,2));
    bank=pr_bank(y,obs,d,old.coarse,pc,old.noise_power,notify);
    candidate_error=zeros(p.Q,size(bank.estimates,3));
    for k=1:size(bank.estimates,3), candidate_error(:,k)=errors(bank.estimates(:,:,k),p); end
    [~,oracle]=min(mean(candidate_error.^2,1));
    choices=[bank.choice,oracle];
    result.estimates(:,:,1,condition)=legacy;
    for k=2:numel(methods), result.estimates(:,:,k,condition)=bank.estimates(:,:,choices(k-1)); end
    for k=1:numel(methods)
        result.position_errors(:,k,condition)=errors(result.estimates(:,:,k,condition),p);
        result.failure(k,condition)=any(result.position_errors(:,k,condition)>5);
    end
    D=pr_dictionary(p.truth,obs,d,pc,false); norms=vecnorm(D); normal=D./max(norms,realmin);
    truth_geometry=channel_geometry(p.truth,pc);
    carrier=exp(-1j*2*pi*p.fref/p.c*(norm(p.ris_pos)+truth_geometry.rr-p.truth(:,1).'));
    amplitude=zeros(4*p.Q,1);
    % Explicit orders avoid assuming RD/DR/RR have independent true fading.
    for q=1:p.Q, amplitude((q-1)*4+(1:4))=p.alpha(q)*(d{1}.scale(q)*carrier(q)).^[0 1 1 2]; end
    assert(norm(D*amplitude-vertcat(clean{:}))/max(norm(vertcat(clean{:})),realmin)<1e-8);
    bank.candidate_position_errors=candidate_error; bank.oracle_choice=oracle;
    bank.path_snr_db=reshape(10*log10(max(abs(amplitude).'.^2.*norms.^2/old.noise_power,realmin)),4,p.Q).';
    bank.column_coherence=abs(normal'*normal); bank.legacy_fit=legacy_fit;
    bank.observation_hash=fas_hash(typecast([real(y);imag(y)],'uint8'));
    result.banks{condition}=bank; result.design{condition}=d;
    result.feasible(condition)=true;
end
% A separate physical no-RIS counterfactual, with the same fine observations.
pn=p; pn.ris_enabled=false; pn.tx_positions=old.design_info{1}.positions;
if old.feasible(1)
    result.baseline_estimates(:,:,1)=old.estimates(:,:,1);
    result.baseline_errors(:,1)=old.position_errors(:,1); result.baseline_feasible(1)=true;
    result.baseline_failure(1)=any(result.baseline_errors(:,1)>5);
    d=old.design{1}; perturbed=d;
    for s=1:2
        v=reshape(sin((1:numel(d{s}.W))*sqrt(2))+1j*cos((1:numel(d{s}.W))*sqrt(3)),size(d{s}.W));
        perturbed{s}.W=d{s}.W+.05*v/norm(v,'fro');
        perturbed{s}.W=perturbed{s}.W/norm(perturbed{s}.W,'fro');
    end
    starts={struct('positions',pn.tx_positions,'design',{d}), ...
        struct('positions',pn.tx_positions,'design',{perturbed})};
    if result.feasible(2), starts{end+1}=struct('positions',pn.tx_positions,'design',{result.design{2}}); end
    cache=loc_information_cache(old.coarse,pn,obs,ones(p.Q,1));
    [~,dn,search]=loc_search(cache,starts,false,struct('iterations',settings.no_ris_iterations,'ris_rounds',0),notify);
    yn=cell(2,1);
    for s=1:2, yn{s}=fas_echo(pn,obs{s},dn{s},old.noise_power,noise{s}); end
    zn=pr_refine(vertcat(yn{:}),obs,dn,old.coarse,pn,old.noise_power,[1 0 0 0],0);
    result.baseline_estimates(:,:,2)=zn; result.baseline_errors(:,2)=errors(zn,p);
    result.baseline_feasible(2)=true; result.baseline_failure(2)=any(result.baseline_errors(:,2)>5);
    result.no_ris_design=dn; result.no_ris_search=search;
end
result.sample_counts=cellfun(@(o) size(o.symbol,2),obs);
result.seconds=toc(t);
assert(all(isfinite(result.position_errors),'all') && all(isfinite(result.baseline_errors),'all'));
end

function e=errors(z,p)
c=evaluate_estimation(z,p); a=channel_geometry(c.estimate,p); b=channel_geometry(p.truth,p);
e=vecnorm(a.position-b.position,2,1).';
end
