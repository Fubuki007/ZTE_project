function summary=aggregate_uav_diagnosis(output)
root=fileparts(mfilename('fullpath')); uav=fileparts(root); code=fileparts(uav);
addpath(root,uav,code,fullfile(code,'path_reliability')); maxNumCompThreads(2);
m=jsondecode(fileread(fullfile(output,'manifest.json'))); nr=3; nm=15; nmc=m.total_cases/3;
assert(strcmp(filehash(fullfile(m.parent,'manifest.json')),m.parent_manifest_sha256));
for k=1:numel(m.source), assert(strcmp(filehash(fullfile(code,m.source(k).file)),m.source(k).sha256)); end
assert(numel(dir(fullfile(output,'samples','mc_*_rcs_*.mat')))==m.total_cases);
mse=zeros(nmc,nr,nm); fail=false(nmc,nr,nm); locked=fail; feasible=fail;
path_snr=nan(nmc,nr,2,4,2); ratio=nan(nmc,nr,2); snr_gain=zeros(nmc,nr);
mask_counts=zeros(nr,8,2); rows=cell(m.total_cases*nm,15); row=0; seconds=0;
max_delta=0; max_replay=0; max_synthesis=0; max_power=0; min_sinr=Inf;
for trial=0:nmc-1
    for ri=1:nr
        name=sprintf('mc_%04d_rcs_%02d.mat',trial,ri);
        item=load(fullfile(output,'samples',name)); r=item.result;
        assert(strcmp(item.manifest_id,m.id) && r.trial==trial && r.rcs_index==ri);
        assert(r.seed==m.config.seed+10000*trial && r.rcs_m2==m.config.rcs_m2(ri));
        parent=fullfile(m.parent,'samples',name); assert(strcmp(filehash(parent),r.parent_sha256));
        old=load(parent,'result'); old=old.result; p=r.p;
        assert(p.N==12672 && p.K==256 && p.Ntx*p.Nty==16 && p.Mx*p.My==64);
        assert(p.ris_side^2==256 && p.ris_bits==2 && p.noise_w==m.waveform.noise_w);
        assert(p.coarse_n==384 && p.coarse_l==64 && p.fine_n==256 && p.fine_l==64);
        assert(r.noise_power==p.noise_power && abs(norm(r.rx_weights)-1)<1e-12);
        assert(max(abs(r.position_errors(:,1:2)-old.position_errors(:,3:4)),[],'all')<1e-8);
        for k=1:nm
            ep=p; if k==2, ep=old.parameters{4}; end
            a=channel_geometry(r.estimates(:,:,k),ep); b=channel_geometry(ep.truth,ep);
            e=vecnorm(a.position-b.position,2,1).'; delta=max(abs(e-r.position_errors(:,k)));
            max_delta=max(max_delta,delta); assert(delta<1e-8 && all(isfinite(e)));
            assert(r.failure(k)==(~r.locked(k) || ~r.feasible(k) || any(e>5)));
            mse(trial+1,ri,k)=mean(e.^2); fail(trial+1,ri,k)=r.failure(k);
            locked(trial+1,ri,k)=r.locked(k); feasible(trial+1,ri,k)=r.feasible(k);
            row=row+1; rows(row,:)={trial,r.rcs_m2,r.methods{k},e(1),e(2),sqrt(mean(e.^2)), ...
                r.locked(k),r.feasible(k),r.failure(k),r.diagnostic_only(k),r.seed, ...
                r.hover(1),r.hover(2),r.hover(3),r.rx_info.input_snr_db-old.input_snr_db(3)};
        end
        for c=1:2
            bank=r.banks{c}; if isempty(bank), continue; end
            [~,choice]=min(cellfun(@(f) f.bic,bank.fits)); assert(choice==bank.choice);
            mask_counts(ri,choice,c)=mask_counts(ri,choice,c)+1;
            for k=1:8
                f=bank.fits{k}; assert(all(diff(f.cost_history)<=1e-6*max(1,f.cost_history(1))));
                assert(isequal(logical(bank.masks(k,:)),f.mask));
            end
        end
        operational={};
        if ~isempty(r.design{1}), operational=[r.design(1:2)]; end
        if ~isempty(r.design{4}), operational=[operational,{r.design{4}.no_ris,r.design{4}.ris}]; end
        for k=1:numel(operational)
            d=operational{k};
            for s=1:2
                power=norm(d{s}.W,'fro')^2; max_power=max(max_power,power); assert(power<=1+1e-6);
                ph=angle(d{s}.phase)*4/(2*pi); assert(max(abs(ph-round(ph)))<1e-10);
                if d{s}.feasible
                    min_sinr=min(min_sinr,min(10*log10(d{s}.sinr)));
                    assert(all(d{s}.sinr>=10));
                end
            end
        end
        path_snr(trial+1,ri,:,:,:)=reshape(r.path_snr_db,1,1,2,4,2);
        ratio(trial+1,ri,:)=r.reflected_to_DD_db;
        snr_gain(trial+1,ri)=r.rx_info.input_snr_db-old.input_snr_db(3);
        max_replay=max(max_replay,r.replay_error_m); max_synthesis=max(max_synthesis,r.synthesis_relative_error);
        seconds=seconds+r.seconds; methods=r.methods;
    end
end
metrics=cell2table(rows,'VariableNames',{'trial','rcs_m2','method','target1_error_m','target2_error_m', ...
    'position_rmse_m','locked','feasible','failure','diagnostic_only','seed', ...
    'anchor_x','anchor_y','anchor_z','rx_snr_gain_db'});
writetable(metrics,fullfile(output,'case_metrics.csv'));
summary=struct('manifest_id',m.id,'complete_cases',m.total_cases,'methods',{methods},'rcs_m2',m.config.rcs_m2, ...
    'position_rmse_m',reshape(sqrt(mean(mse,1)),nr,nm),'failure_rate',reshape(mean(fail,1),nr,nm), ...
    'capture_rate',reshape(mean(locked,1),nr,nm),'feasible_rate',reshape(mean(feasible,1),nr,nm), ...
    'bic_mask_counts',mask_counts,'bic_masks',bank_masks(),'path_conditions',{{'Original_acquisition','RxBeam_acquisition'}}, ...
    'path_order',{{'DD','RD','DR','RR'}},'median_rx_snr_gain_db',median(snr_gain,1), ...
    'median_path_snr_db',reshape(median(reshape(permute(path_snr,[1 3 2 4 5]),nmc*2,nr,4,2),1,'omitnan'),nr,4,2), ...
    'median_reflected_to_DD_db',reshape(median(ratio,1,'omitnan'),nr,2),'total_compute_s',seconds);
pairs=[2 3;3 4;3 5;3 6;1 7;1 8;3 10;1 9;10 11;1 12;12 13;13 15;12 15;12 14];
names={'position_control','normalization','DD_fit','BIC_fit','frozenW_full','frozenW_DD', ...
    'RIS_remove_noise','NoRIS_remove_noise','noiseless_DD','receive_beam','RIS_after_receive_beam', ...
    'BIC_after_receive_beam','net_RIS_BIC','net_RIS_DD'};
rng(m.bootstrap_seed,'twister'); ids=randi(nmc,nmc,4000); comparisons=struct([]); ix=0;
for ri=1:3
    for k=1:size(pairs,1)
        ix=ix+1; a=mse(:,ri,pairs(k,1)); b=mse(:,ri,pairs(k,2));
        improvement=sort(100*(1-sqrt(mean(b(ids),1))./sqrt(mean(a(ids),1))));
        delta=double(fail(:,ri,pairs(k,1)))-double(fail(:,ri,pairs(k,2)));
        failure_boot=sort(100*mean(delta(ids),1));
        comparisons(ix)=struct('name',names{k},'rcs_m2',m.config.rcs_m2(ri), ...
            'rmse_reduction_percent',100*(1-sqrt(mean(b)/mean(a))), ...
            'rmse_ci95_percent',improvement([100 3900]),'failure_reduction_pp',100*mean(delta), ...
            'failure_ci95_pp',failure_boot([100 3900]));
        if ri==2 && k==10
            primary(1)=struct('name','receive_beam_failure_RCS10','estimate',100*mean(delta), ...
                'units','percentage points','ci975',failure_boot([50 3950]));
        elseif ri==3 && k==4
            primary(2)=struct('name','BIC_RMSE_RCS100','estimate',100*(1-sqrt(mean(b)/mean(a))), ...
                'units','percent RMSE reduction','ci975',improvement([50 3950]));
        end
    end
end
summary.comparisons=comparisons; summary.primary=primary;
uav_write_json(fullfile(output,'summary.json'),summary);
fig=figure('Visible','off','Position',[50 50 1450 480]); shown=[1 2 3 5 6 12 13 14 15];
labels={'Old/noRIS','Old/RIS','Matched/full','Matched/DD','Matched/BIC','RX/noRIS','RX/RIS full','RX/RIS DD','RX/RIS BIC'};
subplot(1,2,1); bar(100*summary.failure_rate(2,shown)); ylabel('Failure rate (%)'); title('RCS=10, all geometries');
xticks(1:numel(shown)); xticklabels(labels); xtickangle(35); grid on;
subplot(1,2,2); bar(summary.position_rmse_m(3,shown)); ylabel('3D position RMSE (m)'); title('RCS=100, failures retained');
xticks(1:numel(shown)); xticklabels(labels); xtickangle(35); grid on;
saveas(fig,fullfile(output,'comparison.png')); close(fig);
v=struct('passed',true,'manifest_id',m.id,'cases',m.total_cases,'metric_rows',height(metrics), ...
    'maximum_error_recompute_difference_m',max_delta,'maximum_legacy_replay_difference_m',max_replay, ...
    'maximum_synthesis_relative_error',max_synthesis,'maximum_power_fraction',max_power, ...
    'minimum_feasible_sinr_db',min_sinr,'all_failures_retained',true,'source_and_input_hashes_verified',true);
uav_write_json(fullfile(output,'verification.json'),v); disp(summary.position_rmse_m); disp(primary);
end

function masks=bank_masks()
masks=[ones(8,1),bitget(repmat((0:7).',1,3),repmat(1:3,8,1))];
end

function h=filehash(path)
f=fopen(path,'rb'); assert(f>=0); bytes=fread(f,inf,'*uint8'); fclose(f); h=uav_hash(bytes);
end
