function r=ud_case(old,notify)
% Replay the saved UAV geometry; all feasible estimators receive no truth.
if nargin<2, notify=@(s) []; end
t=tic; p=old.parameters{3}; initial=old.coarse(:,:,3); seed=old.seed;
r=struct('trial',old.trial,'rcs_index',old.rcs_index,'rcs_m2',old.rcs_m2,'seed',seed, ...
    'p',p,'scene',old.scene,'hover',old.hover(3,:),'initial',initial, ...
    'methods',{{'Original_NoRIS','Original_RIS_own_position','RIS_matched_full', ...
    'RIS_matched_normalized','RIS_matched_DD','RIS_matched_BIC', ...
    'RIS_frozenW_full','RIS_frozenW_DD','NoRIS_noiseless','RIS_noiseless_full', ...
    'RIS_noiseless_DD','RxBeam_NoRIS','RxBeam_RIS_full','RxBeam_RIS_DD','RxBeam_RIS_BIC'}}, ...
    'estimates',repmat(initial,1,1,15),'position_errors',zeros(2,15), ...
    'locked',false(1,15),'feasible',false(1,15),'failure',true(1,15), ...
    'diagnostic_only',logical([zeros(1,6),ones(1,5),zeros(1,4)]), ...
    'banks',{cell(1,2)},'fits',{cell(1,15)},'design',{cell(1,4)}, ...
    'noise_w',p.noise_w,'noise_power',p.noise_power,'replay_error_m',0, ...
    'synthesis_relative_error',0,'path_snr_db',nan(2,4,2),'reflected_to_DD_db',nan(1,2));
r.estimates(:,:,1:2)=old.estimates(:,:,3:4);
r.locked(1:11)=old.locked(3); r.locked(2)=old.locked(4);
r.feasible(1:11)=old.feasible(3); r.feasible(2)=old.feasible(4);
r.reference_hover=old.hover(3:4,:);
if old.locked(3) && old.feasible(3)
    notify('original acquisition: matched-position estimator ablation');
    [o,n]=observations(initial); dn=old.design{3}; dr=cell(2,1); frozen=cell(2,1);
    for s=1:2
        dr{s}=uav_design(initial,p,true,s); frozen{s}=dr{s}; frozen{s}.W=dn{s}.W;
    end
    pn=p; pn.ris_enabled=false; pr=p; pr.ris_enabled=true;
    [yn,cn]=capture(pn,o,dn,n); [yr,cr]=capture(pr,o,dr,n);
    [yf,~]=capture(pr,o,frozen,n);
    replay=refine_ris_parameters(yn,o,dn,initial,pn);
    r.replay_error_m=max(abs(errors(replay)-old.position_errors(:,3)));
    assert(r.replay_error_m<1e-6,'Original no-RIS replay changed.');
    [r.estimates(:,:,3),r.fits{3}]=refine_ris_parameters(yr,o,dr,initial,pr);
    r.banks{1}=bank(yr,o,dr,initial,pr);
    r.estimates(:,:,4)=r.banks{1}.estimates(:,:,8);
    r.estimates(:,:,5)=r.banks{1}.estimates(:,:,1);
    r.estimates(:,:,6)=r.banks{1}.estimates(:,:,r.banks{1}.choice);
    [r.estimates(:,:,7),r.fits{7}]=refine_ris_parameters(yf,o,frozen,initial,pr);
    [r.estimates(:,:,8),r.fits{8}]=pr_refine(yf,o,frozen,initial,sanitize(pr),p.noise_power,[1 0 0 0],0);
    [r.estimates(:,:,9),r.fits{9}]=refine_ris_parameters(cn,o,dn,initial,pn);
    [r.estimates(:,:,10),r.fits{10}]=refine_ris_parameters(cr,o,dr,initial,pr);
    [r.estimates(:,:,11),r.fits{11}]=pr_refine(cr,o,dr,initial,sanitize(pr),p.noise_power,[1 0 0 0],0);
    r.design(1:3)={dn,dr,frozen};
    r.feasible(3:6)=all(cellfun(@(d) d.feasible,dr));
    r.feasible(10:11)=r.feasible(3);
    r.frozen_sinr_db=min([sinr(frozen{1},pr),sinr(frozen{2},pr)],[],2);
    r.feasible(7:8)=all(r.frozen_sinr_db>=10);
    [r.path_snr_db(:,:,1),r.reflected_to_DD_db(1),delta]=path_audit(pr,o,dr,cr);
    r.synthesis_relative_error=max(r.synthesis_relative_error,delta);
end
notify('receive-beam acquisition');
[~,prior]=uav_parameters(uav_config(profile(p)),old.scene,p.hover,old.rcs_m2);
pn=p; pn.ris_enabled=false; cd=uav_design(prior,pn,false,1);
r.rx_weights=uav_rx_weights(prior,pn);
[next,info]=uav_coarse(pn,cd,seed+1,r.rx_weights);
r.rx_initial=next; r.rx_info=info; r.estimates(:,:,12:15)=repmat(next,1,1,4);
r.locked(12:15)=info.locked;
if info.locked && cd.feasible
    notify('receive-beam acquisition: fine estimators');
    [o,n]=observations(next); dn=cell(2,1); dr=cell(2,1);
    for s=1:2, dn{s}=uav_design(next,p,false,s); dr{s}=uav_design(next,p,true,s); end
    pr=p; pr.ris_enabled=true;
    [yn,~]=capture(pn,o,dn,n); [yr,cr]=capture(pr,o,dr,n);
    [r.estimates(:,:,12),r.fits{12}]=refine_ris_parameters(yn,o,dn,next,pn);
    [r.estimates(:,:,13),r.fits{13}]=refine_ris_parameters(yr,o,dr,next,pr);
    r.banks{2}=bank(yr,o,dr,next,pr);
    r.estimates(:,:,14)=r.banks{2}.estimates(:,:,1);
    r.estimates(:,:,15)=r.banks{2}.estimates(:,:,r.banks{2}.choice);
    r.feasible(12)=all(cellfun(@(d) d.feasible,dn));
    r.feasible(13:15)=all(cellfun(@(d) d.feasible,dr));
    r.design{4}=struct('no_ris',{dn},'ris',{dr});
    [r.path_snr_db(:,:,2),r.reflected_to_DD_db(2),delta]=path_audit(pr,o,dr,cr);
    r.synthesis_relative_error=max(r.synthesis_relative_error,delta);
end
for k=1:15
    if k==2, ep=old.parameters{4}; else, ep=p; end
    matched=evaluate_estimation(r.estimates(:,:,k),ep);
    r.estimates(:,:,k)=matched.estimate;
    a=channel_geometry(matched.estimate,ep); b=channel_geometry(ep.truth,ep);
    r.position_errors(:,k)=vecnorm(a.position-b.position,2,1).';
    r.failure(k)=~r.locked(k) || ~r.feasible(k) || any(r.position_errors(:,k)>5);
end
assert(max(abs(r.position_errors(:,1:2)-old.position_errors(:,3:4)),[],'all')<1e-8);
r.seconds=toc(t);
    function [o,n]=observations(z)
        o=cell(2,1); n=cell(2,1); times=round(linspace(0,p.K-1,min(p.K,p.fine_l)));
        for segment=1:2
            rng(seed+10+segment,'twister'); o{segment}=prepare_ris_observation(z,p,times(segment:2:end));
            rng(seed+20+segment,'twister'); n{segment}=(randn(p.Mx*p.My,size(o{segment}.symbol,2)) ...
                +1j*randn(p.Mx*p.My,size(o{segment}.symbol,2)))/sqrt(2);
        end
    end
    function e=errors(z)
        matched=evaluate_estimation(z,p); a=channel_geometry(matched.estimate,p); b=channel_geometry(p.truth,p);
        e=vecnorm(a.position-b.position,2,1).';
    end
end

function name=profile(p)
if p.N==512, name='smoke'; else, name='full'; end
end

function [y,clean]=capture(p,o,d,n)
y=cell(2,1); clean=cell(2,1);
for s=1:2, [y{s},clean{s}]=uav_echo(p,o{s},d{s},n{s}); end
y=vertcat(y{:}); clean=vertcat(clean{:});
end

function b=bank(y,o,d,z,p)
p=sanitize(p); masks=[ones(8,1),bitget(repmat((0:7).',1,3),repmat(1:3,8,1))];
b=struct('masks',masks,'estimates',zeros(size(z,1),4,8),'fits',{cell(1,8)},'choice',0);
for k=1:8, [b.estimates(:,:,k),b.fits{k}]=pr_refine(y,o,d,z,p,p.noise_power,masks(k,:),0); end
[~,b.choice]=min(cellfun(@(f) f.bic,b.fits));
end

function p=sanitize(p)
for field={'truth','alpha','R_true','v_true','theta_true','phi_true'}
    if isfield(p,field{1}), p=rmfield(p,field{1}); end
end
end

function db=sinr(d,p)
z=[p.user_R(:),zeros(p.K_stream,1),p.user_theta(:),p.user_phi(:)]; g=channel_geometry(z,p);
c=d.phase.'*(g.V.*exp(-1j*2*pi*p.fc/p.c*(norm(p.ris_pos)+g.rr-p.user_R)));
H=(g.transmit+g.to_ris*conj(c)).*(p.lambda./(4*pi*p.user_R));
Y=H'*d.W; a=abs(diag(Y)).^2; db=10*log10(a./(sum(abs(Y).^2,2)-a+p.comm_noise));
end

function [snr,ratio,delta]=path_audit(p,o,d,clean)
D=pr_dictionary(p.truth,o,d,p,false); g=channel_geometry(p.truth,p);
c=exp(-1j*2*pi*p.fref/p.c*(norm(p.ris_pos)+g.rr-p.truth(:,1).'));
a=zeros(4*p.Q,1);
for q=1:p.Q, a((q-1)*4+(1:4))=p.alpha(q)*(d{1}.scale(q)*c(q)).^[0 1 1 2]; end
delta=norm(D*a-clean)/max(norm(clean),realmin); assert(delta<1e-8);
snr=reshape(10*log10(max(abs(a).'.^2.*vecnorm(D).^2/p.noise_power,realmin)),4,p.Q).';
direct=1:4:4*p.Q; reflected=setdiff(1:4*p.Q,direct);
ratio=10*log10(max(norm(D(:,reflected)*a(reflected))^2,realmin)/max(norm(D(:,direct)*a(direct))^2,realmin));
end
