function audit=uav_optimizer_audit(output)
% Post-run diagnosis only: no fitting, model selection or control changes.
code=fileparts(fileparts(fileparts(output))); addpath(code,fullfile(code,'uav')); maxNumCompThreads(2);
m=jsondecode(fileread(fullfile(output,'manifest.json')));
v=jsondecode(fileread(fullfile(output,'verification.json'))); assert(v.passed && v.cases==m.total_cases);
nmc=m.total_cases/3; assert(ismember(nmc,[1 300]));
if strcmp(m.profile,'full'), assert(strcmp(strtrim(fileread(fullfile(output,'state'))),'COMPLETE')); end
count=zeros(3,2); worse=count; condition=cell(3,2); rss_difference=condition;
chosen=[1 3 5 6 9 10 11 12 13 15]; sums=zeros(3,numel(chosen),4);
coarse=zeros(3,2,4); normalization_delta=zeros(3,1); frozen_feasible=zeros(3,1);
outside=zeros(3,2); locked_outside=outside;
xyz_sse=zeros(3,15); xyz_failed=xyz_sse; rematched=xyz_sse;
prior_sse=zeros(3,1); prior_over5=prior_sse; fallback_sse=xyz_sse; coarse_boundary=zeros(3,2);
for trial=0:nmc-1
    for ri=1:3
        pth=fullfile(output,'samples',sprintf('mc_%04d_rcs_%02d.mat',trial,ri));
        item=load(pth,'result','manifest_id'); r=item.result; assert(strcmp(item.manifest_id,m.id));
        assert(r.trial==trial && r.rcs_index==ri);
        prior_error=vecnorm(r.scene.prior-r.scene.targets,2,2);
        prior_sse(ri)=prior_sse(ri)+sum(prior_error.^2); prior_over5(ri)=prior_over5(ri)+any(prior_error>5);
        for c=1:2
            b=r.banks{c}; if isempty(b), continue; end
            full=b.fits{8}; dd=b.fits{1}; count(ri,c)=count(ri,c)+1;
            worse(ri,c)=worse(ri,c)+(full.rss_whitened>dd.rss_whitened+1e-6*max(1,dd.rss_whitened));
            condition{ri,c}(end+1)=full.condition;
            rss_difference{ri,c}(end+1)=full.rss_whitened-dd.rss_whitened;
        end
        normalization_delta(ri)=max(normalization_delta(ri),max(abs(r.estimates(:,:,3)-r.estimates(:,:,4)),[],'all'));
        frozen_feasible(ri)=frozen_feasible(ri)+r.feasible(7);
        for k=1:numel(chosen)
            e=parameter_errors(r.estimates(:,:,chosen(k)),r.p);
            sums(ri,k,:)=reshape(reshape(sums(ri,k,:),1,4)+sum(e.^2,1),1,1,4);
        end
        for c=1:2
            if c==1, z=r.initial; else, z=r.rx_initial; end
            e=parameter_errors(z,r.p);
            coarse(ri,c,:)=reshape(reshape(coarse(ri,c,:),1,4)+sum(e.^2,1),1,1,4);
            bounds=repmat([max(.6,2*r.p.resolution),max(10,r.p.lambda/(r.p.K*r.p.Ts)),15,30],2,1);
            inside=false;
            for order=[1 2;2 1].'
                delta=r.p.truth(order,:)-z; delta(:,4)=mod(delta(:,4)+180,360)-180;
                inside=inside || all(abs(delta)<=bounds,'all');
            end
            outside(ri,c)=outside(ri,c)+~inside;
            locked_outside(ri,c)=locked_outside(ri,c)+(~inside && r.locked(1+(c-1)*11));
            coarse_boundary(ri,c)=coarse_boundary(ri,c)+any(z(:,3)>=89.99);
        end
        for k=1:15
            z=r.estimates(:,:,k);
            local=z(:,1).*[sind(z(:,3)).*cosd(z(:,4)),sind(z(:,3)).*sind(z(:,4)),cosd(z(:,3))];
            hover=r.hover; if k==2, hover=r.reference_hover(2,:); end
            world=(r.p.world_to_local'*local.').'+hover;
            original=vecnorm(world-r.scene.targets,2,2);
            alternative=vecnorm(world([2 1],:)-r.scene.targets,2,2);
            swap=sum(alternative.^2)<sum(original.^2)-1e-8;
            if swap, original=alternative; end
            rematched(ri,k)=rematched(ri,k)+swap;
            xyz_sse(ri,k)=xyz_sse(ri,k)+sum(original.^2);
            xyz_failed(ri,k)=xyz_failed(ri,k)+(~r.locked(k) || ~r.feasible(k) || any(original>5));
            fallback_error=r.position_errors(:,k);
            if ~r.locked(k), fallback_error=prior_error; end
            fallback_sse(ri,k)=fallback_sse(ri,k)+sum(fallback_error.^2);
        end
    end
end
median_condition=nan(3,2); median_rss_delta=median_condition;
for ri=1:3
    for c=1:2
        if count(ri,c)>0
            median_condition(ri,c)=median(condition{ri,c}); median_rss_delta(ri,c)=median(rss_difference{ri,c});
        end
    end
end
f=fopen([mfilename('fullpath'),'.m'],'rb'); assert(f>=0); bytes=fread(f,inf,'*uint8'); fclose(f);
audit=struct('passed',true,'manifest_id',m.id,'cases',m.total_cases,'profile',m.profile,'source_sha256',uav_hash(bytes), ...
    'rcs_m2',[1 10 100],'conditions',{{'Original_acquisition','RxBeam_acquisition'}}, ...
    'eligible_model_banks',count,'full_RSS_above_found_DD_RSS_count',worse, ...
    'median_full_normalized_dictionary_condition',median_condition, ...
    'median_full_minus_DD_whitened_RSS',median_rss_delta, ...
    'maximum_legacy_vs_normalized_parameter_difference',normalization_delta, ...
    'frozen_W_communication_feasible_count',frozen_feasible, ...
    'parameter_order',{{'range_m','radial_velocity_mps','polar_angle_deg','azimuth_deg'}}, ...
    'parameter_method_ids',chosen,'parameter_RMSE',sqrt(sums./(2*nmc)), ...
    'coarse_parameter_RMSE',sqrt(coarse./(2*nmc)), ...
    'coarse_truth_outside_original_local_box_count',outside, ...
    'locked_coarse_truth_outside_original_local_box_count',locked_outside, ...
    'coarse_polar_boundary_case_count',coarse_boundary, ...
    'posthoc_Cartesian_matching_position_RMSE_m',sqrt(xyz_sse./(2*nmc)), ...
    'posthoc_Cartesian_matching_failure_rate',xyz_failed./nmc, ...
    'posthoc_Cartesian_rematched_case_count',rematched, ...
    'prior_only_position_RMSE_m',sqrt(prior_sse./(2*nmc)), ...
    'prior_only_any_target_over5m_rate',prior_over5./nmc, ...
    'posthoc_prior_fallback_position_RMSE_m',sqrt(fallback_sse./(2*nmc)), ...
    'prior_fallback_rule','When the original capture flag is false, return the supplied location prior; capture and strict pipeline failure flags are unchanged', ...
    'interpretation','Full contains DD as a feasible submodel; larger final RSS diagnoses optimization shortfall, not statistical evidence for a new estimator');
uav_write_json(fullfile(output,'optimizer_audit.json'),audit); disp(audit);
end

function e=parameter_errors(z,p)
matched=evaluate_estimation(z,p); e=matched.estimate-p.truth;
e(:,4)=mod(e(:,4)+180,360)-180;
end
