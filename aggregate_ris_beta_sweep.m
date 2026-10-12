function out = aggregate_ris_beta_sweep
[cfg,prefix]=ris_beta_config;
root=fileparts(mfilename('fullpath')); folder=fullfile(root,[prefix '_samples']);
samples=cell(1,cfg.n_mc_total);
for mc=1:cfg.n_mc_total
    [s,valid,reason]=ris_beta_load_sample(fullfile(folder,sprintf('mc_%05d.mat',mc)),cfg,mc);
    assert(valid && all(s.completed(:)),'RIS:InvalidCheckpoint','MC=%d missing or invalid: %s',mc,reason);
    samples{mc}=s;
end
out=ris_beta_summarize(samples,cfg);
ris_sic_save_atomic(fullfile(root,[prefix '_results.mat']),out);
fid=fopen(fullfile(root,[prefix '_summary.csv']),'w'); assert(fid>=0);
close_file=onCleanup(@() fclose(fid)); %#ok<NASGU>
fprintf(fid,'beta_SI,snr_dB,scheme,pooled_theta_rmse_deg,median_theta_rmse_deg,mean_theta_rmse_deg,pooled_phi_rmse_deg,mean_detected,valid_mc,median_sic_suppression_db\n');
for bi=1:numel(cfg.beta_list)
    for si=1:4
        for ni=1:numel(cfg.snr_list)
            fprintf(fid,'%.12g,%.12g,%s,%.12g,%.12g,%.12g,%.12g,%.12g,%d,%.12g\n', ...
                cfg.beta_list(bi),cfg.snr_list(ni),cfg.scheme_names{si}, ...
                out.pooled_theta_rmse(si,ni,bi),out.median_theta(si,ni,bi), ...
                out.mean_theta(si,ni,bi),out.pooled_phi_rmse(si,ni,bi), ...
                out.mean_detected(si,ni,bi),out.valid_mc(si,ni,bi),out.median_sic_suppression_db(si,ni,bi));
        end
    end
end
figdir=fullfile(root,'fig'); if ~isfolder(figdir), mkdir(figdir); end
colors=[0.1 0.35 0.8;0.85 0.3 0.08;0.4 0.15 0.65;0.1 0.6 0.25];
for stat=1:2
    if stat==1, Y=out.pooled_theta_rmse; tag='angle_rmse'; label='Elevation angle RMSE (deg)';
    else, Y=out.median_theta; tag='angle_median_rmse'; label='Median trial elevation RMSE (deg)'; end
    combined=figure('Visible','off','Color','w','Position',[60 60 1500 520]);
    for bi=1:numel(cfg.beta_list)
        figure(combined); subplot(1,numel(cfg.beta_list),bi);
        draw_panel(cfg,Y(:,:,bi),colors,label,bi);
        if stat==1
            one=figure('Visible','off','Color','w','Position',[100 100 1050 680]);
            draw_panel(cfg,Y(:,:,bi),colors,label,bi);
            save_plot(one,fullfile(figdir,sprintf('%s_beta%g_%s',prefix,cfg.beta_list(bi),tag)));
            close(one);
        end
    end
    figure(combined); sgtitle(sprintf('RIS/SIC comparison, paired MC=%d, continuous RIS, pilot-LS SIC',cfg.n_mc_total));
    save_plot(combined,fullfile(figdir,[prefix '_' tag '_all'])); close(combined);
end
fprintf('AGGREGATED_RESULT=%s\n',fullfile(root,[prefix '_results.mat']));
end

function draw_panel(cfg,Y,colors,label,bi)
hold on; grid on;
styles={'--o','--s','-o','-s'};
for si=1:4
    semilogy(cfg.snr_list,max(Y(si,:),1e-12),styles{si},'LineWidth',1.5, ...
        'Color',colors(si,:),'MarkerSize',5,'DisplayName',cfg.scheme_names{si});
end
set(gca,'YScale','log','FontName','Arial','FontSize',11);
xlabel('SNR (dB)'); ylabel(label); title(sprintf('beta_{SI} = %g',cfg.beta_list(bi)));
if numel(cfg.snr_list)>1, xlim([cfg.snr_list(1) cfg.snr_list(end)]); end
legend('Location','best');
end

function save_plot(fig,path)
print(fig,[path '.png'],'-dpng','-r180'); savefig(fig,[path '.fig']);
print(fig,[path '.eps'],'-depsc','-painters');
end
