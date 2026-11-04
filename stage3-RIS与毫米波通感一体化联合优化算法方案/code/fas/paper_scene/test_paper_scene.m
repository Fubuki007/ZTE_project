function report=test_paper_scene(output,full_size)
if nargin<2, full_size=false; end
root=fileparts(mfilename('fullpath')); code=fileparts(fileparts(root));
cd(code); addpath(root,code,fileparts(root)); maxNumCompThreads(2);
rng(43); p=build_default_params();
if ~full_size, p.N=128; p.K=16; p.Mx=3; p.My=3; p.ris_side=4; p.fine_n=32; p.fine_l=12; end
c=paper_scene(p,2026110400,10); X=c.uniform; v=exp(1j*(0:numel(c.a)-1)'*pi/2);
b=paper_controls(c,X,v); [w,~,ok]=paper_beam(c,b); assert(ok); b=paper_controls(c,X,v,w);
h=1e-6; numeric=zeros(size(X)); nc=numeric;
for j=1:numel(X)
    xp=X; xm=X; xp(j)=xp(j)+h; xm(j)=xm(j)-h;
    bp=paper_controls(c,xp,v,w); bm=paper_controls(c,xm,v,w);
    numeric(j)=(bp.score-bm.score)/(2*h); nc(j)=(abs(bp.comm)^2-abs(bm.comm)^2)/(2*h);
end
report=struct('full_size',full_size,'position_gradient_error',norm(numeric-b.gradient,'fro')/norm(numeric,'fro'), ...
    'communication_gradient_error',norm(nc-b.comm_gradient,'fro')/norm(nc,'fro'));
assert(report.position_gradient_error<1e-6 && report.communication_gradient_error<1e-6);
% Co-located Tx and Rx ports must sample exactly the same scatterer realization.
Xrx=c.rx(:,1:2); br=paper_controls(c,Xrx,v);
report.reciprocal_field_error=norm(br.G-c.Grx,'fro')/norm(c.Grx,'fro');
assert(report.reciprocal_field_error<1e-13);
cb=paper_controls(c,X,v); [w,s,ok]=paper_beam(c,cb); assert(ok);
report.beam_sinr=abs(cb.h'*w)^2/c.comm_noise; assert(report.beam_sinr>=c.gamma*(1-1e-8));
d=struct('X',X,'v',v,'w',w); [peb,info]=paper_information(c,d,0,~full_size);
report.peb=peb; report.gram_dense_error=info.dense_error;
if ~full_size, assert(info.dense_error<1e-9); end
if ~full_size
    % Independently difference the physical space-time echo, not the Gram code.
    [mean_echo,H]=physical(c,d); J=zeros(numel(mean_echo),4); steps=[1e-4 1e-4 1e-5 1e-5];
    for j=1:4
        zp=c.z; zm=c.z; zp(j)=zp(j)+steps(j); zm(j)=zm(j)-steps(j);
        J(:,j)=(physical(paper_target(c,zp),d)-physical(paper_target(c,zm),d))/(2*steps(j));
    end
    [Q,~]=qr(H,0); F=2/c.radar_noise*real(J'*(J-Q*(Q'*J)));
    [~,info]=paper_information(c,d,0); analytic=inv(info.covariance);
    report.physical_information_error=norm(F-analytic,'fro')/norm(F,'fro');
    assert(report.physical_information_error<1e-5);
end
% Removing a known number of samples cannot improve an unchanged design's bound.
guard=4; pg=paper_information(c,d,guard); assert(pg>=peb*(1-1e-7));
report.guard_peb=pg;
los=paper_scene(p,2026110400,inf);
vl=exp(1j*pi/2*round(angle(los.surface(:,1).*conj(los.a))*2/pi));
bl=paper_controls(los,X,vl); [wl,~,ok]=paper_beam(los,bl); assert(ok);
dl=struct('X',X,'v',vl,'w',wl); report.los_peb=paper_information(los,dl,0);
assert(isfinite(report.los_peb),'A nonzero identifiable DD path must survive strong RR scaling.');
los.direct=0; report.only_RR_los_peb=paper_information(los,dl,0);
assert(isinf(report.only_RR_los_peb),'One rank-one RR path cannot identify all spatial directions.');
report.passed=true;
if nargin>=1 && ~isempty(output), fas_write_json(output,report); end
disp(report);
end

function [y,H]=physical(c,d)
p=c.p; n=round(linspace(0,p.N-1,min(p.N,p.fine_n))).';
time=(p.K+round(linspace(0,p.K-1,min(p.K,p.fine_l))))*p.Ts;
nn=repmat(n,numel(time),1); tt=repelem(time(:),numel(n));
b=paper_controls(c,d.X,d.v,d.w); H=zeros(size(b.parts,1)*numel(nn),2);
for a=1:2
    phase=exp(-1j*2*pi*p.delta_f/p.c*nn*c.distance(a)+1j*2*pi*tt*c.doppler(a));
    echo=b.parts(:,a)*phase.'; H(:,a)=echo(:);
end
y=sum(H,2);
end
