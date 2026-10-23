function test_fas()
root=fileparts(mfilename('fullpath')); addpath(root,fileparts(root));
assert(license('test','Optimization_Toolbox'),'Optimization Toolbox is required.');
opt=fas_options('smoke'); p=fas_parameters(opt,0,10); maxNumCompThreads(2);
g=channel_geometry(p.truth,p); [x,y]=ndgrid(0:p.Ntx-1,0:p.Nty-1);
legacy=exp(1j*pi*(x(:)*g.u(1,:)+y(:)*g.u(2,:)));
assert(norm(g.transmit-legacy,'fro')<1e-12,'Legacy Tx response changed.');
px=p; px.tx_positions=p.d*[x(:),y(:),zeros(numel(x),1)];
gx=channel_geometry(p.truth,px); assert(norm(gx.transmit-g.transmit,'fro')<1e-12);
assert(fas_positions_valid(px.tx_positions,p,opt));
bad=px.tx_positions; bad(1,:)=bad(2,:); assert(~fas_positions_valid(bad,p,opt));
bad=px.tx_positions; bad(1,1)=-p.lambda; assert(~fas_positions_valid(bad,p,opt));
% Common noise and QAM must match at every retained time after switching.
[o0,e0]=fas_fine_observations(p.truth,p,0,100);
[og,eg]=fas_fine_observations(p.truth,p,4,100);
for s=1:2
    [yes,ix]=ismember(og{s}.time,o0{s}.time); assert(all(yes));
    cols=reshape(1:size(o0{s}.symbol,2),numel(o0{s}.n),[]); cols=cols(:,ix);
    assert(isequal(og{s}.symbol,o0{s}.symbol(:,cols(:))));
    assert(isequal(eg{s},e0{s}(:,cols(:))));
    assert(norm(og{s}.B'*og{s}.B-eye(og{s}.rank),'fro')<1e-6);
end
for enabled=[false,true]
    p.ris_enabled=enabled;
    [pf,df,infof]=fas_optimize_array(p.truth,p,opt,false);
    [pm,dm,infom]=fas_optimize_array(p.truth,p,opt,true);
    assert(infof.feasible && infom.feasible,'Test geometry must meet QoS.');
    assert(fas_positions_valid(pm.tx_positions,p,opt));
    assert(all(diff(infom.objective)>=-1e-8),'Position/beam design lost its incumbent.');
    altered=p; altered.truth(:)=999; altered.R_true(:)=999;
    [pa,da,~]=fas_optimize_array(p.truth,altered,opt,true);
    assert(norm(pa.tx_positions-pm.tx_positions,'fro')<1e-12,'Design leaked truth.');
    assert(norm(da{1}.W-dm{1}.W,'fro')<1e-10,'Design leaked truth.');
    if ~enabled
        gd=channel_geometry(p.truth,pf); assert(all(gd.V==0,'all'));
    end
    [obs,noise]=fas_fine_observations(p.truth,pm,0,123); yy=cell(2,1);
    for s=1:2
        yy{s}=fas_echo(pm,obs{s},dm{s},0,noise{s});
    end
    [estimate,fit]=refine_ris_parameters(vertcat(yy{:}),obs,dm,p.truth,pm);
    assert(fit.residual/max(norm(vertcat(yy{:}))^2,eps)<1e-8,'Synthesis and estimator disagree.');
    assert(norm(estimate-p.truth,'fro')<1e-4,'Noiseless truth should be a fixed point.');
end
full=fas_parameters(fas_options('full'),0,-20);
assert(full.N==12672 && full.K==256 && full.Mx*full.My==64 && ...
    full.Ntx*full.Nty==16 && full.ris_side^2==256 && full.K_stream==2);
assert(full.coarse_n==384 && full.coarse_l==64 && full.fine_n==256 && full.fine_l==64);
identity=fas_source_identity();
evidence=struct('passed',true,'matlab_version',version,'source_sha256',identity.sha256, ...
    'checks',{{'legacy geometry','physical port bounds and spacing','paired QAM/noise after guard', ...
    'projection whitening','communication feasibility','monotone accepted search', ...
    'truth independence','no-RIS switch','noiseless estimator consistency','full parameter preservation'}});
fas_write_json(fullfile(root,'test_evidence.json'),evidence);
fprintf('PASS: all FAS mathematical/integration checks.\n');
end
