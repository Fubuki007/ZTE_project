function report=test_uav_angles(output)
root=fileparts(mfilename('fullpath')); uav=fileparts(root); code=fileparts(uav);
addpath(root,uav,code); maxNumCompThreads(2); rng(20261116,'twister'); p=build_default_params();
[x,y]=ndgrid(0:p.Mx-1,0:p.My-1); xy=[x(:),y(:)]; truth=[85 170;70 -45]; snapshots=cell(1,2);
for q=1:2
    uv=sind(truth(q,1))*[cosd(truth(q,2));sind(truth(q,2))];
    snapshots{q}=exp(-1j*pi*xy*uv)*[1,.3+.4j];
end
exact=coarse_array_angles(snapshots,p); phase=coarse_array_angles(snapshots,p,'no_null');
assert(max(abs(exact-truth),[],'all')<1e-4 && max(abs(phase-truth),[],'all')<1e-10);
safe=rmfield(p,{'truth','alpha','R_true','v_true','theta_true','phi_true'});
assert(isequal(exact,coarse_array_angles(snapshots,safe)),'Angular estimator must not use truth.');
weak=snapshots{1}+2*(randn(64,2)+1j*randn(64,2))/sqrt(2);
matched=coarse_array_angles({weak},safe); adjacent=coarse_array_angles({weak},safe,'no_null');
beam=@(a) exp(-1j*pi*xy*(sind(a(1))*[cosd(a(2));sind(a(2))]));
assert(sum(abs(beam(matched)'*weak).^2)>=sum(abs(beam(adjacent)'*weak).^2)-1e-8);
cfg=uav_config('smoke'); scene=struct('targets',cfg.targets,'prior',cfg.targets+[5 -5 0;-5 5 0], ...
    'scatter_phase',[.7 1.4]);
[small,~]=uav_parameters(cfg,scene,cfg.hover,cfg.rcs_m2(2));
old=struct('p',small,'seed',cfg.seed,'trial',0,'rcs_index',2,'rcs_m2',cfg.rcs_m2(2),'scene',scene);
r=ua_case(old); assert(all(r.locked) && all(r.feasible) && all(isfinite(r.position_errors),'all'));
assert(all(r.initial_unmatched(:,3,:)>=0 & r.initial_unmatched(:,3,:)<=90,'all'));
report=struct('passed',true,'profile','smoke','methods',{r.methods}, ...
    'noiseless_angle_error_deg',max(abs(exact-truth),[],'all'), ...
    'position_rmse_m',sqrt(mean(r.position_errors.^2,1)), ...
    'checks',{{'receive steering sign and quadrant','near-horizon noiseless recovery', ...
    'no truth in angle estimator','weak-snapshot spatial likelihood','same range and velocity', ...
    'all four angular and fine-estimation branches'}});
if nargin, uav_write_json(output,report); end
disp(report);
end
