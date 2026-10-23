function [score,feasible,sinr]=fas_design_score(z,p,design)
% The supplied max-min illumination objective, averaged over two patterns.
g=channel_geometry(z,p); Nt=p.Ntx*p.Nty;
users=[p.user_R(:),zeros(p.K_stream,1),p.user_theta(:),p.user_phi(:)];
u=channel_geometry(users,p);
carrier=exp(-1j*2*pi*p.fc/p.c*(norm(p.ris_pos)+u.rr-p.user_R(:).'));
u.V=u.V.*carrier;
energy=zeros(numel(design),size(z,1)); sinr=zeros(p.K_stream,numel(design));
feasible=true;
for s=1:numel(design)
    d=design{s}; c=d.phase.'*g.V;
    energy(s,:)=sum(abs(g.transmit'/sqrt(Nt)*d.W).^2,2).' ...
        +abs(c).^2*sum(abs(g.to_ris'/sqrt(Nt)*d.W).^2);
    H=u.transmit+u.to_ris*conj(d.phase.'*u.V); Y=H'*d.W;
    signal=abs(diag(Y)).^2;
    sinr(:,s)=signal./(sum(abs(Y).^2,2)-signal+p.comm_noise);
    feasible=feasible && norm(d.W,'fro')<=1+1e-6 && ...
        all(sinr(:,s)>=10.^(p.comm_sinr_db/10));
end
score=min(mean(energy,1));
end
