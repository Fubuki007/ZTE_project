function out = ris_beta_summarize(samples,cfg)
% Pool squared target errors, rather than taking the median of trial RMSEs.
n=cfg.n_mc_total; shape=[4 numel(cfg.snr_list) numel(cfg.beta_list) n];
names={'rmse_theta','rmse_phi','rmse_R','rmse_v','detected', ...
    'sic_suppression_db','theta_sse','phi_sse','n_matched'};
out=struct('config',cfg);
for k=1:numel(names), out.(names{k})=NaN(shape); end
assert(numel(samples)==n,'Missing MC samples.');
for mc=1:n
    s=samples{mc};
    assert(s.mc==mc && isequaln(s.config,cfg) && all(s.completed(:)),'Incomplete or incompatible sample.');
    for k=1:numel(names), out.(names{k})(:,:,:,mc)=s.(names{k}); end
end
count=sum(out.n_matched,4);
out.pooled_theta_rmse=sqrt(sum(out.theta_sse,4)./count);
out.pooled_phi_rmse=sqrt(sum(out.phi_sse,4)./count);
out.pooled_theta_rmse(count==0)=NaN; out.pooled_phi_rmse(count==0)=NaN;
out.median_theta=median(out.rmse_theta,4,'omitnan');
out.mean_theta=mean(out.rmse_theta,4,'omitnan');
out.median_phi=median(out.rmse_phi,4,'omitnan');
out.mean_detected=mean(out.detected,4,'omitnan');
out.median_sic_suppression_db=median(out.sic_suppression_db,4,'omitnan');
out.valid_mc=sum(out.n_matched>0,4);
out.timestamp=char(datetime('now','Format','yyyy-MM-dd HH:mm:ss'));
end
