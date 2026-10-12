function diagnose_mimo_ris()
root=fileparts(mfilename('fullpath'));
addpath(root); addpath(fullfile(root,'..')); addpath(fullfile(root,'..','RIS_SIC_Wu2024_验证'));
params=zte_ris_mimo_params();
ch=generate_ris_mimo_channels(params);
p_tx=params; p_tx.N=params.M; p_tx.K=8; p_tx.K_stream=1; p_tx.precoder_type='zf';
p_tx.user_theta_rad=deg2rad(params.theta_true(1)); p_tx.user_phi_rad=deg2rad(params.phi_true(1));
if isfield(p_tx,'H_SI'), p_tx=rmfield(p_tx,'H_SI'); end
if isfield(p_tx,'H_SI_per_cc'), p_tx=rmfield(p_tx,'H_SI_per_cc'); end
tx=generate_mimo_ofdm_waveform(p_tx);
[h_d,h_r,info]=build_mimo_ris_objective(ch,tx.W);
a=info.a_all; B=info.B_all; N=ch.N_ris;
direct_pow=mean(abs(a).^2);
ris_one=mean(abs(B.'*ones(N,1)).^2);
max_ris=mean(sum(abs(B),1).^2);
fprintf('direct_pow=%.6g, ris_all_one_phase_pow=%.6g, ratio_dB=%.2f, max_coherent_pow=%.6g, max_ratio_dB=%.2f\n',...
 direct_pow,ris_one,10*log10(direct_pow/max(ris_one,eps)),max_ris,10*log10(direct_pow/max(max_ris,eps)));
sv=svd(B.');
fprintf('svd(B.''): max=%.4g min=%.4g cond=%.4g rank=%d\n',sv(1),sv(end),sv(1)/max(sv(end),eps),rank(B.'));
% unconstrained LS
phi_ls=-(B.')\a;
res_ls=mean(abs(a+B.'*phi_ls).^2);
fprintf('unconstrained LS residual=%.6g, supp=%.2f dB, norm(phi_ls)=%.3f, max|phi_ls|=%.3f\n',...
 res_ls,10*log10(direct_pow/res_ls),norm(phi_ls),max(abs(phi_ls)));
% projected gradient ideal |phi|<=1
A=conj(B)*B.'; c=conj(B)*a;
L=2*max(real(eig(A))); alpha=1/max(L,eps);
phi=ones(N,1);
for it=1:20000
  g=2*(A*phi+c);
  phi=phi-alpha*g;
  phi=phi.*min(1,1./max(abs(phi),eps));
end
res_pg=mean(abs(a+B.'*phi).^2);
fprintf('ideal PG residual=%.6g, supp=%.2f dB, max|phi|=%.3f, norm=%.3f\n',res_pg,10*log10(direct_pow/res_pg),max(abs(phi)),norm(phi));
end
