function test_ris_sic_resume
% Check persistence, interrupted work, invalid data and deterministic RNG.
folder = tempname;
mkdir(folder);
cleanup = onCleanup(@() rmdir(folder,'s')); %#ok<NASGU>
config = struct('format_version',3,'n_mc_total',2,'snr_list',[-25 20], ...
    'beta_si',0.1,'use_single',false);
sample = struct('mc',1,'config',config,'completed',false(6,2));
metrics = {'rmse_theta','rmse_phi','rmse_R','rmse_v','detected','sic_suppression_db'};
for k = 1:numel(metrics), sample.(metrics{k}) = NaN(6,2); end
sample.completed(1,1) = true;
for k = 1:5, sample.(metrics{k})(1,1) = 2; end
path_name = fullfile(folder,'mc_00001.mat');
rng(42,'twister'); previous_rng = rng;
ris_sic_save_atomic(path_name,sample);
assert(isequal(rng,previous_rng),'Checkpoint save changed simulation RNG.');
[loaded,valid] = ris_sic_load_sample(path_name,config,1);
assert(valid && nnz(loaded.completed)==1 && isequaln(sample,loaded));
assert(isempty(dir(fullfile(folder,'*.tmp*'))));
assert(numel(dir(fullfile(folder,'*.mat')))==1,'Uncommitted temporary MAT remained.');
incompatible = config; incompatible.use_single = true;
[~,valid] = ris_sic_load_sample(path_name,incompatible,1);
assert(~valid,'Mixed precision checkpoint was accepted.');
[~,valid] = ris_sic_load_sample(path_name,config,2);
assert(~valid,'Wrong MC index was accepted.');
sample.completed(:) = true;
for k = 1:5, sample.(metrics{k})(:) = 2; end
% Zero detections are completed, even though the RMSE values are NaN.
sample.detected(1,2)=0;
for k = 1:4, sample.(metrics{k})(1,2)=NaN; end
ris_sic_save_atomic(path_name,sample);
[loaded,valid] = ris_sic_load_sample(path_name,config,1);
assert(valid && all(loaded.completed(:)));
sample.rmse_R=zeros(1,2);
ris_sic_save_atomic(path_name,sample);
[~,valid] = ris_sic_load_sample(path_name,config,1);
assert(~valid,'Malformed checkpoint was accepted.');
fid=fopen(path_name,'w'); fwrite(fid,'interrupted MAT write'); fclose(fid);
[~,valid] = ris_sic_load_sample(path_name,config,1);
assert(~valid,'Truncated file was accepted.');
files={'run_ris_rmse_snr_sic_worker.m','aggregate_ris_sic_rmse_snr_mc60.m', ...
    'ris_sic_run_config.m','ris_sic_save_atomic.m','ris_sic_load_sample.m'};
for k=1:numel(files)
    notes=checkcode(files{k},'-id');
    assert(~any(strcmp({notes.id},'SYNER')),'Syntax error in %s',files{k});
end
disp('CHECKPOINT_TESTS_PASSED');
end
