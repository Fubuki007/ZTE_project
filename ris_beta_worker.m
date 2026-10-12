function ris_beta_worker(shard)
% Full-size paired beta/SNR sweep with per-case atomic commits.
[cfg,prefix,shards] = ris_beta_config;
assert(shard>=1 && shard<=shards && shard==fix(shard));
root=fileparts(mfilename('fullpath')); addpath(root);
folder=fullfile(root,[prefix '_samples']);
if ~isfolder(folder), mkdir(folder); end
budget=str2double(getenv('RIS_CASES_PER_PROCESS'));
if isnan(budget), budget=1; end
assert(isfinite(budget) && budget>=1 && budget==fix(budget));
fprintf('WORKER_START shard=%d/%d MC=%d SNR=%s beta=%s batch=%d\n', ...
    shard,shards,cfg.n_mc_total,mat2str(cfg.snr_list),mat2str(cfg.beta_list),budget);
prepared=ris_beta_prepare(cfg,root,prefix);
p0=prepared.params;
shape=[4 numel(cfg.snr_list) numel(cfg.beta_list)];
saved=0;
for mc=shard:shards:cfg.n_mc_total
    path=fullfile(folder,sprintf('mc_%05d.mat',mc));
    [s,valid,reason]=ris_beta_load_sample(path,cfg,mc);
    if ~valid && isfile(path), error('RIS:InvalidCheckpoint','Configuration mismatch or invalid data: %s',reason); end
    if valid
        fprintf('RESUMED MC=%d cases=%d/%d\n',mc,nnz(s.completed),numel(s.completed));
        if all(s.completed(:)), continue; end
    end
    rng(2026106000+mc,'twister');
    p_mc=p0; p_mc.H_SI=generate_HSI(prepared.hsi_cfg); p_mc.H_SI_matrix=p_mc.H_SI;
    rng(2026101000+mc,'twister');
    tx_full=generate_mimo_ofdm_waveform(p_mc); tx=tx_full.X; clear tx_full;
    rng(2026105000+mc,'twister');
    pilot=(randn(p0.Ntx*p0.Nty,cfg.sic_pilot_len)+ ...
        1j*randn(p0.Ntx*p0.Nty,cfg.sic_pilot_len))/sqrt(2);
    if ~valid
        ref=p_mc; ref.enable_SI=false; ref.enable_SIC=false;
        ref.beta_SI=0; ref.ris_target_model=[]; ref.SNR=Inf;
        rng(2026102000+mc,'twister');
        [~,info]=simulate_radar_channel_3d(tx,ref);
        s=struct('config',cfg,'mc',mc,'completed',false(shape), ...
            'reference_target_power',info.target_signal_power);
        for name={'rmse_theta','rmse_phi','rmse_R','rmse_v','detected', ...
                'sic_suppression_db','theta_sse','phi_sse','n_matched'}
            s.(name{1})=NaN(shape);
        end
        ris_sic_save_atomic(path,s);
    end
    for ni=1:numel(cfg.snr_list)
        for bi=1:numel(cfg.beta_list)
            for si=1:4
                if s.completed(si,ni,bi), continue; end
                started=tic;
                p=p_mc; p.SNR=cfg.snr_list(ni); p.beta_SI=cfg.beta_list(bi);
                p.noise_reference_target_power=s.reference_target_power;
                p.SIC_pilot=pilot; p.enable_SIC=si>=3;
                if mod(si,2)==0
                    p.ris_target_model=prepared.model_template;
                    p.ris_target_model.phi=prepared.phi_cont;
                else
                    p.ris_target_model=[];
                end
                % Pair AWGN across RIS, SIC and beta, as in the preceding sweep.
                rng(2026103000+1000*mc+ni,'twister');
                if ~p.enable_SIC
                    randn(p.Mx*p.My,cfg.sic_pilot_len,'like',p.H_SI);
                    randn(p.Mx*p.My,cfg.sic_pilot_len,'like',p.H_SI);
                end
                fprintf('CASE_START MC=%d SNR=%+g beta=%g scheme=%d channel\n',mc,p.SNR,p.beta_SI,si);
                [rx,sim]=simulate_radar_channel_3d(tx,p);
                fprintf('CASE_STAGE MC=%d SNR=%+g beta=%g scheme=%d estimator\n',mc,p.SNR,p.beta_SI,si);
                [theta,phi,R,v,est]=joint_estimator_fast(rx,tx,p);
                cmp=evaluate_estimation(theta,phi,R,v,p,false);
                clear rx;
                for name={'rmse_theta','rmse_phi','rmse_R','rmse_v'}
                    s.(name{1})(si,ni,bi)=cmp.(name{1});
                end
                s.detected(si,ni,bi)=est.detected_targets;
                s.n_matched(si,ni,bi)=numel(cmp.theta_err);
                s.theta_sse(si,ni,bi)=sum(cmp.theta_err.^2);
                s.phi_sse(si,ni,bi)=sum(cmp.phi_err.^2);
                if p.enable_SIC
                    assert(sim.sic.applied,'Requested SIC was not applied.');
                    s.sic_suppression_db(si,ni,bi)=sim.sic.suppression_db;
                end
                s.completed(si,ni,bi)=true;
                ris_sic_save_atomic(path,s);
                saved=saved+1;
                fprintf('CASE_SAVED MC=%d/%d SNR=%+g beta=%g scheme=%d elapsed=%.3f (%d/%d)\n', ...
                    mc,cfg.n_mc_total,p.SNR,p.beta_SI,si,toc(started),nnz(s.completed),numel(s.completed));
                if saved>=budget
                    fprintf('BATCH_YIELD saved=%d; checkpoints committed.\n',saved);
                    return;
                end
            end
        end
    end
    clear tx p_mc pilot;
end
out=struct('config',cfg,'shard',shard,'shards',shards,'complete',true);
path=fullfile(root,sprintf('%s_shard%d.mat',prefix,shard));
ris_sic_save_atomic(path,out);
fprintf('FINAL_RESULT=%s\n',path);
end
