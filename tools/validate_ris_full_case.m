function validate_ris_full_case
% Run in an isolated directory with the candidate generator and worker.
project = '/home/jzm123/AAA_ZTEproject';
addpath(project,'-end');
setenv('RIS_MC_TOTAL','60');
setenv('RIS_N_SHARDS','4');
setenv('RIS_RUN_TAG','math_validation');
setenv('RIS_CASES_PER_PROCESS','1');
setenv('RIS_USE_SINGLE','0');
setenv('RIS_SNR_LIST','');
run_ris_rmse_snr_sic_worker(1);
old = load(fullfile(project,'ris_sic_rmse_snr_mc60_resume_v3_double_samples','mc_00001.mat'));
new = load(fullfile(pwd,'ris_sic_rmse_snr_mc60_math_validation_double_samples','mc_00001.mat'));
assert(new.completed(1,1) && old.completed(1,1));
fields = {'rmse_theta','rmse_phi','rmse_R','rmse_v','detected','sic_suppression_db'};
for k=1:numel(fields)
    a=old.(fields{k}); b=new.(fields{k});
    assert(isequaln(a(1,1),b(1,1)),['Changed result: ' fields{k}]);
    fprintf('EXACT_MATCH %s %.17g\n',fields{k},b(1,1));
end
fprintf('FULL_CASE_EQUIVALENCE_PASSED\n');
end
