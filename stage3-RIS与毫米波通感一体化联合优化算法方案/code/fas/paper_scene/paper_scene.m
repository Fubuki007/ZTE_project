function c=paper_scene(p,seed,rice_db)
% Paper-inspired, gain-normalized field-response experiment; not a reproduction.
rng(seed,'twister'); c=struct('p',p,'seed',seed,'rice_db',rice_db);
c.ris_pos=[100;0;0]; c.user_pos=[100;0;-1];
c.active_users=1; c.active_targets=1;
c.z=p.truth(1,:); c.direct=.01; c.reflected=.1;
c.power=1; c.radar_noise=.1; c.comm_noise=p.comm_noise(1);
c.gamma=10^(p.comm_sinr_db(1)/10); c.aperture=(p.Ntx-1)/2;
c.spacing=.4; c.grid=.1; c.paths=32;
[x,y]=ndgrid(0:p.Ntx-1,0:p.Nty-1); c.uniform=[x(:),y(:)]/2;
% Rx preserves the original half-wavelength 8x8 aperture, independently of Tx.
[x,y]=ndgrid(0:p.Mx-1,0:p.My-1); c.rx=[x(:),y(:),zeros(numel(x),1)]/2;
v=((0:p.ris_side-1)-(p.ris_side-1)/2)/2; [x,y]=ndgrid(v,v);
c.ris_offsets=[zeros(numel(x),1),x(:),y(:)]; N=size(c.ris_offsets,1);
u=c.ris_pos/norm(c.ris_pos); c.departure=[u,random_directions(c.paths)];
arrival=[u,random_directions(c.paths)];
c.surface=exp(1j*2*pi*c.ris_offsets*arrival);
diffuse=(randn(c.paths,1)+1j*randn(c.paths,1))/sqrt(2*c.paths);
if isinf(rice_db) && rice_db>0, a=1; b=0;
elseif isinf(rice_db), a=0; b=1;
else, k=10^(rice_db/10); a=sqrt(k/(1+k)); b=sqrt(1/(1+k)); end
c.coefficients=[a;b*diffuse]/sqrt(N);
raw=c.surface*(c.coefficients.*exp(-1j*2*pi*c.departure(1:2,:).'*c.uniform.'));
c.link_scale=sqrt(numel(c.uniform)/2)/norm(raw,'fro');
c.coefficients=c.coefficients*c.link_scale;
c.Grx=c.surface*(c.coefficients.*exp(-1j*2*pi*c.departure.'*c.rx.'));
c.user_directions=random_directions(c.paths);
c.user_coefficients=(randn(c.paths,1)+1j*randn(c.paths,1))/sqrt(2*c.paths);
raw=exp(1j*2*pi*c.uniform*c.user_directions(1:2,:))*c.user_coefficients;
c.user_coefficients=c.user_coefficients*sqrt(size(c.uniform,1))/norm(raw);
c.h1=(randn(N,1)+1j*randn(N,1))/sqrt(2);
c=paper_target(c,c.z);
% Audit of the printed physical link budget, separate from normalized results.
c.printed_link_budget=struct('G_power',.1*1e-3*100^(-3.5), ...
    'h2_power',.1*1e-3*100^(-2),'h1_power',.1*1e-3, ...
    'noRIS_user_MRT_SNR_dB',10*log10(3*size(c.uniform,1)*.1*1e-3*100^(-2)/.1));
end

function u=random_directions(n)
u=randn(3,n); u=u./vecnorm(u);
end
