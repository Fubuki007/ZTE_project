function test_ris_codebook_rank1_e2e()
clear; clc; warning('off','all');
rng(20260928);
params = build_default_params();
params.Mx=8; params.My=8; params.Ntx=4; params.Nty=4;
params.N=256; params.B=params.N*120e3; params.K=32; params.K_stream=2;
params.num_targets=0; params.enable_SI=true; params.beta_SI=100; params.enable_SIC=false;
params.precoder_type='nullspace';
params.user_theta_rad=deg2rad([24.63;15.94]); params.user_phi_rad=deg2rad([30.99;13.58]);
Nt=params.Ntx*params.Nty; Nr=params.Mx*params.My;
cfg=struct('model','ura_rician','Nt_total',Nt,'Nr_total',Nr,'kappa_SI',1e6, ...
 'Ntx',params.Ntx,'Nty',params.Nty,'Mx',params.Mx,'My',params.My,'d_lambda',0.5, ...
 'theta_tx_deg',params.theta_SI,'phi_tx_deg',params.phi_SI, ...
 'theta_rx_deg',params.theta_SI,'phi_rx_deg',params.phi_SI);
[Hd, info] = generate_HSI(cfg);
[U,S,V] = svd(info.H_LoS); u=U(:,1); v=V(:,1); sigma=S(1,1);
% no-RIS waveform and actual SI power
p0=params; p0.H_SI=Hd; p0.H_SI_matrix=Hd;
tx0=generate_mimo_ofdm_waveform(p0);
rx0=simulate_radar_channel_3d(tx0.X,p0);
pow0=mean(abs(rx0(:)).^2);
Hc=tx0.H(:,:,1);
% rank-1 RIS path and codebook
Nris=128; rho=1.0; b=ones(Nris,1)/sqrt(Nris);
A=u*b'; B=b*v'; scale=sigma*rho;
H_RIS=@(theta) scale*(A*diag(exp(1j*theta))*B);
M=64; phi=2*pi*(0:M-1)/M; best=inf; best_theta=[];
for i=1:M
    theta=phi(i)*ones(Nris,1); Ht=Hd+H_RIS(theta);
    W=design_precoder(Hc,Ht,params.precoder_type); leak=norm(Ht*W,'fro')^2;
    if leak<best, best=leak; best_theta=theta; end
end
p=params; p.H_SI=Hd+H_RIS(best_theta); p.H_SI_matrix=p.H_SI;
tx=generate_mimo_ofdm_waveform(p);
rx=simulate_radar_channel_3d(tx.X,p);
pow1=mean(abs(rx(:)).^2);
fprintf('==== rank-1 RIS codebook end-to-end SI-only ====\n');
fprintf('no RIS SI power : %.6g\n', pow0);
fprintf('RIS   SI power : %.6g\n', pow1);
fprintf('improvement    : %.2f dB\n', 10*log10(pow0/pow1));
end
