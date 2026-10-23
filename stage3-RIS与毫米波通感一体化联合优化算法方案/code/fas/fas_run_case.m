function result=fas_run_case(options,trial,si,notify)
% One paired MC case. Callback writes live phase/progress without fabricating completion.
if nargin<4, notify=@(s) fprintf('%s\n',s); end
t=tic; snr=options.snr_db(si); p=fas_parameters(options,trial,snr);
seed=options.seed+trial*10000+si*100;
rng(seed+1,'twister'); [data,noise_power]=simulate_radar_channel_3d(p);
[initial,coarse]=joint_estimator_fast(data,p); clear data;
notify(sprintf('coarse complete; locked=%d',coarse.locked));
[names,bases,guards]=fas_methods(options);
result=struct('trial',trial,'snr_index',si,'snr_db',snr,'seed',seed, ...
    'p',p,'coarse',initial,'locked',coarse.locked,'noise_power',noise_power, ...
    'methods',{names},'estimates',zeros(p.Q,4,numel(names)), ...
    'errors',zeros(p.Q,4,numel(names)),'position_errors',zeros(p.Q,numel(names)), ...
    'feasible',false(1,numel(names)),'failure',false(1,numel(names)), ...
    'design',{cell(1,4)},'design_info',{cell(1,4)},'fine_info',{cell(1,numel(names))}, ...
    'guard_symbols',guards,'sample_counts',zeros(1,numel(names)), ...
    'communication_min_sinr',zeros(p.K_stream,numel(names)), ...
    'processing_seconds',zeros(1,numel(names)));
for b=1:4
    pb=p; pb.ris_enabled=mod(b,2)==0; movable=b>2; tb=tic;
    feasible=false; design={}; dinfo=struct('seconds',0,'feasible',false);
    if coarse.locked
        [pb,design,dinfo]=fas_optimize_array(initial,pb,options,movable);
        feasible=dinfo.feasible;
        notify(sprintf('%s design complete; feasible=%d',names{b},feasible));
    end
    design_seconds=toc(tb); result.design{b}=design; result.design_info{b}=dinfo;
    for index=find(bases==b)
        tm=tic; estimate=initial; finfo=struct('skipped',true); guard=guards(index);
        if coarse.locked && feasible
            [obs,noise]=fas_fine_observations(initial,pb,guard,seed+20);
            projected=cell(2,1);
            for s=1:2
                projected{s}=fas_echo(pb,obs{s},design{s},noise_power,noise{s});
            end
            [estimate,finfo]=refine_ris_parameters(vertcat(projected{:}),obs,design,initial,pb);
            result.sample_counts(index)=sum(cellfun(@(o) size(o.symbol,2),obs));
            result.communication_min_sinr(:,index)=dinfo.min_sinr;
        end
        compare=evaluate_estimation(estimate,p);
        g=channel_geometry(compare.estimate,p); truthg=channel_geometry(p.truth,p);
        result.estimates(:,:,index)=compare.estimate; result.errors(:,:,index)=compare.error;
        result.position_errors(:,index)=vecnorm(g.position-truthg.position,2,1).';
        result.feasible(index)=feasible;
        result.failure(index)=~coarse.locked || ~feasible || ...
            any(result.position_errors(:,index)>options.failure_position_m);
        result.fine_info{index}=finfo;
        result.processing_seconds(index)=coarse.runtime+design_seconds+toc(tm);
        notify(sprintf('%s complete; position RMSE=%.6g m',names{index},compare.position_rmse));
    end
end
result.elapsed_seconds=toc(t);
result.acquisition_seconds=2*p.K*p.Ts;
% A normalized energy ceiling, not a calibrated electrical switching cost.
result.transmit_symbol_budget=2*p.K-guards;
result.fine_transmit_fraction=(p.K-guards)/p.K;
assert(all(isfinite(result.estimates),'all') && all(isfinite(result.position_errors),'all'));
end
