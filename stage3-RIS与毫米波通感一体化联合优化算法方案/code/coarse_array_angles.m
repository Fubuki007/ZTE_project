function [angles,info]=coarse_array_angles(snapshots,p,method)
% Same focused spatial samples; legacy variants exist only for paired diagnosis.
if nargin<3, method='matched_array'; end
assert(ismember(method,{'legacy','signed_null','no_null','matched_array'}));
M=p.Mx*p.My; kw=2*pi*p.d/p.lambda; Q=numel(snapshots);
[x,y]=ndgrid(0:p.Mx-1,0:p.My-1); xy=[x(:),y(:)];
angles=zeros(Q,2); power=zeros(Q,1); exits=zeros(Q,1);
if strcmp(method,'matched_array')
    % shortcut: a 128-point grid plus local refinement; revisit for larger arrays.
    bins=(-64:63)*2*pi/(128*kw); [u,v]=ndgrid(bins,bins); valid=u.^2+v.^2<=1;
    for q=1:Q
        s=snapshots{q}; assert(size(s,1)==M && all(isfinite(s),'all'));
        spectrum=zeros(128);
        for k=1:size(s,2)
            f=fftshift(ifft2(reshape(s(:,k),p.Mx,p.My),128,128));
            spectrum=spectrum+abs(f).^2;
        end
        spectrum(~valid)=-Inf; [~,peak]=max(spectrum(:)); start=[u(peak),v(peak)];
        energy=max(M*sum(abs(s).^2,'all'),realmin);
        [uv,cost,exits(q)]=fminsearch(@objective,start, ...
            optimset('Display','off','MaxIter',120,'MaxFunEvals',240,'TolX',1e-8,'TolFun',1e-12));
        if objective(start)<cost, uv=start; end
        uv=uv/max(1,norm(uv)); angles(q,:)=[asind(min(norm(uv),1)),atan2d(uv(2),uv(1))];
        power(q)=-objective(uv);
    end
else
    saved=cell(1,Q);
    for q=1:Q
        [left,~,~]=svd(snapshots{q},'econ'); saved{q}=reshape(left(:,1),p.Mx,p.My);
        angles(q,:)=adjacent(saved{q});
    end
    if ~strcmp(method,'no_null')
        phase_sign=1; if strcmp(method,'signed_null'), phase_sign=-1; end
        for iteration=1:2
            previous=angles;
            for q=1:Q
                signal=saved{q}(:); original_norm=norm(signal);
                for j=1:Q
                    if j==q, continue; end
                    direction=sind(previous(j,1))*[cosd(previous(j,2)),sind(previous(j,2))];
                    ax=exp(phase_sign*1j*kw*(0:p.Mx-1).'*direction(1));
                    ay=exp(phase_sign*1j*kw*(0:p.My-1).'*direction(2));
                    a=ax*ay.'; a=a(:); a=a/(norm(a)+eps);
                    signal=signal-a*(a'*signal);
                end
                if norm(signal)<0.1*original_norm, signal=saved{q}(:); end
                angles(q,:)=adjacent(reshape(signal,p.Mx,p.My));
            end
        end
    end
end
info=struct('method',method,'beam_power_fraction',power,'refinement_exitflag',exits);
    function cost=objective(uv)
        radius=sum(uv.^2);
        if radius>1, cost=radius; return; end
        a=exp(-1j*kw*xy*uv(:)); cost=-sum(abs(a'*s).^2)/energy;
    end
    function a=adjacent(z)
        a1=z(1:end-1,:); a2=z(2:end,:);
        b1=z(:,1:end-1); b2=z(:,2:end);
        ux=-angle(sum(conj(a1(:)).*a2(:)))*p.lambda/(2*pi*p.d);
        uy=-angle(sum(conj(b1(:)).*b2(:)))*p.lambda/(2*pi*p.d);
        ux=max(min(ux,1),-1); uy=max(min(uy,1),-1);
        a=[asind(min(sqrt(ux^2+uy^2),1)),atan2d(uy,ux)];
    end
end
