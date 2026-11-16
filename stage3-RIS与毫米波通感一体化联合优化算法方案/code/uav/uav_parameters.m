function [p,prior]=uav_parameters(cfg,scene,hover,rcs)
% Coordinates in metres. Local +z points down; rotation is right handed.
p=build_default_params();
if strcmp(cfg.profile,'smoke')
    p.N=512; p.K=32; p.coarse_n=128; p.coarse_l=16;
    p.fine_n=64; p.fine_l=16; p.fine_iterations=2;
    p.B=p.N*p.delta_f; p.fref=p.fc-floor(p.N/2)*p.delta_f;
    p.resolution=p.c/(2*p.B);
end
p.world_to_local=diag([1 -1 -1]); p.hover=hover;
z=to_local(scene.targets,hover,p.world_to_local);
prior=to_local(scene.prior,hover,p.world_to_local);
p.R_true=z(:,1).'; p.v_true=z(:,2).';
p.theta_true=z(:,3).'; p.phi_true=z(:,4).'; p.truth=z; p.Q=size(z,1);
p.ris_pos=p.world_to_local*(cfg.ris-hover).';
p.ris_normal=p.world_to_local*cfg.ris_normal.';
u=to_local(cfg.users,hover,p.world_to_local);
p.user_R=u(:,1).'; p.user_theta=u(:,3).'; p.user_phi=u(:,4).';
p.power_w=cfg.power_w; p.reference_range_m=cfg.reference_range_m;
p.noise_w=1.380649e-23*cfg.temperature_k*p.B*10^(cfg.noise_figure_db/10);
p.reference_amplitude=p.lambda/((4*pi)^1.5*cfg.reference_range_m^2);
p.noise_power=p.noise_w/(cfg.power_w*p.reference_amplitude^2);
p.comm_noise=repmat(p.noise_w/cfg.power_w,p.K_stream,1);
sigma=rcs*[1 .8];
p.alpha=sqrt(sigma).*(cfg.reference_range_m./p.R_true).^2 ...
    .*exp(1j*scene.scatter_phase-1j*4*pi*p.fref/p.c*p.R_true);
% Inherited centre-frequency steering and passive panel scattering model.
assert(abs(det(p.world_to_local)-1)<1e-12 && abs(p.ris_normal(2))<1e-12);
assert(all(p.truth(:,3)>0 & p.truth(:,3)<90));
end

function z=to_local(points,hover,rotation)
v=(rotation*(points-hover).').'; r=vecnorm(v,2,2);
z=[r,zeros(size(r)),acosd(v(:,3)./r),atan2d(v(:,2),v(:,1))];
end
