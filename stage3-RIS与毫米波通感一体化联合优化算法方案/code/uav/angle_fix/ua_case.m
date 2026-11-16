function r=ua_case(old,notify)
% Replay one physical acquisition, then vary only its angular estimator.
if nargin<2, notify=@(s) []; end
t=tic; p=old.p; p.ris_enabled=false; seed=old.seed;
profile='full'; if p.N==512, profile='smoke'; end
[~,prior]=uav_parameters(uav_config(profile),old.scene,p.hover,old.rcs_m2);
cd=uav_design(prior,p,false,1); weights=uav_rx_weights(prior,p);
notify('paired receive-beam acquisition'); [initial,info]=uav_coarse(p,cd,seed+1,weights);
methods={'legacy','signed_null','no_null','matched_array'};
r=struct('trial',old.trial,'rcs_index',old.rcs_index,'rcs_m2',old.rcs_m2,'seed',seed, ...
    'p',p,'scene',old.scene,'prior',prior,'hover',p.hover,'rx_weights',weights,'info',info, ...
    'methods',{methods},'initial_unmatched',zeros(2,4,4),'coarse',zeros(2,4,4), ...
    'estimates',zeros(2,4,4),'coarse_errors',zeros(2,4,4),'parameter_errors',zeros(2,4,4), ...
    'position_errors',zeros(2,4),'coarse_position_errors',zeros(2,4), ...
    'locked',repmat(info.locked,1,4),'feasible',false(1,4),'failure',true(1,4), ...
    'outside_local_box',false(1,4),'polar_boundary',false(1,4), ...
    'design',{cell(1,4)},'fits',{cell(1,4)},'coarse_design',cd, ...
    'coarse_replay_delta',0,'fine_replay_delta_m',0,'has_reference',isfield(old,'rx_initial'));
safe=rmfield(p,intersect(fieldnames(p),{'truth','alpha','R_true','v_true','theta_true','phi_true'}));
for k=1:4
    angles=coarse_array_angles(info.angle_snapshots,safe,methods{k}); z=[initial(:,1:2),angles];
    r.initial_unmatched(:,:,k)=z; estimate=z;
    if info.locked && cd.feasible
        notify(['fine NoRIS: ',methods{k}]); obs=cell(2,1); design=cell(2,1); yy=cell(2,1);
        times=round(linspace(0,p.K-1,min(p.K,p.fine_l)));
        for s=1:2
            rng(seed+10+s,'twister'); obs{s}=prepare_ris_observation(z,p,times(s:2:end));
            design{s}=uav_design(z,p,false,s);
            rng(seed+20+s,'twister'); noise=(randn(p.Mx*p.My,size(obs{s}.symbol,2)) ...
                +1j*randn(p.Mx*p.My,size(obs{s}.symbol,2)))/sqrt(2);
            yy{s}=uav_echo(p,obs{s},design{s},noise);
        end
        r.design{k}=design; r.feasible(k)=all(cellfun(@(d) d.feasible,design));
        if r.feasible(k), [estimate,r.fits{k}]=refine_ris_parameters(vertcat(yy{:}),obs,design,z,p); end
    end
    a=evaluate_estimation(z,p); b=evaluate_estimation(estimate,p);
    r.coarse(:,:,k)=a.estimate; r.coarse_errors(:,:,k)=a.error;
    r.estimates(:,:,k)=b.estimate; r.parameter_errors(:,:,k)=b.error;
    truth=channel_geometry(p.truth,p); coarse=channel_geometry(a.estimate,p); fine=channel_geometry(b.estimate,p);
    r.coarse_position_errors(:,k)=vecnorm(coarse.position-truth.position,2,1).';
    r.position_errors(:,k)=vecnorm(fine.position-truth.position,2,1).';
    r.failure(k)=~r.locked(k) || ~r.feasible(k) || any(r.position_errors(:,k)>5);
    r.polar_boundary(k)=any(z(:,3)>=89.99);
    bounds=[max(.6,2*p.resolution),max(10,p.lambda/(p.K*p.Ts)),15,30]; inside=false;
    for order=[1 2;2 1].'
        delta=p.truth(order,:)-z; delta(:,4)=mod(delta(:,4)+180,360)-180;
        inside=inside || all(abs(delta)<=bounds,'all');
    end
    r.outside_local_box(k)=~inside;
end
assert(max(abs(r.initial_unmatched(:,1:2,:)-r.initial_unmatched(:,1:2,1)),[],'all')==0);
if r.has_reference
    r.coarse_replay_delta=max(abs(r.initial_unmatched(:,:,1)-old.rx_initial),[],'all');
    r.fine_replay_delta_m=max(abs(r.position_errors(:,1)-old.position_errors(:,12)));
    assert(r.coarse_replay_delta<1e-7 && r.fine_replay_delta_m<1e-5,'Legacy replay changed.');
    assert(all(r.locked==old.locked(12)) && r.feasible(1)==old.feasible(12));
end
r.seconds=toc(t);
end
