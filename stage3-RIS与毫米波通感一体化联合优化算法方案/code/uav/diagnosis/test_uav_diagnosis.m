function report=test_uav_diagnosis(output)
root=fileparts(mfilename('fullpath')); uav=fileparts(root); code=fileparts(uav);
addpath(root,uav,code,fullfile(code,'path_reliability')); maxNumCompThreads(2);
cfg=uav_config('smoke'); old=uav_case(cfg,0,2); p=old.parameters{3};
[~,prior]=uav_parameters(cfg,old.scene,p.hover,old.rcs_m2);
w=uav_rx_weights(prior,p); other=p; other.truth=p.truth+10; other.alpha=p.alpha*100;
assert(isequal(w,uav_rx_weights(prior,other)) && abs(norm(w)-1)<1e-12);
p.ris_enabled=false; d=uav_design(prior,p,false,1); md=ceil(p.Mx*p.My/2);
one=zeros(p.Mx*p.My,1); one(md)=1;
a=uav_coarse(p,d,old.seed+1); b=uav_coarse(p,d,old.seed+1,one);
assert(max(abs(a-b),[],'all')<1e-8,'Single-channel receiver replay differs.');
r=ud_case(old);
assert(all(isfinite(r.position_errors),'all') && all(r.locked));
assert(r.replay_error_m<1e-6 && r.synthesis_relative_error<1e-8);
assert(all(r.feasible([1:6,9:15])),'Smoke must reach every operational branch.');
for condition=1:2
    bank=r.banks{condition}; [~,choice]=min(cellfun(@(f) f.bic,bank.fits));
    assert(choice==bank.choice && isequal(size(bank.estimates),[2 4 8]));
    for k=1:8, assert(all(diff(bank.fits{k}.cost_history)<=1e-6)); end
end
report=struct('passed',true,'profile','smoke','methods',{r.methods}, ...
    'position_rmse_m',sqrt(mean(r.position_errors.^2,1)), ...
    'legacy_replay_error_m',r.replay_error_m,'synthesis_relative_error',r.synthesis_relative_error, ...
    'noise_w',r.noise_w,'BIC_choice',cellfun(@(b) b.choice,r.banks), ...
    'checks',{{'prior-only unit receive beam','correlated single-channel replay', ...
    'legacy result replay','physical four-path synthesis','BIC minima','monotone costs','all method branches'}});
if nargin, uav_write_json(output,report); end
disp(report);
end
