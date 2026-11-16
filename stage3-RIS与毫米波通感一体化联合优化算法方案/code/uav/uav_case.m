function result=uav_case(cfg,trial,rcs_index,notify)
if nargin<4, notify=@(s) []; end
t=tic; seed=cfg.seed+10000*trial;
rng(seed,'twister'); scene.targets=cfg.targets;
scene.targets(:,1:2)=scene.targets(:,1:2)+cfg.target_jitter_m*randn(2,2);
scene.prior=scene.targets; scene.prior(:,1:2)=scene.prior(:,1:2)+cfg.prior_sigma_m*randn(2,2);
scene.scatter_phase=2*pi*rand(1,2); rcs=cfg.rcs_m2(rcs_index);
result=struct('trial',trial,'rcs_index',rcs_index,'rcs_m2',rcs,'seed',seed, ...
    'scene',scene,'methods',{cfg.methods},'hover',repmat(cfg.hover,4,1), ...
    'position_errors',zeros(2,4),'coarse_position_errors',zeros(2,4), ...
    'velocity_errors',zeros(2,4),'estimates',zeros(2,4,4),'coarse',zeros(2,4,4), ...
    'locked',false(1,4),'feasible',false(1,4),'failure',true(1,4), ...
    'sinr_db',nan(2,4),'tx_power_fraction',nan(1,4),'design',{cell(1,4)}, ...
    'candidate_scores',nan(size(cfg.candidates,1),2),'candidate_feasible',false(size(cfg.candidates,1),2), ...
    'input_snr_db',nan(1,4),'noise_power',nan(1,4),'noise_w',nan(1,4), ...
    'parameters',{cell(1,4)});
for enabled=0:1
    notify(sprintf('position search RIS=%d',enabled));
    for k=1:size(cfg.candidates,1)
        [p,prior]=uav_parameters(cfg,scene,cfg.candidates(k,:),rcs);
        d=uav_design(prior,p,enabled,1);
        result.candidate_scores(k,enabled+1)=d.score;
        result.candidate_feasible(k,enabled+1)=d.feasible;
    end
    scores=result.candidate_scores(:,enabled+1);
    scores(~result.candidate_feasible(:,enabled+1))=-inf;
    [~,best]=max(scores); result.hover(enabled+3,:)=cfg.candidates(best,:);
end
for method=1:4
    notify(sprintf('method %d/4 acquisition',method));
    enabled=mod(method,2)==0;
    [p,prior]=uav_parameters(cfg,scene,result.hover(method,:),rcs);
    p.ris_enabled=false; coarse_design=uav_design(prior,p,false,1);
    result.noise_power(method)=p.noise_power; result.noise_w(method)=p.noise_w;
    [initial,info]=uav_coarse(p,coarse_design,seed+1);
    result.coarse(:,:,method)=initial; result.locked(method)=info.locked;
    result.input_snr_db(method)=info.input_snr_db;
    z=initial;
    if info.locked && coarse_design.feasible
        p.ris_enabled=enabled; obs=cell(2,1); design=cell(2,1); yy=cell(2,1);
        times=round(linspace(0,p.K-1,min(p.K,p.fine_l)));
        for s=1:2
            rng(seed+10+s,'twister'); obs{s}=prepare_ris_observation(initial,p,times(s:2:end));
            design{s}=uav_design(initial,p,enabled,s);
            rng(seed+20+s,'twister'); noise=(randn(p.Mx*p.My,size(obs{s}.symbol,2)) ...
                +1j*randn(p.Mx*p.My,size(obs{s}.symbol,2)))/sqrt(2);
            yy{s}=uav_echo(p,obs{s},design{s},noise);
        end
        result.design{method}=design;
        result.feasible(method)=all(cellfun(@(d) d.feasible,design));
        result.sinr_db(:,method)=min([10*log10(design{1}.sinr),10*log10(design{2}.sinr)],[],2);
        result.tx_power_fraction(method)=max(cellfun(@(d) norm(d.W,'fro')^2,design));
        if result.feasible(method)
            notify(sprintf('method %d/4 fine estimation',method));
            z=refine_ris_parameters(vertcat(yy{:}),obs,design,initial,p);
        end
    end
    evaluated=evaluate_estimation(z,p); rough=evaluate_estimation(initial,p);
    result.estimates(:,:,method)=evaluated.estimate;
    g=channel_geometry(evaluated.estimate,p); gt=channel_geometry(p.truth,p);
    gc=channel_geometry(rough.estimate,p);
    result.position_errors(:,method)=vecnorm(g.position-gt.position,2,1).';
    result.coarse_position_errors(:,method)=vecnorm(gc.position-gt.position,2,1).';
    result.velocity_errors(:,method)=evaluated.error(:,2);
    result.failure(method)=~result.locked(method) || ~result.feasible(method) ...
        || any(result.position_errors(:,method)>cfg.failure_position_m);
    result.parameters{method}=p;
end
result.seconds=toc(t);
assert(all(isfinite(result.position_errors),'all') && numel(unique(result.noise_power))==1);
end
