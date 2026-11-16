function d=uav_design(z,p,enabled,configuration)
% Feasible ZF communication plus one sensing beam in its nullspace.
% shortcut: heuristic beam and phase design; not a globally optimal joint solver.
if nargin<4, configuration=1; end
p.ris_enabled=enabled; g=channel_geometry(z,p); U=p.K_stream;
levels=2^p.ris_bits;
if enabled
    weights=exp(1j*(configuration-1)*pi*(0:size(z,1)-1));
    a=angle(sum(conj(g.V)./max(abs(g.V),realmin).*weights,2));
    phase=exp(1j*2*pi/levels*round(a*levels/(2*pi)));
else
    phase=ones(p.ris_side^2,1);
end
users=[p.user_R(:),zeros(U,1),p.user_theta(:),p.user_phi(:)];
u=channel_geometry(users,p);
carrier=exp(-1j*2*pi*p.fc/p.c*(norm(p.ris_pos)+u.rr-p.user_R));
cuser=(phase.'*(u.V.*carrier));
gain=p.lambda./(4*pi*p.user_R);
H=(u.transmit+u.to_ris*conj(cuser)).*gain;
gamma=10.^(p.comm_sinr_db/10)*(1+1e-6);
W0=(H/(H'*H))*diag(sqrt(gamma.*p.comm_noise));
required=norm(W0,'fro')^2; W=W0/max(1,sqrt(required));
if required<=1
    P=eye(size(H,1))-H*((H'*H)\H'); P=(P+P')/2;
    c=phase.'*g.V; weights=(p.reference_range_m./z(:,1)).^4;
    E=(g.transmit.*weights.')*g.transmit' ...
        +sum(weights.'.*abs(c).^2)*(g.to_ris*g.to_ris');
    [V,D]=eig(P*E*P); [~,ix]=max(real(diag(D))); v=P*V(:,ix);
    if norm(v)>1e-8
        v=v/norm(v); W=W0+sqrt(max(0,1-required)/U)*repmat(v,1,U);
    else
        W=W0/max(sqrt(required),realmin);
    end
end
Y=H'*W; desired=abs(diag(Y)).^2;
sinr=desired./(sum(abs(Y).^2,2)-desired+p.comm_noise);
c=phase.'*g.V;
energy=(p.reference_range_m./z(:,1).').^4 ...
    .*(sum(abs(g.transmit'*W).^2,2).'+abs(c).^2*sum(abs(g.to_ris'*W).^2)) ...
    .*(1+abs(c).^2)*p.Mx*p.My;
scale=max(1e-12,p.ris_side^2*p.d^2/p.lambda*z(:,1).'./(norm(p.ris_pos)*g.rr));
d=struct('W',W,'phase',phase,'sinr',sinr,'required_power_fraction',required, ...
    'feasible',required<=1 && norm(W,'fro')^2<=1+1e-6 && all(sinr>=10.^(p.comm_sinr_db/10)), ...
    'score',min(energy),'scale',scale,'predicted_ris_response',abs(c));
end
