function diagnose_single_subcarrier()
root=fileparts(mfilename('fullpath'));
addpath(root); addpath(fullfile(root,'..')); addpath(fullfile(root,'..','RIS_SIC_Wu2024_验证'));
p=zte_ris_mimo_params();
p.N_ris=144; p.Nx_ris=12; p.Ny_ris=12;
p.d_sep_wl=1.5; p.x_c_wl=1.5; p.d_sep=p.d_sep_wl*p.lambda; p.x_c=p.x_c_wl*p.lambda;
p.M=64;
ch=generate_ris_mimo_channels(p);
p_tx=p; p_tx.N=p.M; p_tx.K=8; p_tx.K_stream=1; p_tx.precoder_type='zf';
p_tx.user_theta_rad=deg2rad(p.theta_true(1)); p_tx.user_phi_rad=deg2rad(p.phi_true(1));
if isfield(p_tx,'H_SI'), p_tx=rmfield(p_tx,'H_SI'); end
if isfield(p_tx,'H_SI_per_cc'), p_tx=rmfield(p_tx,'H_SI_per_cc'); end
tx=generate_mimo_ofdm_waveform(p_tx); W=tx.W;
[a,h_r,info]=build_mimo_ris_objective(ch,W); B=info.B_all; Nr=ch.Nr; K=size(W,2); M=p.M;
for m=[1, round(M/2), M]
  qidx=(m-1)*Nr*K+(1:Nr*K);
  Bm=B(:,qidx); am=a(qidx);
  sv=svd(Bm.');
  fprintf('m=%d, direct_pow=%.3g, sv_max=%.3g, sv_min=%.3g, cond=%.3g, rank=%d\n',...
    m,mean(abs(am).^2),sv(1),sv(end),sv(1)/max(sv(end),eps),rank(Bm.'));
  phi_ls=-(Bm.')\am;
  res_ls=mean(abs(am+Bm.'*phi_ls).^2);
  fprintf('  unconstrained res=%.3g, supp=%.2f dB, norm(phi)=%.3f, max|phi|=%.3f\n',...
    res_ls,10*log10(mean(abs(am).^2)/res_ls),norm(phi_ls),max(abs(phi_ls)));
  maxcol=mean(sum(abs(Bm),1).^2);
  fprintf('  max_coherent_pow=%.3g, ratio_dB=%.2f\n',maxcol,10*log10(mean(abs(am).^2)/max(maxcol,eps)));
end
end
