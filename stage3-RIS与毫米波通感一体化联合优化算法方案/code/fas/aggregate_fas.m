function aggregate_fas(output,partial)
if nargin<2, partial=false; end
manifest=jsondecode(fileread(fullfile(output,'manifest.json'))); opt=manifest.options;
names=cellstr(manifest.methods); nm=numel(names); ns=numel(opt.snr_db);
rows=struct([]); gains=struct([]); counts=zeros(1,ns); curves=nan(ns,nm,4);
rng(20261023,'twister');
for si=1:ns
    pos=[]; errors=[]; fails=[]; feasible=[]; timings=[]; sinrs=[]; pooled=[];
    for trial=0:opt.mc-1
        file=fullfile(output,'samples',sprintf('snr_%02d_mc_%04d.mat',si,trial));
        if ~exist(file,'file'), continue; end
        loaded=load(file,'result','manifest_id'); assert(strcmp(loaded.manifest_id,manifest.id));
        r=loaded.result;
        assert(r.trial==trial && r.snr_index==si && isequal(r.methods(:),names(:)));
        pos(end+1,:)=mean(r.position_errors.^2,1);
        errors(end+1,:,:)=reshape(mean(r.errors.^2,1),[1,4,nm]);
        pooled=cat(1,pooled,r.position_errors);
        fails(end+1,:)=r.failure; feasible(end+1,:)=r.feasible;
        timings(end+1,:)=r.processing_seconds;
        sinrs(end+1,:)=min(r.communication_min_sinr,[],1);
    end
    count=size(pos,1); counts(si)=count;
    if count==0, continue; end
    bootstrap=randi(count,count,2000);
    boot=zeros(2000,nm);
    for m=1:nm
        squared=pos(:,m); boot(:,m)=sqrt(mean(squared(bootstrap),1)).';
        ci=quantile(boot(:,m),[.025,.975]);
        params=sqrt(mean(errors(:,:,m),1));
        entry=struct('snr_db',opt.snr_db(si),'method',names{m},'mc_completed',count, ...
            'position_rmse_m',sqrt(mean(pos(:,m))),'position_ci95_low',ci(1), ...
            'position_ci95_high',ci(2),'position_p95_m',quantile(pooled(:,m),.95), ...
            'range_rmse_m',params(1),'velocity_rmse_mps',params(2), ...
            'theta_rmse_deg',params(3),'phi_rmse_deg',params(4), ...
            'angle_rmse_deg',sqrt(mean(params(3:4).^2)), ...
            'failure_rate',mean(fails(:,m)),'communication_feasible_rate',mean(feasible(:,m)), ...
            'minimum_communication_sinr',min(sinrs(:,m)), ...
            'mean_processing_seconds',mean(timings(:,m)));
        if isempty(rows), rows=entry; else, rows(end+1)=entry; end
        curves(si,m,:)=[entry.position_rmse_m,entry.range_rmse_m,entry.angle_rmse_deg,entry.velocity_rmse_mps];
    end
    % Resample whole paired MC cases, never individual targets or methods.
    for m=3:nm
        if contains(names{m},'noRIS'), base=1; else, base=2; end
        gain=100*(1-sqrt(mean(pos(:,m)))/max(sqrt(mean(pos(:,base))),eps));
        samples=100*(1-boot(:,m)./max(boot(:,base),eps)); ci=quantile(samples,[.025,.975]);
        entry=struct('snr_db',opt.snr_db(si),'method',names{m}, ...
            'reference',names{base},'mc_completed',count,'position_rmse_reduction_percent',gain, ...
            'paired_ci95_low',ci(1),'paired_ci95_high',ci(2));
        if isempty(gains), gains=entry; else, gains(end+1)=entry; end
    end
end
complete=all(counts==opt.mc);
assert(complete || partial,'Incomplete experiment: %d/%d samples.',sum(counts),manifest.total_cases);
if ~isempty(rows), writetable(struct2table(rows),fullfile(output,'metrics.csv')); end
if ~isempty(gains), writetable(struct2table(gains),fullfile(output,'paired_gain.csv')); end
if ~isempty(rows)
    f=figure('Visible','off','Color','w','Position',[100 100 1100 750]);
    cleanup=onCleanup(@() close(f));
    labels={'Position RMSE (m)','Range RMSE (m)','Angle RMSE (degree)','Velocity RMSE (m/s)'};
    for metric=1:4
        subplot(2,2,metric); semilogy(opt.snr_db,curves(:,1:4,metric),'-o','LineWidth',1.4);
        grid on; xlabel('SNR (dB)'); ylabel(labels{metric}); legend(names(1:4),'Interpreter','none','Location','best');
    end
    if strcmp(opt.profile,'smoke'), titletext='LOCAL SMOKE - NOT FORMAL PERFORMANCE';
    elseif ~complete, titletext='FULL CONFIGURATION - INCOMPLETE';
    else, titletext='FULL CONFIGURATION - COMPLETE'; end
    sgtitle(sprintf('%s | MC %d-%d/%d | FAS guard %d symbols',titletext,min(counts),max(counts),opt.mc,opt.main_guard));
    exportgraphics(f,fullfile(output,'comparison.png'),'Resolution',180);
end
fas_write_json(fullfile(output,'progress.json'),struct('manifest_id',manifest.id,'complete',complete, ...
    'counts',counts,'total_completed',sum(counts),'total_expected',manifest.total_cases));
fprintf('AGGREGATED %d/%d complete=%d\n',sum(counts),manifest.total_cases,complete);
end
