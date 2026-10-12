function test_ris_beta_sweep
% Check beta identity, 3-D masks, pooled RMSE, RNG and corrupt-file rejection.
folder=tempname; mkdir(folder);
cleanup=onCleanup(@() rmdir(folder,'s')); %#ok<NASGU>
cfg=struct('n_mc_total',2,'snr_list',[-25 20],'beta_list',[10 100 1000]);
shape=[4 2 3]; samples=cell(1,2);
for mc=1:2
    s=struct('config',cfg,'mc',mc,'completed',true(shape),'reference_target_power',1);
    for name={'rmse_theta','rmse_phi','rmse_R','rmse_v','detected', ...
            'sic_suppression_db','theta_sse','phi_sse','n_matched'}
        s.(name{1})=zeros(shape);
    end
    s.n_matched(:)=2; s.detected(:)=2;
    s.rmse_theta(:)=mc; s.rmse_phi(:)=mc;
    s.theta_sse(:)=2*mc^2; s.phi_sse(:)=2*mc^2;
    s.sic_suppression_db(1:2,:,:)=NaN;
    path=fullfile(folder,sprintf('mc_%05d.mat',mc));
    before=rng; ris_sic_save_atomic(path,s); assert(isequal(before,rng));
    [loaded,valid]=ris_beta_load_sample(path,cfg,mc); assert(valid && isequaln(loaded,s));
    samples{mc}=loaded;
end
out=ris_beta_summarize(samples,cfg);
assert(all(abs(out.pooled_theta_rmse(:)-sqrt(2.5))<1e-14));
assert(all(out.median_theta(:)==1.5));
path=fullfile(folder,'mc_00001.mat');
other=cfg; other.beta_list=[10 100 999];
[~,valid]=ris_beta_load_sample(path,other,1); assert(~valid);
s=samples{1}; s.completed(4,2,3)=false; ris_sic_save_atomic(path,s);
[loaded,valid]=ris_beta_load_sample(path,cfg,1);
assert(valid && nnz(loaded.completed)==23);
other_samples=samples; other_samples{1}=loaded;
rejected=false;
try, ris_beta_summarize(other_samples,cfg); catch, rejected=true; end
assert(rejected,'Incomplete sample accepted by aggregator.');
fid=fopen(path,'w'); fwrite(fid,'truncated MAT'); fclose(fid);
[~,valid]=ris_beta_load_sample(path,cfg,1); assert(~valid);
for file={'ris_beta_config.m','ris_beta_prepare.m','ris_beta_load_sample.m', ...
        'ris_beta_worker.m','ris_beta_summarize.m','aggregate_ris_beta_sweep.m'}
    notes=checkcode(file{1},'-id'); assert(~any(strcmp({notes.id},'SYNER')));
end
fprintf('BETA_SWEEP_TESTS_PASSED\n');
end
