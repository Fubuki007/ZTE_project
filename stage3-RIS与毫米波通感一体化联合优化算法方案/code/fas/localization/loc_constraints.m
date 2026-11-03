function [c,ceq,G,Geq]=loc_constraints(x,p,phase,movable,positions)
% Variables: real(W1,W2), imag(W1,W2), optional xy coordinates / lambda.
Nt=p.Ntx*p.Nty; U=p.K_stream; n=2*Nt*U; nv=numel(x);
W=reshape(x(1:n)+1j*x(n+(1:n)),Nt,U,2);
if movable, positions=[reshape(x(2*n+1:end),Nt,2),zeros(Nt,1)]*p.lambda; end
users=[p.user_R(:),zeros(U,1),p.user_theta(:),p.user_phi(:)];
u=channel_geometry(users,p); direction=p.ris_pos/norm(p.ris_pos);
at=exp(1j*2*pi/p.lambda*positions*u.u); ar=exp(1j*2*pi/p.lambda*positions*direction);
u.V=u.V.*exp(-1j*2*pi*p.fc/p.c*(norm(p.ris_pos)+u.rr-p.user_R(:).'));
gamma=10.^(p.comm_sinr_db/10)*(1+1e-5);
count=2*(1+U)+movable*Nt*(Nt-1)/2; c=zeros(count,1); G=zeros(nv,count); k=0;
for s=1:2
    H=at+ar*conj(phase{s}.'*u.V); Y=H'*W(:,:,s);
    k=k+1; c(k)=norm(W(:,:,s),'fro')^2-1;
    ix=(s-1)*Nt*U+(1:Nt*U); gw=2*W(:,:,s);
    G(ix,k)=real(gw(:)); G(n+ix,k)=imag(gw(:));
    for user=1:U
        k=k+1; weights=gamma(user)*ones(1,U); weights(user)=-1;
        c(k)=sum(weights.*abs(Y(user,:)).^2)+gamma(user)*p.comm_noise(user);
        gw=2*H(:,user)*(weights.*Y(user,:));
        G(ix,k)=real(gw(:)); G(n+ix,k)=imag(gw(:));
        if movable
            for coordinate=1:2
                dh=1j*2*pi*(at(:,user)*u.u(coordinate,user) ...
                    +ar*direction(coordinate)*conj(phase{s}.'*u.V(:,user)));
                dy=conj(dh).*W(:,:,s);
                G(2*n+(coordinate-1)*Nt+(1:Nt),k)=2*real(sum(dy.*(weights.*conj(Y(user,:))),2));
            end
        end
    end
end
if movable
    xy=positions(:,1:2)/p.lambda;
    for a=1:Nt
        for b=a+1:Nt
            k=k+1; delta=xy(a,:)-xy(b,:); c(k)=.400001^2-sum(delta.^2);
            G(2*n+[a,Nt+a],k)=-2*delta.'; G(2*n+[b,Nt+b],k)=2*delta.';
        end
    end
end
ceq=[]; Geq=[];
end
