function validate_ris_beta_equivalence
% Four full-size cases must reproduce the already validated beta=0.1 run.
test_ris_beta_sweep;
ris_beta_worker(1);
[cfg,prefix]=ris_beta_config;
assert(cfg.n_mc_total==1 && isequal(cfg.snr_list,-25) && isequal(cfg.beta_list,0.1));
fresh=load(fullfile(pwd,[prefix '_samples'],'mc_00001.mat'));
if ~all(fresh.completed(:))
    fprintf('EQUIVALENCE_PENDING completed=%d/%d; resume in a fresh process.\n', ...
        nnz(fresh.completed),numel(fresh.completed));
    return;
end
previous=load('/home/jzm123/AAA_ZTEproject/ris_sic_rmse_snr_mc60_resume_v3_double_samples/mc_00001.mat');
map=[1 2 4 5];
for name={'rmse_theta','rmse_phi','rmse_R','rmse_v','detected','sic_suppression_db'}
    a=fresh.(name{1}); b=previous.(name{1});
    assert(isequaln(a(:,1,1),b(map,1)),['Changed full-size results: ' name{1}]);
    fprintf('EXACT_MATCH_ALL_FOUR %s\n',name{1});
end
aggregate_ris_beta_sweep;
fprintf('BETA_FULL_SIZE_EQUIVALENCE_PASSED\n');
end
