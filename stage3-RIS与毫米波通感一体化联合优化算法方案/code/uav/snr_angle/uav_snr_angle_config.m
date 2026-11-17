function cfg=uav_snr_angle_config(profile)
if nargin<1, profile='full'; end
if strcmp(profile,'smoke')
    cfg=uav_config('smoke');
    cfg.snr_db=[-60 -40 -20];
else
    assert(ismember(profile,{'full','pilot'}));
    cfg=uav_config('full');
    cfg.snr_db=-60:5:-20;
end
cfg.rcs_m2=[10 100 1000];
cfg.seed=20261118;
cfg.methods={'RIS_fine_after_direct_coarse'};
end
