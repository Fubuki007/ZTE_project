function diagnose_conditioning()
root=fileparts(mfilename('fullpath'));
addpath(root); addpath(fullfile(root,'..')); addpath(fullfile(root,'..','RIS_SIC_Wu2024_验证'));
p=zte_ris_mimo_params(); p.M=32; p.d_sep_wl=1.5; p.x_c_wl=1.5; p.d_sep=p.d_sep_wl*p.lambda; p.x_c=p.x_c_wl*p.lambda;
p_tx=p; p_tx.N=p.M; p_tx.K=8; p_tx.K_stream=1; p_tx.precoder_type='zf';
p_tx.user_theta_rad=deg2rad(p.theta_true(1)); p_tx.user_phi_rad=deg2rad(p.phi_true(1));
if isfield(p_tx,'H_SI'), p_tx=rmfield(p_tx,'H_SI'); end
if isfield(p_tx,'H_SI_per_cc'), p_tx=rmfield(p_tx,'H_SI_per_cc'); end
tx=generate_mimo_ofdm_waveform(p_tx); W=tx.W;
for N=[144,256,400,676]
  p.N_ris=N; p.Nx_ris=sqrt(N); p.Ny_ris=sqrt(N);
  ch=generate_ris_mimo_channels(p);
  [a,h_r,info]=build_mimo_ris_objective(ch,W); B=info.B_all; Nr=ch.Nr;
  qidx=(1:Nr); Bm=B(:,qidx); am=a(qidx);
  sv=svd(Bm.');
  r=min(N,Nr);
  svn=sv(1:r);
  phi=-(Bm.')\am;
  fprintf('N=%3d: sv_nonzero min=%.3g max=%.3g cond=%.3g, norm(phi)=%.3g, max|phi|=%.3g\n',...
    N,min(svn),max(svn),max(svn)/max(min(svn),eps),norm(phi),max(abs(phi)));
end
end
