function report=test_uav_snr_angle(output)
root=fileparts(mfilename('fullpath')); uav=fileparts(root); code=fileparts(uav);
addpath(root,uav,code); maxNumCompThreads(2);
cfg=uav_snr_angle_config('smoke');
r=uav_snr_angle_case(cfg,0,3,3);
assert(all(isfinite(r.angular_error_deg)) ...
    && abs(r.reference_snr_db-cfg.snr_db(3))<1e-10);
assert(r.ris_fine_used && all(cellfun(@(d) d.feasible,r.designs)));
report=struct('passed',true,'profile','local_smoke','rcs_m2',r.rcs_m2, ...
    'reference_snr_db',r.reference_snr_db,'ris_fine_used',r.ris_fine_used, ...
    'angle_error_deg',r.angular_error_deg,'checks',{{'requested reference SNR', ...
    'RIS phase quantization and feasibility','finite spherical angle error'}});
if nargin, uav_write_json(output,report); end
disp(report);
end
