function [peb,out]=paper_information(c,d,guard,dense)
% Exact expected-symbol Gram for a DD/RR wideband extension of the paper.
% Unknown DD and RR complex amplitudes are eliminated; this is an oracle bound.
if nargin<4, dense=false; end
p=c.p; n=round(linspace(0,p.N-1,min(p.N,p.fine_n))).';
symbols=round(linspace(0,p.K-1,min(p.K,p.fine_l)));
symbols=symbols(symbols>=guard); time=(p.K+symbols)*p.Ts;
distance=c.distance; doppler=c.doppler;
G=zeros(6); base_order=[0 1 0]; time_order=[0 0 1];
for a=1:2
    for b=1:2
        pn=exp(-1j*2*pi*p.delta_f/p.c*n*(distance(b)-distance(a)));
        pt=exp(1j*2*pi*time*(doppler(b)-doppler(a)));
        for i=1:3
            for j=1:3
                G((a-1)*3+i,(b-1)*3+j)=sum(n.^(base_order(i)+base_order(j)).*pn) ...
                    *sum(time.^(time_order(i)+time_order(j)).*pt);
            end
        end
    end
end
b=paper_controls(c,d.X,d.v,d.w); s=b.parts; M=size(s,1);
C=repmat({zeros(M,6)},1,6); C{1}(:,1)=s(:,1); C{2}(:,4)=s(:,2);
steps=[1e-4 1e-4 1e-5 1e-5];
for j=1:4
    plus=c.z; minus=c.z; plus(j)=plus(j)+steps(j); minus(j)=minus(j)-steps(j);
    cp=paper_target(c,plus); cm=paper_target(c,minus);
    bp=paper_controls(cp,d.X,d.v,d.w); bm=paper_controls(cm,d.X,d.v,d.w);
    ds=(bp.parts-bm.parts)/(2*steps(j)); dd=(cp.distance-cm.distance)/(2*steps(j));
    df=(cp.doppler-cm.doppler)/(2*steps(j));
    for a=1:2
        ix=(a-1)*3; C{j+2}(:,ix+1)=ds(:,a);
        C{j+2}(:,ix+2)=s(:,a)*(-1j*2*pi*p.delta_f/p.c*dd(a));
        C{j+2}(:,ix+3)=s(:,a)*(1j*2*pi*df(a));
    end
end
K=zeros(6); for i=1:6, for j=1:6, K(i,j)=sum((C{i}'*C{j}).*G,'all'); end; end
out=struct('gram',K,'dense_error',nan,'covariance',[],'finite',false);
nn=repmat(n,numel(time),1); tt=repelem(time(:),numel(n)); T=zeros(numel(nn),6);
for a=1:2
    e=exp(-1j*2*pi*p.delta_f/p.c*nn*distance(a)+1j*2*pi*tt*doppler(a));
    T(:,(a-1)*3+(1:3))=[e,nn.*e,tt.*e];
end
if dense
    Z=zeros(M*numel(nn),6); for j=1:6, Y=C{j}*T.'; Z(:,j)=Y(:); end
    out.dense_error=norm(K-Z'*Z,'fro')/max(norm(K,'fro'),realmin);
end
% QR compression and SVD avoid subtracting enormous nearly equal FIM terms.
tscale=vecnorm(T); [~,R]=qr(T./tscale,0); R=R.*tscale;
Z=zeros(M*6,6);
for j=1:6, Y=C{j}*R.'; Z(:,j)=Y(:); end
active=find(vecnorm(Z(:,1:2))>0); H=Z(:,active);
[Qh,~]=qr(H./vecnorm(H),0); D=Z(:,3:6); D=D-Qh*(Qh'*D);
A=sqrt(2/c.radar_noise)*[real(D);imag(D)]; scale=vecnorm(A); peb=inf;
if any(scale==0), return; end
[~,S,V]=svd(A./scale,0); singular=diag(S); out.singular_values=singular;
out.eigenvalues=singular.^2;
if min(singular)<=max(singular)*eps*max(size(A))*8, return; end
covariance=((V./singular.')*(V./singular.')')./(scale.'*scale);
z=c.z; u=c.u; r=z(1); t=z(3); a=z(4);
P=[u,zeros(3,1),r*pi/180*[cosd(t)*cosd(a);cosd(t)*sind(a);-sind(t)], ...
    r*pi/180*[-sind(t)*sind(a);sind(t)*cosd(a);0]];
peb=sqrt(max(0,trace(P*covariance*P'))); out.finite=isfinite(peb); out.covariance=covariance;
end
