function test_loc_aggregation(code,source,destination)
% Synthetic edge case built only from the local smoke fixture, never full data.
assert(ispc && ~exist(destination,'dir'));
manifest=jsondecode(fileread(fullfile(source,'manifest.json')));
assert(strcmp(manifest.profile,'smoke') && manifest.total_cases==2);
copyfile(source,destination); file=fullfile(destination,'samples','snr_02_mc_0000.mat');
saved=load(file); result=saved.result; manifest_id=saved.manifest_id;
result.peb(6)=Inf; save(file,'result','manifest_id','-v7');
addpath(code,fullfile(code,'fas'),fullfile(code,'fas','localization'));
aggregate_localization(destination);
metrics=readtable(fullfile(destination,'metrics.csv'));
row=metrics.snr_db==10 & strcmp(metrics.method,'FAS_localization_guard4');
assert(sum(row)==1 && isinf(metrics.peb_rms_m(row)));
assert(metrics.information_cases(row)==1 && metrics.singular_information_cases(row)==1);
missing=metrics.snr_db==-20;
assert(all(isnan(metrics.peb_rms_m(missing))) && all(metrics.information_cases(missing)==0));
fas_write_json(fullfile(destination,'aggregation_test.json'),struct('passed',true, ...
    'profile','synthetic smoke fixture','checks',{{'Infinite PEB retained','Singular case counted','Unavailable coarse-stage information excluded'}}));
fprintf('AGGREGATION EDGE-CASE TEST PASSED\n');
end
