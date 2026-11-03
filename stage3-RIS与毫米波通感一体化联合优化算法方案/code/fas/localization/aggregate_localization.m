function aggregate_localization(output)
root=fileparts(mfilename('fullpath')); addpath(root,fileparts(root));
manifest=jsondecode(fileread(fullfile(output,'manifest.json'))); opt=manifest.options;
names=cellstr(manifest.methods); ns=numel(opt.snr_db); nm=numel(names);
metrics=struct([]); gains=struct([]); oracle=struct([]); counts=zeros(1,ns);
rmse=nan(ns,nm); pebcurve=rmse; rng(20261103,'twister');
for si=1:ns
    squared=zeros(opt.mc,nm); pebs=nan(opt.mc,nm); failures=false(opt.mc,nm); feasible=failures;
    for trial=0:opt.mc-1
        file=fullfile(output,'samples',sprintf('snr_%02d_mc_%04d.mat',si,trial));
        a=load(file,'result','manifest_id'); assert(strcmp(a.manifest_id,manifest.id)); r=a.result;
        assert(r.trial==trial && r.snr_index==si && isequal(r.methods(:),names(:)));
        squared(trial+1,:)=mean(r.position_errors.^2,1); pebs(trial+1,:)=r.peb;
        failures(trial+1,:)=r.failure; feasible(trial+1,:)=r.feasible; counts(si)=counts(si)+1;
        if isfield(r,'oracle')
            o=r.oracle; entry=struct('trial',trial,'snr_db',r.snr_db,'fixed_peb_m',o.fixed_peb, ...
                'fas_peb_m',o.fas_peb,'fas_guard4_peb_m',o.fas_guard4_peb, ...
                'gain_percent',100*(1-o.fas_peb/o.fixed_peb), ...
                'guard4_gain_percent',100*(1-o.fas_guard4_peb/o.fixed_peb), ...
                'continuous_objective_gain_percent',100*(1-o.fas_search.continuous_peb/o.fixed_search.peb));
            if isempty(oracle), oracle=entry; else, oracle(end+1)=entry; end
        end
    end
    bootstrap=randi(opt.mc,opt.mc,2000); boot=zeros(2000,nm);
    for m=1:nm
        errors=squared(:,m); boot(:,m)=sqrt(mean(errors(bootstrap),1)).'; ci=quantile(boot(:,m),[.025,.975]);
        rmse(si,m)=sqrt(mean(errors)); valid=~isnan(pebs(:,m)); pebcurve(si,m)=sqrt(mean(pebs(valid,m).^2));
        entry=struct('snr_db',opt.snr_db(si),'method',names{m},'mc_completed',opt.mc, ...
            'position_rmse_m',rmse(si,m),'ci95_low',ci(1),'ci95_high',ci(2), ...
            'failure_rate',mean(failures(:,m)),'feasible_rate',mean(feasible(:,m)), ...
            'peb_rms_m',pebcurve(si,m),'information_cases',sum(valid), ...
            'singular_information_cases',sum(isinf(pebs(:,m))));
        if isempty(metrics), metrics=entry; else, metrics(end+1)=entry; end
    end
    comparisons=[4 1;5 4;6 4;5 2;6 3];
    for k=1:size(comparisons,1)
        m=comparisons(k,1); b=comparisons(k,2);
        samples=100*(1-boot(:,m)./boot(:,b)); ci=quantile(samples,[.025,.975]);
        entry=struct('snr_db',opt.snr_db(si),'method',names{m},'reference',names{b}, ...
            'gain_percent',100*(1-rmse(si,m)/rmse(si,b)),'paired_ci95_low',ci(1),'paired_ci95_high',ci(2));
        if isempty(gains), gains=entry; else, gains(end+1)=entry; end
    end
end
assert(all(counts==opt.mc));
if strcmp(manifest.profile,'full'), assert(numel(oracle)==300,'Oracle reference is incomplete.'); end
writetable(struct2table(metrics),fullfile(output,'metrics.csv'));
writetable(struct2table(gains),fullfile(output,'paired_gain.csv'));
if ~isempty(oracle), writetable(struct2table(oracle),fullfile(output,'oracle.csv')); end
f=figure('Visible','off','Color','w','Position',[100 100 1200 820]); cleanup=onCleanup(@() close(f));
subplot(2,2,1); semilogy(opt.snr_db,rmse,'-o'); grid on; xlabel('SNR (dB)'); ylabel('Position RMSE (m)'); legend(names,'Interpreter','none','Location','best');
subplot(2,2,2); semilogy(opt.snr_db,pebcurve,'-o'); grid on; xlabel('SNR (dB)'); ylabel('Conditional PEB RMS (m)');
subplot(2,2,3);
for m=5:6
    subset=gains(strcmp({gains.method},names{m}) & strcmp({gains.reference},names{4}));
    y=[subset.gain_percent]; errorbar(opt.snr_db,y,y-[subset.paired_ci95_low],[subset.paired_ci95_high]-y,'-o'); hold on;
end
yline(0); grid on; xlabel('SNR (dB)'); ylabel('FAS vs fixed localization RMSE reduction (%)'); legend('guard 0','guard 4','Location','best');
subplot(2,2,4);
if ~isempty(oracle)
    plot(sort([oracle.gain_percent]),(1:numel(oracle))/numel(oracle),'LineWidth',1.5); hold on;
    plot(sort([oracle.guard4_gain_percent]),(1:numel(oracle))/numel(oracle),'LineWidth',1.5);
    grid on; xlabel('Oracle PEB reduction (%)'); ylabel('Fraction of geometries'); legend('guard 0','guard 4','Location','best');
end
sgtitle(sprintf('%s | %d/%d original paired inputs | localization objective',upper(manifest.profile),sum(counts),manifest.total_cases));
exportgraphics(f,fullfile(output,'comparison.png'),'Resolution',180);
fas_write_json(fullfile(output,'progress.json'),struct('complete',true,'manifest_id',manifest.id, ...
    'counts',counts,'total_completed',sum(counts),'total_expected',manifest.total_cases,'oracle_completed',numel(oracle)));
fprintf('AGGREGATED %d/%d localization cases\n',sum(counts),manifest.total_cases);
end
