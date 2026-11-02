function audit_matlab_fas(code,output,mode,run)
% Read-only audit of the original simulator; outputs go outside its run folder.
previous=pwd; restore=onCleanup(@() cd(previous)); cd(code);
addpath(code,fullfile(code,'fas')); maxNumCompThreads(2);
assert(strcmp(which('channel_geometry'),fullfile(code,'channel_geometry.m')));
assert(strcmp(which('build_default_params'),fullfile(code,'build_default_params.m')));
if ~exist(output,'dir'), mkdir(output); end
if strcmp(mode,'smoke')
    opt=fas_options('smoke'); p=fas_parameters(opt,0,10);
    p.ris_enabled=true; initial=p.truth;
    [pf,df,inf]=fas_optimize_array(initial,p,opt,false);
    [pm,dm,inm]=fas_optimize_array(initial,p,opt,true);
    assert(inf.feasible && inm.feasible);
    row=diagnose(p,initial,pf,df,pm,dm,123,1,0);
    assert(row.echo_change_with_frozen_design>1e-6,'Moving Tx did not change echoes.');
    assert(row.wrong_geometry_residual>row.correct_geometry_residual+1e-10);
    fas_write_json(fullfile(output,'smoke.json'),row);
    fprintf('AUDIT SMOKE PASSED; fixed-design echo change %.6g\n',row.echo_change_with_frozen_design);
    return;
end
assert(strcmp(mode,'checkpoints') && ~ispc,'Full checkpoint audit is server-only.');
manifest=jsondecode(fileread(fullfile(run,'manifest.json'))); opt=manifest.options;
identity=fas_source_identity();
assert(strcmp(identity.sha256,manifest.source.sha256),'Audit must use original run source.');
rows=struct([]); position2=zeros(manifest.total_cases,numel(manifest.methods));
snrs=zeros(manifest.total_cases,1); count=0; diagnostic=struct([]);
for trial=0:opt.mc-1
    for si=1:numel(opt.snr_db)
        f=fullfile(run,'samples',sprintf('snr_%02d_mc_%04d.mat',si,trial));
        a=load(f,'result','manifest_id'); r=a.result;
        assert(strcmp(a.manifest_id,manifest.id) && r.trial==trial && r.snr_index==si);
        assert(isequal(r.methods(:),cellstr(manifest.methods(:))));
        count=count+1; position2(count,:)=mean(r.position_errors.^2,1); snrs(count)=r.snr_db;
        [x,y]=ndgrid(0:r.p.Ntx-1,0:r.p.Nty-1);
        fixed=r.p.d*[x(:),y(:),zeros(numel(x),1)];
        for b=1:4
            row=struct('trial',trial,'snr_db',r.snr_db,'method',string(r.methods{b}), ...
                'locked',r.locked,'feasible',r.feasible(b),'moves',0, ...
                'max_displacement_lambda',0,'moved_elements',0,'evaluations',0, ...
                'initial_score',NaN,'final_score',NaN,'score_vs_fixed_percent',NaN, ...
                'min_history_change',NaN,'target_steering_change',NaN, ...
                'ris_feed_change',NaN,'min_target_correlation',NaN, ...
                'min_pair_angle_separation_deg',NaN,'guard0_samples',0,'guard4_samples',0);
            if r.locked
                d=r.design_info{b}; pb=r.p; pb.tx_positions=d.positions; pb.ris_enabled=mod(b,2)==0;
                assert(fas_positions_valid(d.positions,pb,opt));
                [score,feasible]=fas_design_score(r.coarse,pb,r.design{b});
                assert(feasible==d.feasible && feasible==r.feasible(b));
                assert(abs(score-d.objective(end))<1e-10);
                delta=vecnorm(d.positions-fixed,2,2)/pb.lambda;
                row.moves=d.accepted_moves; row.max_displacement_lambda=max(delta);
                row.moved_elements=sum(delta>1e-9); row.evaluations=d.candidate_evaluations;
                row.initial_score=d.objective(1); row.final_score=score;
                row.min_history_change=min(diff(d.objective));
                g=channel_geometry(r.coarse,pb); p0=pb; p0.tx_positions=fixed;
                g0=channel_geometry(r.coarse,p0);
                row.target_steering_change=norm(g.transmit-g0.transmit,'fro')/norm(g0.transmit,'fro');
                row.ris_feed_change=norm(g.to_ris-g0.to_ris)/norm(g0.to_ris);
                row.min_target_correlation=min(abs(sum(conj(g0.transmit).*g.transmit,1))/size(fixed,1));
                dots=g.u'*g.u; dots(1:size(dots,1)+1:end)=-1;
                row.min_pair_angle_separation_deg=acosd(min(1,max(dots,[],'all')));
                if b>2
                    row.score_vs_fixed_percent=100*(score/r.design_info{b-2}.objective(end)-1);
                    ix=find(contains(r.methods,r.methods{b}) & r.guard_symbols==0);
                    row.guard0_samples=r.sample_counts(ix); row.guard4_samples=r.sample_counts(b);
                else
                    assert(max(delta)<1e-12);
                end
            end
            if isempty(rows), rows=row; else, rows(end+1)=row; end
        end
        % Predetermined first three geometries at 10 dB; no selection by gains.
        if trial<3 && r.snr_db==10 && r.locked && all(r.feasible(1:4))
            pf=r.p; pf.ris_enabled=true; pf.tx_positions=r.design_info{2}.positions;
            pm=pf; pm.tx_positions=r.design_info{4}.positions;
            dr=diagnose(r.p,r.coarse,pf,r.design{2},pm,r.design{4},r.seed+20,r.noise_power,trial);
            [obs,noise]=fas_fine_observations(r.coarse,pm,4,r.seed+20); yy=cell(2,1);
            for s=1:2, yy{s}=fas_echo(pm,obs{s},r.design{4}{s},r.noise_power,noise{s}); end
            [estimate,~]=refine_ris_parameters(vertcat(yy{:}),obs,r.design{4},r.coarse,pm);
            compare=evaluate_estimation(estimate,pm);
            dr.replay_estimate_difference=norm(compare.estimate-r.estimates(:,:,4),'fro');
            assert(dr.replay_estimate_difference<1e-7,'Saved result disagrees with original replay.');
            if isempty(diagnostic), diagnostic=dr; else, diagnostic(end+1)=dr; end
            fas_write_json(fullfile(output,'diagnostics.json'),diagnostic);
        end
    end
    if mod(trial+1,25)==0, fprintf('AUDITED %d/%d original checkpoints\n',count,manifest.total_cases); end
end
assert(count==manifest.total_cases && numel(diagnostic)==3);
writetable(struct2table(rows),fullfile(output,'checkpoint_audit.csv'));
metrics=readtable(fullfile(run,'metrics.csv')); maxdiff=0;
for k=1:height(metrics)
    m=find(strcmp(manifest.methods,metrics.method{k}));
    value=sqrt(mean(position2(snrs==metrics.snr_db(k),m)));
    maxdiff=max(maxdiff,abs(value-metrics.position_rmse_m(k)));
end
assert(maxdiff<1e-8,'Published RMSE does not match raw checkpoints.');
fas_write_json(fullfile(output,'completion.json'),struct('complete',true,'count',count, ...
    'run_manifest_id',manifest.id,'source_sha256',identity.sha256,'rmse_max_difference',maxdiff, ...
    'purpose','Audit of existing formal results; three diagnostic replays are not a performance study'));
fprintf('AUDIT COMPLETE %d checkpoints; RMSE reproduction max difference %.6g\n',count,maxdiff);
end

function row=diagnose(p,initial,pf,df,pm,dm,seed,noise_power,trial)
% Freeze observations and controls before differentiating unknown parameters.
[obs,noise]=fas_fine_observations(initial,pm,0,seed);
[guarded,guardnoise]=fas_fine_observations(initial,pm,4,seed);
for s=1:2
    [ok,ix]=ismember(guarded{s}.time,obs{s}.time); assert(all(ok));
    columns=reshape(1:size(obs{s}.symbol,2),numel(obs{s}.n),[]); columns=columns(:,ix);
    assert(isequal(guarded{s}.symbol,obs{s}.symbol(:,columns(:))));
    assert(isequal(guardnoise{s},noise{s}(:,columns(:))));
    assert(norm(obs{s}.B'*obs{s}.B-eye(obs{s}.rank),'fro')<1e-6);
end
y=echo(pm,obs,dm); yf=echo(pf,obs,dm);
row=struct('trial',trial,'seed',seed,'truth',p.truth,'coarse',initial, ...
    'fixed_positions_lambda',pf.tx_positions/p.lambda,'fas_positions_lambda',pm.tx_positions/p.lambda, ...
    'echo_change_with_frozen_design',norm(y-yf)/norm(y));
near=p.truth+repmat([.01 .05 .02 -.02],p.Q,1);
[z,fit]=refine_ris_parameters(y,obs,dm,near,pm);
[~,wrong]=refine_ris_parameters(y,obs,dm,near,pf);
row.noiseless_parameter_error=norm(z-p.truth,'fro');
row.correct_geometry_residual=fit.residual/norm(y)^2;
row.wrong_geometry_residual=wrong.residual/norm(y)^2;
assert(row.correct_geometry_residual<1e-8,'Perturbed noiseless recovery failed.');
row.fixed=information(pf,obs,df,noise_power);
row.fas=information(pm,obs,dm,noise_power);
row.fas_guard4=information(pm,guarded,dm,noise_power);
row.peb_reduction_percent=100*(1-row.fas.peb_m/row.fixed.peb_m);
row.peb_guard4_reduction_percent=100*(1-row.fas_guard4.peb_m/row.fixed.peb_m);
% Diagnose the response-matching proxy, using one legal move per element.
options=fas_options('full'); [dx,dy]=ndgrid(-1:1,-1:1);
offsets=[dx(:),dy(:),zeros(9,1)]*.1*p.lambda;
proxy=struct([]);
for antenna=1:size(pm.tx_positions,1)
    for k=1:size(offsets,1)
        if all(offsets(k,:)==0), continue; end
        pc=pm; pc.tx_positions(antenna,:)=pm.tx_positions(antenna,:)+offsets(k,:);
        if ~fas_positions_valid(pc.tx_positions,pc,options), continue; end
        dc=fas_transport_beams(initial,pm,pc,dm);
        residual=zeros(1,2); scale=zeros(1,2);
        for s=1:2
            old=responses(initial,pm,dm{s}); next=responses(initial,pc,dm{s});
            w=lsqminnorm(next',old'*dm{s}.W,1e-10); scale(s)=1/norm(w,'fro');
            residual(s)=norm(next'*dc{s}.W-scale(s)*(old'*dm{s}.W),'fro')/norm(old'*dm{s}.W,'fro');
        end
        [value,feasible]=fas_design_score(initial,pc,dc);
        entry=struct('antenna',antenna,'offset_lambda',offsets(k,:)/p.lambda, ...
            'response_match_relative_error',max(residual),'amplitude_scale',scale, ...
            'proxy_score',value,'proxy_feasible',feasible);
        if isempty(proxy), proxy=entry; else, proxy(end+1)=entry; end
        break;
    end
end
row.proxy_candidates=proxy;
end

function y=echo(p,obs,design)
yy=cell(2,1);
for s=1:2, [~,yy{s}]=fas_echo(p,obs{s},design{s},0,zeros(p.Mx*p.My,size(obs{s}.symbol,2))); end
y=vertcat(yy{:});
end

function A=responses(z,p,d)
g=channel_geometry(z,p);
u=channel_geometry([p.user_R(:),zeros(p.K_stream,1),p.user_theta(:),p.user_phi(:)],p);
u.V=u.V.*exp(-1j*2*pi*p.fc/p.c*(norm(p.ris_pos)+u.rr-p.user_R(:).'));
A=[g.transmit,g.to_ris,u.transmit+u.to_ris*conj(d.phase.'*u.V)];
end

function result=information(p,obs,design,noise_power)
% Conditional local information at truth; NOT a global FAS performance bound.
y=echo(p,obs,design); D=dictionary(p,obs,design); inverse=pinv(D,1e-8);
residual=norm(y-D*(inverse*y))/norm(y);
assert(residual<1e-7,'Independent path dictionary disagrees with simulator.');
steps=[1e-4 1e-3 1e-4 1e-4]; J=zeros(numel(y),4*p.Q); Jh=J;
for j=1:4
    for q=1:p.Q
        k=q+(j-1)*p.Q;
        plus=p; minus=p; plus.truth(q,j)=p.truth(q,j)+steps(j); minus.truth(q,j)=p.truth(q,j)-steps(j);
        J(:,k)=(echo(plus,obs,design)-echo(minus,obs,design))/(2*steps(j));
        plus.truth(q,j)=p.truth(q,j)+steps(j)/2; minus.truth(q,j)=p.truth(q,j)-steps(j)/2;
        Jh(:,k)=(echo(plus,obs,design)-echo(minus,obs,design))/steps(j);
    end
end
J=J-D*(inverse*J); Jh=Jh-D*(inverse*Jh);
convergence=norm(J-Jh,'fro')/norm(Jh,'fro'); assert(convergence<1e-4);
F=2/noise_power*real(Jh'*Jh); F=(F+F')/2;
scales=1./sqrt(diag(F)); Fs=F.*(scales*scales');
assert(min(eig(Fs))>1e-10,'Information is singular: do not report a finite PEB.');
C=(Fs\eye(size(Fs))).*(scales*scales'); P=zeros(3*p.Q,4*p.Q);
for q=1:p.Q
    z=p.truth(q,:); r=z(1); t=z(3); a=z(4);
    P((q-1)*3+(1:3),q)=[sind(t)*cosd(a);sind(t)*sind(a);cosd(t)];
    P((q-1)*3+(1:3),q+2*p.Q)=r*pi/180*[cosd(t)*cosd(a);cosd(t)*sind(a);-sind(t)];
    P((q-1)*3+(1:3),q+3*p.Q)=r*pi/180*[-sind(t)*sind(a);sind(t)*cosd(a);0];
end
result=struct('peb_m',sqrt(trace(P*C*P')/p.Q),'scaled_fim_min_eigenvalue',min(eig(Fs)), ...
    'dictionary_relative_residual',residual,'derivative_step_relative_change',convergence, ...
    'projected_signal_energy',norm(y)^2,'fisher_information',F);
end

function D=dictionary(p,obs,design)
% Four independent complex path amplitudes per target, shared across patterns,
% matching the nuisance-parameter model used by refine_ris_parameters.
M=p.Mx*p.My; D=zeros(M*sum(cellfun(@(o) o.rank,obs)),4*p.Q); first=0;
for s=1:2
    o=obs{s}; d=design{s}; ix=first+(1:M*o.rank); first=first+M*o.rank;
    for q=1:p.Q
        g=channel_geometry(p.truth(q,:),p);
        illumination=([g.transmit';g.to_ris']*d.W*o.symbol).';
        phase=exp(-1j*2*pi*p.delta_f/p.c*o.n_grid*g.distance+1j*2*pi*o.time_grid*g.doppler);
        ratio=d.phase.'*g.V/d.scale(q);
        waves=[phase(:,1).*illumination(:,1),phase(:,2).*illumination(:,2)*ratio, ...
            phase(:,2).*illumination(:,1)*ratio,phase(:,3).*illumination(:,2)*ratio^2];
        projection=o.B'*waves; spatial=[g.receive,g.receive,g.from_ris,g.from_ris];
        for a=1:4
            block=spatial(:,a)*projection(:,a).'; D(ix,(q-1)*4+a)=block(:);
        end
    end
end
end
