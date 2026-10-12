function diagnose_target_beam()
root=fileparts(mfilename('fullpath'));
addpath(root); addpath(fullfile(root,'..')); addpath(fullfile(root,'..','RIS_SIC_Wu2024_验证'));
rng(20240920,'twister');
p=zte_ris_mimo_params();
p.N_ris=144; p.Nx_ris=12; p.Ny_ris=12;
p.d_sep_wl=1.5; p.x_c_wl=1.5; p.d_sep=p.d_sep_wl*p.lambda; p.x_c=p.x_c_wl*p.lambda;
p.M=64; p.rcg.n_restarts=8; p.rcg.max_iter=1000;
ch=generate_ris_mimo_channels(p);
p_tx=p; p_tx.N=p.M; p_tx.K=8; p_tx.K_stream=1; p_tx.precoder_type='zf';
p_tx.user_theta_rad=deg2rad(p.theta_true(1)); p_tx.user_phi_rad=deg2rad(p.phi_true(1));
if isfield(p_tx,'H_SI'), p_tx=rmfield(p_tx,'H_SI'); end
if isfield(p_tx,'H_SI_per_cc'), p_tx=rmfield(p_tx,'H_SI_per_cc'); end
tx=generate_mimo_ofdm_waveform(p_tx); W=tx.W;
[a_all,h_r_all,info]=build_mimo_ris_objective(ch,W); B_all=info.B_all; Nr=ch.Nr; M=p.M; N=ch.N_ris;

% 目标方向接收导向矢量
theta=p.theta_true(1); phi=p.phi_true(1);
kw=2*pi*p.d/p.lambda;
mx=(0:p.Mx-1).'; my=(0:p.My-1).';
u=sin(theta*pi/180)*cos(phi*pi/180); v=sin(theta*pi/180)*sin(phi*pi/180);
ax=exp(-1j*kw*mx*u); ay=exp(-1j*kw*my*v);
uvec=ax*ay.'; uvec=uvec(:); uvec=uvec/norm(uvec);

HdW=zeros(Nr,M); for m=1:M, HdW(:,m)=ch.H_direct(:,:,m)*W(:,:,m); end
a_u=(uvec'*HdW).'; a_u=a_u(:);
B_u=zeros(N,M);
for m=1:M
  Wm=W(:,:,m);
  for n=1:N
    contrib=ch.G_rx(:,n,m)*(ch.G_tx(n,:,m)*Wm);
    B_u(n,m)=uvec'*contrib;
  end
end

% ideal ADMM
[phi_admm,info_admm]=solve_ideal_amplitude_admm(a_u, B_u, struct('max_iter',1000,'tol',1e-10));
res_admm=mean(abs(a_u+B_u.'*phi_admm).^2); direct=mean(abs(a_u).^2);
fprintf('target beam ADMM ideal: supp=%.2f dB, max|phi|=%.3f\n',10*log10(direct/res_admm),max(abs(phi_admm)));
% RCG from ADMM phase
phi_rcg=rcg_phase_optimize(a_u,conj(B_u),ones(M,1),p,exp(1j*angle(phi_admm)));
res_rcg=mean(abs(a_u+B_u.'*phi_rcg).^2);
fprintf('target beam RCG: supp=%.2f dB\n',10*log10(direct/res_rcg));
% total residual using target-beam phi
res_total=mean(abs(a_all+B_all.'*phi_rcg).^2); direct_total=mean(abs(a_all).^2);
fprintf('total SI with target-beam phi: supp=%.2f dB\n',10*log10(direct_total/res_total));
end
