function b=paper_controls(c,X,v,w)
E=exp(-1j*2*pi*c.departure(1:2,:).'*X.');
b.G=c.surface*(c.coefficients.*E);
F=exp(1j*2*pi*X*c.user_directions(1:2,:));
b.h2=F*c.user_coefficients; b.atx=exp(1j*2*pi*X*c.u(1:2));
b.brx=c.Grx'*(v.*c.a); b.btx=b.G'*(v.*c.a);
b.h=b.h2+b.G'*(v.*c.h1);
b.H=c.direct*c.arx*b.atx'+c.reflected*b.brx*b.btx';
if nargin<4, return; end
b.parts=[c.direct*c.arx*(b.atx'*w),c.reflected*b.brx*(b.btx'*w)];
b.y=sum(b.parts,2); b.score=real(b.y'*b.y); b.comm=b.h'*w;
b.gradient=zeros(size(X)); b.comm_gradient=zeros(size(X));
for j=1:2
    dG=c.surface*(c.coefficients.*(-1j*2*pi*c.departure(j,:).').*E);
    dh2=(F.*(1j*2*pi*c.user_directions(j,:)))*c.user_coefficients;
    dtx=-1j*2*pi*c.u(j)*conj(b.atx);
    ds=(v.*c.a)'*dG;
    dy=(c.direct*c.arx*dtx.'+c.reflected*b.brx*ds).*w.';
    b.gradient(:,j)=2*real(b.y'*dy).';
    dc=(conj(dh2).'+(v.*c.h1)'*dG).*w.';
    b.comm_gradient(:,j)=2*real(conj(b.comm)*dc).';
end
end
