function cache=loc_information_cache(z,p,obs,amplitudes,keep_basis)
% Exact QR compression of the original projected observation and its local
% derivatives. Controls may change; design location and observations stay fixed.
if nargin<5, keep_basis=false; end
Q=size(z,1); U=p.K_stream; M=p.Mx*p.My; L=4*Q*U;
g=channel_geometry(z,p); step=[1e-5 1e-4 1e-5 1e-5];
dg=cell(1,4);
for j=1:4
    plus=z; minus=z; plus(:,j)=plus(:,j)+step(j); minus(:,j)=minus(:,j)-step(j);
    gp=channel_geometry(plus,p); gm=channel_geometry(minus,p);
    fields={'u','receive','V','rr','distance','doppler'};
    for k=1:numel(fields)
        key=fields{k}; dg{j}.(key)=(gp.(key)-gm.(key))/(2*step(j));
    end
end
cache=struct('z',z,'p',p,'g',g,'dg',{dg},'amplitudes',amplitudes(:), ...
    'R',{cell(2,1)},'left',{cell(2,1)},'rows',zeros(2,1),'P',zeros(3*Q,4*Q));
path_time=[1 2 2 3]; path_receive=[1 1 2 2];
for s=1:2
    o=obs{s}; K=zeros(M*o.rank,L*5); cache.rows(s)=M*o.rank;
    for q=1:Q
        phase=exp(-1j*2*pi*p.delta_f/p.c*o.n_grid*g.distance(q,:) ...
            +1j*2*pi*o.time_grid*g.doppler(q,:));
        for a=1:4
            f=path_time(a); receive=path_receive(a);
            if receive==1, spatial=g.receive(:,q); else, spatial=g.from_ris; end
            waves=phase(:,f).*o.symbol.'; temporal=o.B'*waves;
            columns=((q-1)*4+a-1)*U+(1:U);
            for u=1:U, K(:,columns(u))=reshape(spatial*temporal(:,u).',[],1); end
            for j=1:4
                slope=-1j*2*pi*p.delta_f/p.c*o.n_grid*dg{j}.distance(q,f) ...
                    +1j*2*pi*o.time_grid*dg{j}.doppler(q,f);
                dt=o.B'*(waves.*slope);
                if receive==1, ds=dg{j}.receive(:,q); else, ds=zeros(M,1); end
                for u=1:U
                    K(:,columns(u)+j*L)=reshape(ds*temporal(:,u).'+spatial*dt(:,u).',[],1);
                end
            end
        end
    end
    [left,R]=qr(K,0); cache.R{s}=R;
    if keep_basis, cache.left{s}=left; end
end
for q=1:Q
    r=z(q,1); t=z(q,3); a=z(q,4); ix=(q-1)*3+(1:3);
    cache.P(ix,q)=[sind(t)*cosd(a);sind(t)*sind(a);cosd(t)];
    cache.P(ix,q+2*Q)=r*pi/180*[cosd(t)*cosd(a);cosd(t)*sind(a);-sind(t)];
    cache.P(ix,q+3*Q)=r*pi/180*[-sind(t)*sind(a);sind(t)*cosd(a);0];
end
end
