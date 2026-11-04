function [peb,out,gradient]=loc_information(cache,positions,design,noise_power)
% Eliminate four unknown complex path amplitudes per target, shared across
% both configurations, as in the original estimator. Singular cases cost Inf.
if nargin<4, noise_power=1; end
p=cache.p; z=cache.z; Q=size(z,1); U=p.K_stream; L=4*Q*U; g=cache.g;
amplitudes=repmat(cache.amplitudes(:),1,4);
if isfield(cache,'path_weights')
    assert(isequal(size(cache.path_weights),[1 4]) && all(isfinite(cache.path_weights)) && all(cache.path_weights>=0));
    amplitudes=amplitudes.*cache.path_weights;
end
at=exp(1j*2*pi/p.lambda*positions*g.u);
ar=exp(1j*2*pi/p.lambda*positions*(p.ris_pos/norm(p.ris_pos)));
carrier=exp(-1j*2*pi*p.fref/p.c*(norm(p.ris_pos)+g.rr-z(:,1).'));
Ds=cell(2,1); Js=cell(2,1); path_illumination=[1 2 1 2]; orders=[0 1 1 2];
for s=1:2
    d=design{s}; target=at'*d.W; reflected=ar'*d.W;
    c=(d.phase.'*g.V).*carrier;
    C=zeros(L,4*Q); B=zeros(L,4*Q); T=cell(1,4);
    for j=1:4, T{j}=zeros(L,4*Q); end
    for q=1:Q
        for a=1:4
            column=(q-1)*4+a; ix=(column-1)*U+(1:U); order=orders(a);
            if path_illumination(a)==1, w=target(q,:); else, w=reflected; end
            coefficient=w*c(q)^order; C(ix,column)=coefficient.';
            for j=1:4
                da=at(:,q).*(1j*2*pi/p.lambda*positions*cache.dg{j}.u(:,q));
                if path_illumination(a)==1, dw=da'*d.W; else, dw=zeros(1,U); end
                dc=carrier(q)*(d.phase.'*cache.dg{j}.V(:,q)) ...
                    +c(q)*(-1j*2*pi*p.fref/p.c*(cache.dg{j}.rr(q)-(j==1)));
                derivative=dw*c(q)^order;
                if order>0, derivative=derivative+w*order*c(q)^(order-1)*dc; end
                B(ix,q+(j-1)*Q)=amplitudes(q,a)*derivative.';
                T{j}(ix,q+(j-1)*Q)=amplitudes(q,a)*coefficient.';
            end
        end
    end
    R=cache.R{s}; Ds{s}=R(:,1:L)*C; Js{s}=R(:,1:L)*B;
    for j=1:4, Js{s}=Js{s}+R(:,j*L+(1:L))*T{j}; end
end
D=vertcat(Ds{:}); J=vertcat(Js{:});
norms=vecnorm(D); keep=norms>1e-15; Dn=D(:,keep)./norms(keep);
[Ue,S,Ve]=svd(Dn,'econ'); singular=diag(S); active=singular>max(singular)*1e-10;
Ue=Ue(:,active); Jraw=J; J=J-Ue*(Ue'*J);
F=2/noise_power*real(J'*J); F=(F+F')/2;
diagonal=diag(F); peb=Inf; min_eigenvalue=0; covariance=[];
if all(diagonal>0) && all(isfinite(F),'all')
    scales=1./sqrt(diagonal); Fs=F.*(scales*scales');
    min_eigenvalue=min(eig(Fs));
    if min_eigenvalue>1e-10
        covariance=(Fs\eye(4*Q)).*(scales*scales');
        variance=trace(cache.P*covariance*cache.P')/Q;
        if variance>0, peb=sqrt(variance); end
    end
end
if nargout>1
    out=struct('F',F,'covariance',covariance,'min_eigenvalue',min_eigenvalue,'nuisance_rank',sum(active), ...
        'D',{Ds},'J_unprojected',{Js});
end
if nargout>2
    % Adjoint of log(PEB), including the changing nuisance subspace.
    gradient=struct('positions_lambda',zeros(size(positions)),'W',{cell(2,1)});
    for s=1:2, gradient.W{s}=zeros(size(design{s}.W)); end
    if ~isfinite(peb), return; end
    V=covariance*(cache.P'*cache.P)*covariance;
    GJ=-2/(noise_power*Q*peb^2)*(J*V);
    beta=zeros(4*Q,4*Q);
    beta(keep,:)=(Ve(:,active)*((Ue'*Jraw)./singular(active)))./norms(keep).';
    GD=-GJ*beta'; first=0;
    for s=1:2
        R=cache.R{s}; ix=first+(1:size(R,1)); first=first+size(R,1);
        gd=R(:,1:L)'*GD(ix,:); gj=R(:,1:L)'*GJ(ix,:);
        gt=cell(1,4); for j=1:4, gt{j}=R(:,j*L+(1:L))'*GJ(ix,:); end
        d=design{s}; c=(d.phase.'*g.V).*carrier;
        for q=1:Q
            for a=1:4
                column=(q-1)*4+a; bx=(column-1)*U+(1:U); order=orders(a);
                gb=gd(bx,column); gdb=zeros(U,4); dwave=zeros(1,4);
                for j=1:4
                    k=q+(j-1)*Q;
                    gb=gb+conj(amplitudes(q,a))*gt{j}(bx,k);
                    gdb(:,j)=conj(amplitudes(q,a))*gj(bx,k);
                    dc=carrier(q)*(d.phase.'*cache.dg{j}.V(:,q)) ...
                        +c(q)*(-1j*2*pi*p.fref/p.c*(cache.dg{j}.rr(q)-(j==1)));
                    if order>0, dwave(j)=order*c(q)^(order-1)*dc; end
                end
                gi=conj(c(q)^order)*gb+gdb*conj(dwave).';
                if path_illumination(a)==1
                    steering=at(:,q); direction=g.u(:,q);
                else
                    steering=ar; direction=p.ris_pos/norm(p.ris_pos);
                end
                gradient.W{s}=gradient.W{s}+steering*gi.';
                weighted=sum(d.W.*conj(gi.'),2);
                gradient.positions_lambda=gradient.positions_lambda+real((-1j*2*pi*conj(steering).*weighted)*direction.');
                if path_illumination(a)==1
                    for j=1:4
                        da=steering.*(1j*2*pi/p.lambda*positions*cache.dg{j}.u(:,q));
                        gdi=conj(c(q)^order)*gdb(:,j);
                        gradient.W{s}=gradient.W{s}+da*gdi.';
                        weighted=sum(d.W.*conj(gdi.'),2);
                        gradient.positions_lambda=gradient.positions_lambda+real( ...
                            (-1j*2*pi*conj(steering).*weighted)*cache.dg{j}.u(:,q).' ...
                            +(-1j*2*pi*conj(da).*weighted)*direction.');
                    end
                end
            end
        end
    end
end
end
