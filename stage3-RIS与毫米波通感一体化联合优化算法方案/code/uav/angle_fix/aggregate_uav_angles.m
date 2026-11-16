function summary=aggregate_uav_angles(output)
root=fileparts(mfilename('fullpath')); uav=fileparts(root); code=fileparts(uav);
addpath(root,uav,code); maxNumCompThreads(2); m=jsondecode(fileread(fullfile(output,'manifest.json')));
assert(strcmp(filehash(fullfile(m.parent,'manifest.json')),m.parent_manifest_sha256));
for k=1:numel(m.source), assert(strcmp(filehash(fullfile(code,m.source(k).file)),m.source(k).sha256)); end
assert(numel(dir(fullfile(output,'samples','mc_*_rcs_*.mat')))==m.total_cases);
nmc=m.total_cases/3; mse=zeros(nmc,3,4); fail=false(nmc,3,4); locked=fail; feasible=fail; outside=fail; boundary=fail;
coarse_sse=zeros(nmc,3,4,4); fine_sse=coarse_sse; coarse_mse=mse; rows=cell(m.total_cases*4,19); row=0;
max_replay=0; max_fine_replay=0; max_error_delta=0; max_power=0; min_sinr=Inf; seconds=0;
for trial=0:nmc-1
    for ri=1:3
        name=sprintf('mc_%04d_rcs_%02d.mat',trial,ri); item=load(fullfile(output,'samples',name)); r=item.result;
        assert(strcmp(item.manifest_id,m.id) && r.trial==trial && r.rcs_index==ri && isequal(r.methods,m.methods.'));
        assert(r.has_reference && r.seed==m.config.seed+10000*trial && r.rcs_m2==m.config.rcs_m2(ri));
        assert(strcmp(filehash(fullfile(m.parent,'samples',name)),r.parent_sha256));
        p=r.p; assert(p.N==12672 && p.K==256 && p.Mx*p.My==64 && p.Ntx*p.Nty==16);
        assert(p.coarse_n==384 && p.coarse_l==64 && p.fine_n==256 && p.fine_l==64);
        assert(p.ris_side^2==256 && p.ris_bits==2 && p.noise_w==m.waveform.noise_w);
        assert(abs(norm(r.rx_weights)-1)<1e-12 && all(r.locked==r.locked(1)));
        assert(max(abs(r.initial_unmatched(:,1:2,:)-r.initial_unmatched(:,1:2,1)),[],'all')==0);
        max_replay=max(max_replay,r.coarse_replay_delta); max_fine_replay=max(max_fine_replay,r.fine_replay_delta_m);
        assert(r.coarse_replay_delta<1e-7 && r.fine_replay_delta_m<1e-5);
        for k=1:4
            b=evaluate_estimation(r.estimates(:,:,k),p); a=evaluate_estimation(r.coarse(:,:,k),p);
            g=channel_geometry(b.estimate,p); gt=channel_geometry(p.truth,p);
            e=vecnorm(g.position-gt.position,2,1).'; delta=max(abs(e-r.position_errors(:,k)));
            max_error_delta=max(max_error_delta,delta); assert(delta<1e-8 && all(isfinite(e)));
            assert(r.failure(k)==(~r.locked(k) || ~r.feasible(k) || any(e>5)));
            mse(trial+1,ri,k)=mean(e.^2); coarse_mse(trial+1,ri,k)=mean(r.coarse_position_errors(:,k).^2);
            coarse_sse(trial+1,ri,k,:)=reshape(mean(a.error.^2,1),1,1,1,4);
            fine_sse(trial+1,ri,k,:)=reshape(mean(b.error.^2,1),1,1,1,4);
            fail(trial+1,ri,k)=r.failure(k); locked(trial+1,ri,k)=r.locked(k); feasible(trial+1,ri,k)=r.feasible(k);
            outside(trial+1,ri,k)=r.outside_local_box(k); boundary(trial+1,ri,k)=r.polar_boundary(k);
            row=row+1; rows(row,:)={trial,r.rcs_m2,r.methods{k},e(1),e(2),sqrt(mean(e.^2)), ...
                r.locked(k),r.feasible(k),r.failure(k),r.seed, ...
                sqrt(mean(a.error(:,1).^2)),sqrt(mean(a.error(:,2).^2)), ...
                sqrt(mean(a.error(:,3).^2)),sqrt(mean(a.error(:,4).^2)), ...
                r.outside_local_box(k),r.polar_boundary(k),r.coarse_replay_delta, ...
                r.fine_replay_delta_m,r.info.input_snr_db};
            d=r.design{k};
            for s=1:numel(d)
                power=norm(d{s}.W,'fro')^2; max_power=max(max_power,power); assert(power<=1+1e-6);
                if d{s}.feasible
                    min_sinr=min(min_sinr,min(10*log10(d{s}.sinr))); assert(all(d{s}.sinr>=10));
                end
            end
        end
        seconds=seconds+r.seconds;
    end
end
metrics=cell2table(rows,'VariableNames',{'trial','rcs_m2','method','target1_error_m','target2_error_m', ...
    'position_rmse_m','locked','feasible','failure','seed','coarse_range_rmse_m','coarse_velocity_rmse_mps', ...
    'coarse_polar_rmse_deg','coarse_azimuth_rmse_deg','outside_local_box','polar_boundary', ...
    'legacy_coarse_replay_delta','legacy_fine_replay_delta_m','input_snr_db'});
writetable(metrics,fullfile(output,'case_metrics.csv'));
summary=struct('manifest_id',m.id,'complete_cases',m.total_cases,'methods',{m.methods},'rcs_m2',m.config.rcs_m2, ...
    'position_rmse_m',reshape(sqrt(mean(mse,1)),3,4),'failure_rate',reshape(mean(fail,1),3,4), ...
    'capture_rate',reshape(mean(locked,1),3,4),'feasible_rate',reshape(mean(feasible,1),3,4), ...
    'coarse_position_rmse_m',reshape(sqrt(mean(coarse_mse,1)),3,4), ...
    'parameter_order',{{'range_m','radial_velocity_mps','polar_angle_deg','azimuth_deg'}}, ...
    'coarse_parameter_RMSE',reshape(sqrt(mean(coarse_sse,1)),3,4,4), ...
    'fine_parameter_RMSE',reshape(sqrt(mean(fine_sse,1)),3,4,4), ...
    'outside_local_box_rate',reshape(mean(outside,1),3,4),'polar_boundary_rate',reshape(mean(boundary,1),3,4), ...
    'total_compute_s',seconds);
rng(m.bootstrap_seed,'twister'); ids=randi(nmc,nmc,m.bootstrap_repeats); comparisons=cell(3,3);
for ri=1:3
    for k=2:4
        a=mse(:,ri,1); b=mse(:,ri,k); reduction=sort(100*(1-sqrt(mean(b(ids),1)./mean(a(ids),1))));
        delta=double(fail(:,ri,1))-double(fail(:,ri,k)); fb=sort(100*mean(delta(ids),1));
        comparisons{ri,k-1}=struct('rcs_m2',m.config.rcs_m2(ri),'method',m.methods{k}, ...
            'rmse_reduction_percent',100*(1-sqrt(mean(b)/mean(a))),'rmse_ci95_percent',reduction([100 3900]), ...
            'failure_reduction_pp',100*mean(delta),'failure_ci95_pp',fb([100 3900]));
    end
end
summary.comparisons=vertcat(comparisons{:}); summary.primary=comparisons{2,3};
uav_write_json(fullfile(output,'summary.json'),summary);
fig=figure('Visible','off','Position',[50 50 1300 450]);
subplot(1,2,1); bar(100*summary.failure_rate(2,:)); ylabel('Strict failure (%)'); title('RCS=10, all 300 cases');
xticks(1:4); xticklabels(m.methods); xtickangle(20); grid on;
subplot(1,2,2); bar(squeeze(summary.coarse_parameter_RMSE(2,:,3:4))); ylabel('Coarse angle RMSE (deg)');
xticks(1:4); xticklabels(m.methods); xtickangle(20); legend('Polar','Azimuth'); grid on;
saveas(fig,fullfile(output,'comparison.png')); close(fig);
verification=struct('passed',true,'manifest_id',m.id,'cases',m.total_cases,'metric_rows',height(metrics), ...
    'all_failures_retained',true,'same_RD_and_noise',true,'source_and_input_hashes_verified',true, ...
    'maximum_error_recompute_difference_m',max_error_delta,'maximum_legacy_coarse_replay_delta',max_replay, ...
    'maximum_legacy_fine_replay_delta_m',max_fine_replay,'maximum_power_fraction',max_power, ...
    'minimum_feasible_sinr_db',min_sinr);
uav_write_json(fullfile(output,'verification.json'),verification); disp(summary); disp(summary.primary);
end

function h=filehash(path)
f=fopen(path,'rb'); assert(f>=0); bytes=fread(f,inf,'*uint8'); fclose(f); h=uav_hash(bytes);
end
