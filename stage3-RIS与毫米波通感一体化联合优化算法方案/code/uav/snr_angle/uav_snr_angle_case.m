function r=uav_snr_angle_case(cfg,trial,rcs_index,snr_index,notify)
if nargin<5, notify=@(s) []; end
seed=cfg.seed+10000*trial; rng(seed,'twister');
scene.targets=cfg.targets;
scene.targets(:,1:2)=scene.targets(:,1:2)+cfg.target_jitter_m*randn(2,2);
scene.prior=scene.targets;
scene.prior(:,1:2)=scene.prior(:,1:2)+cfg.prior_sigma_m*randn(2,2);
scene.scatter_phase=2*pi*rand(1,2);
rcs=cfg.rcs_m2(rcs_index); requested_snr=cfg.snr_db(snr_index);
[p,prior]=uav_parameters(cfg,scene,cfg.hover,rcs);
reference_snr=10*log10(1/p.noise_power);
noise_scale=10.^((reference_snr-requested_snr)/10);
p.noise_w=p.noise_w*noise_scale;
p.noise_power=p.noise_power*noise_scale;
p.comm_noise=p.comm_noise*noise_scale;
assert(abs(10*log10(1/p.noise_power)-requested_snr)<1e-10);
notify('direct-path coarse acquisition');
coarse_design=uav_design(prior,p,false,1);
[initial,info]=uav_coarse(p,coarse_design,seed+1);
estimate=initial; designs=cell(2,1); ris_feasible=false;
if info.locked && coarse_design.feasible
    notify('RIS-assisted fine acquisition');
    obs=cell(2,1); echo=cell(2,1);
    times=round(linspace(0,p.K-1,min(p.K,p.fine_l)));
    for segment=1:2
        rng(seed+10+segment,'twister');
        obs{segment}=prepare_ris_observation(initial,p,times(segment:2:end));
        designs{segment}=uav_design(initial,p,true,segment);
        rng(seed+20+segment,'twister');
        noise=(randn(p.Mx*p.My,size(obs{segment}.symbol,2)) ...
            +1j*randn(p.Mx*p.My,size(obs{segment}.symbol,2)))/sqrt(2);
        echo{segment}=uav_echo(p,obs{segment},designs{segment},noise);
    end
    ris_feasible=all(cellfun(@(d) d.feasible,designs));
    if ris_feasible
        estimate=refine_ris_parameters(vertcat(echo{:}),obs,designs,initial,p);
    end
end
evaluated=evaluate_estimation(estimate,p); estimate=evaluated.estimate;
truth_direction=direction(p.truth(:,3:4)); estimate_direction=direction(estimate(:,3:4));
angular_error=acosd(max(-1,min(1,sum(truth_direction.*estimate_direction,2))));
geometry=channel_geometry(estimate,p); truth=channel_geometry(p.truth,p);
position_error=vecnorm(geometry.position-truth.position,2,1).';
ris_used=info.locked && coarse_design.feasible && ris_feasible;
r=struct('trial',trial,'rcs_index',rcs_index,'snr_index',snr_index,'rcs_m2',rcs, ...
    'requested_snr_db',requested_snr,'reference_snr_db',10*log10(1/p.noise_power), ...
    'input_snr_db',info.input_snr_db,'seed',seed,'scene',scene,'p',p,'prior',prior, ...
    'coarse',initial,'estimate',estimate,'angular_error_deg',angular_error, ...
    'position_error_m',position_error,'coarse_locked',info.locked, ...
    'coarse_design_feasible',coarse_design.feasible,'ris_feasible',ris_feasible, ...
    'ris_fine_used',ris_used,'failure',~info.locked || ~coarse_design.feasible ...
        || ~ris_feasible || any(position_error>cfg.failure_position_m), ...
    'noise_w',p.noise_w,'noise_power',p.noise_power,'designs',{designs},'seconds',NaN);
end

function v=direction(angles)
theta=angles(:,1); phi=angles(:,2);
v=[sind(theta).*cosd(phi),sind(theta).*sind(phi),cosd(theta)];
end
