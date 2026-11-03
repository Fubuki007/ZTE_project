function finalize_loc_aggregation(original_code,run)
% Recompute summaries with the reviewed aggregation code; preserve the original
% summaries and record its hash without modifying simulation checkpoints.
root=fileparts(mfilename('fullpath')); cd(root);
addpath(original_code,fullfile(original_code,'fas'),root);
assert(strcmp(which('aggregate_localization'),fullfile(root,'aggregate_localization.m')));
progress=jsondecode(fileread(fullfile(run,'progress.json')));
manifest=jsondecode(fileread(fullfile(run,'manifest.json')));
assert(progress.complete && progress.total_completed==manifest.total_cases);
assert(strcmp(strtrim(fileread(fullfile(run,'state'))),'COMPLETE'));
assert(strcmp(manifest.profile,'full') && all(progress.counts==300) && progress.oracle_completed==300);
archive=fullfile(run,'summary_before_peb_fix'); if ~exist(archive,'dir'), mkdir(archive); end
files={'metrics.csv','paired_gain.csv','oracle.csv','comparison.png','progress.json'};
for k=1:numel(files)
    dest=fullfile(archive,files{k}); if ~exist(dest,'file'), copyfile(fullfile(run,files{k}),dest); end
end
f=fopen(fullfile(root,'aggregate_localization.m'),'rb'); bytes=fread(f,inf,'*uint8'); fclose(f);
aggregate_localization(run);
metrics=readtable(fullfile(run,'metrics.csv'));
assert(all(isinf(metrics.peb_rms_m(metrics.singular_information_cases>0))));
evidence=struct('complete',true,'input_manifest_id',manifest.id,'aggregation_sha256',fas_hash(bytes), ...
    'singular_information_cases_by_metric_row',metrics.singular_information_cases.', ...
    'purpose','Preserve infinite PEBs; no simulation checkpoint changed', ...
    'updated_utc',char(datetime('now','TimeZone','UTC','Format','yyyy-MM-dd''T''HH:mm:ss''Z''')));
fas_write_json(fullfile(run,'aggregation_revision.json'),evidence);
end
