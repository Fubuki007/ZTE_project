function diagnose_receive_beam()
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

% 构造每个子载波的直达 SI 矩阵 H_direct(:,:,m)*W(:,:,m)
HdW=zeros(Nr,M);
for m=1:M
  HdW(:,m)=ch.H_direct(:,:,m)*W(:,:,m);
end
[U,~,~]=svd(HdW,'econ'); u=U(:,1);
a_u=u'*HdW; a_u=a_u.';
B_u=zeros(N,M);
for m=1:M
  Wm=W(:,:,m);
  for n=1:N
    contrib=ch.G_rx(:,n,m)*(ch.G_tx(n,:,m)*Wm);
    B_u(n,m)=u'*contrib;
  end
end
phi=rcg_phase_optimize(a_u,conj(B_u),ones(M,1),p);
res_beam=mean(abs(a_u+B_u.'*phi).^2);
direct_beam=mean(abs(a_u).^2);
res_total=mean(abs(a_all+B_all.'*phi).^2);
direct_total=mean(abs(a_all).^2);
fprintf('dominant beam: direct=%.3g, residual=%.3g, supp=%.2f dB\n',direct_beam,res_beam,10*log10(direct_beam/res_beam));
fprintf('total: direct=%.3g, residual=%.3g, supp=%.2f dB\n',direct_total,res_total,10*log10(direct_total/res_total));
% 再试一个单天线接收通道 u=e1
u2=zeros(Nr,1); u2(1)=1;
a2=u2'*HdW; a2=a2.';
B2=zeros(N,M);
for m=1:M
  Wm=W(:,:,m);
  for n=1:N
    contrib=ch.G_rx(:,n,m)*(ch.G_tx(n,:,m)*Wm);
    B2(n,m)=u2'*contrib;
  end
end
phi2=rcg_phase_optimize(a2,conj(B2),ones(M,1),p);
res2=mean(abs(a2+B2.'*phi2).^2); direct2=mean(abs(a2).^2);
fprintf('single Rx: supp=%.2f dB, total supp with phi2=%.2f dB\n',10*log10(direct2/res2),10*log10(direct_total/mean(abs(a_all+B_all.'*phi2).^2)));
end
