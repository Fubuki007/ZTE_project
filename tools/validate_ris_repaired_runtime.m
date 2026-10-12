function validate_ris_repaired_runtime(shard)
% Four long-running workers must exactly reproduce old full-size results.
ris_beta_worker(shard);
[cfg,prefix,shards]=ris_beta_config;
% Use the first two old SNR positions to preserve the noise-seed index.
assert(cfg.n_mc_total==4 && shards==4 && isequal(cfg.snr_list,[-25 -20]) && isequal(cfg.beta_list,0.1));
[fresh,valid,reason]=ris_beta_load_sample(fullfile(pwd,[prefix '_samples'], ...
    sprintf('mc_%05d.mat',shard)),cfg,shard);
assert(valid && all(fresh.completed(:)),reason);
previous=load(fullfile('/home/jzm123/AAA_ZTEproject', ...
    'ris_sic_rmse_snr_mc60_resume_v3_double_samples',sprintf('mc_%05d.mat',shard)));
map=[1 2 4 5];
[present,previous_snr]=ismember(cfg.snr_list,previous.config.snr_list);
assert(all(present));
for name={'rmse_theta','rmse_phi','rmse_R','rmse_v','detected','sic_suppression_db'}
    a=fresh.(name{1}); b=previous.(name{1});
    assert(isequaln(a(:,:,1),b(map,previous_snr)),['Changed results: ' name{1}]);
    fprintf('EXACT_MATCH MC=%d %s\n',shard,name{1});
end
fprintf('REPAIRED_RUNTIME_FULL_SIZE_PASSED MC=%d\n',shard);
end
