function summary=aggregate_uav_snr_angle(output)
root=fileparts(mfilename('fullpath')); uav=fileparts(root); code=fileparts(uav);
addpath(root,uav,code); maxNumCompThreads(2);
m=jsondecode(fileread(fullfile(output,'manifest.json'))); cfg=m.config;
for k=1:numel(m.source)
    assert(strcmp(filehash(fullfile(code,m.source(k).file)),m.source(k).sha256));
end
nt=numel(m.trials); nr=numel(cfg.rcs_m2); ns=numel(cfg.snr_db);
assert(numel(dir(fullfile(output,'samples','mc_*.mat')))==m.total_cases);
used=false(nt,nr,ns); angle=zeros(nt,nr,ns,2); failure=false(nt,nr,ns);
capture=failure; feasible=failure; input_snr=nan(nt,nr,ns); seconds=0; max_angle_delta=0;
rows=cell(m.total_cases,14); row=0;
for ti=1:nt
    trial=m.trials(ti);
    for ri=1:nr
        for si=1:ns
            name=sprintf('mc_%04d_rcs_%02d_snr_%02d.mat',trial,ri,si);
            item=load(fullfile(output,'samples',name)); r=item.result;
            assert(strcmp(item.manifest_id,m.id) && r.trial==trial ...
                && r.rcs_index==ri && r.snr_index==si);
            assert(r.seed==cfg.seed+10000*trial && r.rcs_m2==cfg.rcs_m2(ri));
            assert(r.requested_snr_db==cfg.snr_db(si) ...
                && abs(r.reference_snr_db-r.requested_snr_db)<1e-9);
            checked=evaluate_estimation(r.estimate,r.p);
            direction=unit_direction(checked.estimate(:,3:4));
            truth=unit_direction(r.p.truth(:,3:4));
            err=acosd(max(-1,min(1,sum(direction.*truth,2))));
            delta=max(abs(err-r.angular_error_deg)); max_angle_delta=max(max_angle_delta,delta);
            assert(delta<1e-8 && all(isfinite(err)) && all(err>=0));
            assert(r.ris_fine_used==(r.coarse_locked && r.coarse_design_feasible && r.ris_feasible));
            if r.ris_fine_used
                for seg=1:2
                    d=r.designs{seg}; assert(norm(d.W,'fro')^2<=1+1e-6);
                    phase=angle(d.phase)*2^r.p.ris_bits/(2*pi);
                    assert(max(abs(phase-round(phase)))<1e-9);
                    assert(all(d.sinr>=10^(r.p.comm_sinr_db(1)/10)-1e-8));
                end
            end
            used(ti,ri,si)=r.ris_fine_used; angle(ti,ri,si,:)=reshape(err,1,1,1,2);
            failure(ti,ri,si)=r.failure; capture(ti,ri,si)=r.coarse_locked;
            feasible(ti,ri,si)=r.ris_feasible; input_snr(ti,ri,si)=r.input_snr_db;
            seconds=seconds+r.seconds; row=row+1;
            rows(row,:)={trial,r.rcs_m2,r.requested_snr_db,r.input_snr_db, ...
                err(1),err(2),sqrt(mean(err.^2)),r.ris_fine_used, ...
                r.coarse_locked,r.coarse_design_feasible,r.ris_feasible, ...
                r.position_error_m(1),r.position_error_m(2),r.failure};
        end
    end
end
metrics=cell2table(rows,'VariableNames',{'trial','rcs_m2','reference_snr_db', ...
    'measured_direct_input_snr_db','target1_angle_error_deg','target2_angle_error_deg', ...
    'case_angle_rmse_deg','ris_fine_used','coarse_locked','coarse_design_feasible', ...
    'ris_fine_feasible','target1_position_error_m','target2_position_error_m','strict_failure'});
writetable(metrics,fullfile(output,'case_metrics.csv'));

bootstrap_seed=20261119; repeats=4000; rng(bootstrap_seed,'twister');
draw=randi(nt,nt,repeats); curves=cell(nr*ns,9); ix=0;
angle_rmse=nan(nr,ns); lower=nan(nr,ns); upper=nan(nr,ns);
coverage=zeros(nr,ns); failure_rate=zeros(nr,ns); capture_rate=zeros(nr,ns);
feasible_rate=zeros(nr,ns); mean_input_snr=nan(nr,ns); n_used=zeros(nr,ns);
for ri=1:nr
    for si=1:ns
        ix=ix+1; selected=used(:,ri,si); n_used(ri,si)=sum(selected);
        coverage(ri,si)=mean(selected); failure_rate(ri,si)=mean(failure(:,ri,si));
        capture_rate(ri,si)=mean(capture(:,ri,si)); feasible_rate(ri,si)=mean(feasible(:,ri,si));
        mean_input_snr(ri,si)=mean(input_snr(:,ri,si),'omitnan');
        ci=[NaN NaN]; value=NaN;
        if any(selected)
            samples=squeeze(mean(angle(:,ri,si,:).^2,4)); samples(~selected)=NaN;
            value=sqrt(mean(samples,'omitnan'));
            boot=sqrt(mean(samples(draw),'omitnan')); boot=sort(boot(isfinite(boot)));
            if ~isempty(boot)
                ci=boot([max(1,ceil(.025*numel(boot))),min(numel(boot),ceil(.975*numel(boot)))]);
            end
        end
        angle_rmse(ri,si)=value; lower(ri,si)=ci(1); upper(ri,si)=ci(2);
        curves(ix,:)={cfg.rcs_m2(ri),cfg.snr_db(si),mean_input_snr(ri,si), ...
            n_used(ri,si),coverage(ri,si),value,ci(1),ci(2),failure_rate(ri,si)};
    end
end
curve_table=cell2table(curves,'VariableNames',{'rcs_m2','reference_snr_db', ...
    'mean_direct_input_snr_db','ris_fine_cases','ris_fine_coverage', ...
    'angle_rmse_deg','ci95_lower_deg','ci95_upper_deg','strict_failure_rate'});
writetable(curve_table,fullfile(output,'snr_summary.csv'));
summary=struct('manifest_id',m.id,'complete_cases',m.total_cases, ...
    'rcs_m2',cfg.rcs_m2,'reference_snr_db',cfg.snr_db, ...
    'angle_rmse_deg',angle_rmse,'ci95_lower_deg',lower,'ci95_upper_deg',upper, ...
    'ris_fine_cases',n_used,'ris_fine_coverage',coverage, ...
    'coarse_capture_rate',capture_rate,'ris_fine_feasible_rate',feasible_rate, ...
    'strict_failure_rate',failure_rate,'mean_direct_input_snr_db',mean_input_snr, ...
    'angle_metric',m.angle_metric,'snr_definition',m.snr_definition, ...
    'ris_scope',m.ris_scope,'bootstrap_seed',bootstrap_seed, ...
    'bootstrap_repeats',repeats,'total_compute_s',seconds);
uav_write_json(fullfile(output,'summary.json'),summary);
plot_curves(cfg,angle_rmse,lower,upper,coverage,output);
verification=struct('passed',true,'manifest_id',m.id,'cases',m.total_cases, ...
    'metric_rows',height(metrics),'curve_points',height(curve_table), ...
    'all_RIS_fine_samples_identified',true,'failed_samples_retained',true, ...
    'source_hashes_verified',true,'reference_snr_definition_verified',true, ...
    'max_angle_error_recompute_difference_deg',max_angle_delta);
uav_write_json(fullfile(output,'verification.json'),verification);
disp(summary);
end

function plot_curves(cfg,rmse,lower,upper,coverage,output)
fig=figure('Visible','off','Color','w','Units','inches','Position',[.5 .5 12 7]);
colors=[.12 .38 .58;.78 .36 .19;.12 .58 .49];
ax1=axes('Parent',fig,'Position',[.11 .52 .84 .36]); hold(ax1,'on');
for k=1:numel(cfg.rcs_m2)
    valid=isfinite(rmse(k,:));
    errorbar(ax1,cfg.snr_db(valid),rmse(k,valid), ...
        max(0,rmse(k,valid)-lower(k,valid)), ...
        max(0,upper(k,valid)-rmse(k,valid)), ...
        '-o','Color',colors(k,:),'MarkerFaceColor',colors(k,:), ...
        'LineWidth',1.8,'MarkerSize',6,'CapSize',4);
end
set(ax1,'YScale','log','FontName','SimHei','FontSize',10,'LineWidth',1);
grid(ax1,'on'); box(ax1,'on'); ylabel(ax1,'角度 RMSE (deg)','FontName','SimHei');
title(ax1,'RIS 精测成功样本的球面角误差 RMSE（95% 配对场景 bootstrap 区间）', ...
    'FontName','SimHei','FontSize',12);
legend(ax1,compose('RCS=%g m^2',cfg.rcs_m2),'Location','northeast', ...
    'FontName','SimHei','Box','off');
ax2=axes('Parent',fig,'Position',[.11 .13 .84 .25]); hold(ax2,'on');
for k=1:numel(cfg.rcs_m2)
    plot(ax2,cfg.snr_db,100*coverage(k,:),'-o','Color',colors(k,:), ...
        'MarkerFaceColor',colors(k,:),'LineWidth',1.8,'MarkerSize',5);
end
set(ax2,'FontName','SimHei','FontSize',10,'LineWidth',1,'YLim',[0 105],'YTick',0:20:100);
grid(ax2,'on'); box(ax2,'on');
xlabel(ax2,'参考 SNR (dB)，RCS=1 m^2、距离=200 m','FontName','SimHei');
ylabel(ax2,'进入 RIS 精测比例 (%)','FontName','SimHei');
note='所有曲线均启用 RIS 精测；粗测捕获仍使用直达链路。固定悬停高度 80 m；阵列、带宽与 CPI 不变。';
annotation(fig,'textbox',[.05 .015 .9 .06],'String',note,'EdgeColor','none', ...
    'FontName','SimHei','FontSize',9,'HorizontalAlignment','center');
exportgraphics(fig,fullfile(output,'comparison.png'),'Resolution',300,'BackgroundColor','white');
exportgraphics(fig,fullfile(output,'comparison.pdf'),'ContentType','vector','BackgroundColor','white');
close(fig);
end

function v=unit_direction(angles)
theta=angles(:,1); phi=angles(:,2);
v=[sind(theta).*cosd(phi),sind(theta).*sind(phi),cosd(theta)];
end

function h=filehash(path)
f=fopen(path,'rb'); assert(f>=0); bytes=fread(f,inf,'*uint8'); fclose(f);
h=uav_hash(bytes);
end
