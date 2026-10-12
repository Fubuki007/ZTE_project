function test_ris_codebook_rank1_kappa10()
clear; clc; warning('off','all');
rng(20260928);
params=build_default_params();
params.Mx=8; params.My=8; params.Ntx=4; params.Nty=4;
params.N=256; params.B=params.N*120e3; params.K=32; params.K_stream=2;
params.num_targets=0; params.enable_SI=true; params.beta_SI=100; params.enable_SIC=false;
params.precoder_type='nullspace';
params.user_theta_rad=deg2rad([24.63;15.94]); params.user_phi_rad=deg2rad([30.99;13.58]);
Nt=params.Ntx*params.Nty; Nr=params.Mx*params.My;
cfg=struct('model','ura_rician','Nt_total',Nt,'Nr_total',Nr,'kappa_SI',10, ...
 'Ntx',params.Ntx,'Nty',params.Nty,'Mx',params.Mx,'My',params.My,'d_lambda',0.5, ...
 'theta_tx_deg',params.theta_SI,'phi_tx_deg',params.phi_SI, ...
 'theta_rx_deg',params.theta_SI,'phi_rx_deg',params.phi_SI);
[Hd,info]=generate_HSI(cfg);
[U,S,V]=svd(info.H_LoS); u=U(:,1); v=V(:,1); sigma=S(1,1);
p0=params; p0.H_SI=Hd; p0.H_SI_matrix=Hd;
tx0=generate_mimo_ofdm_waveform(p0); Hc=tx0.H(:,:,1);
rx0=simulate_radar_channel_3d(tx0.X,p0); pow0=mean(abs(rx0(:)).^2);
Wd=design_precoder(Hc,Hd,params.precoder_type); leakd=norm(Hd*Wd,'fro')^2;
Nris=128; b=ones(Nris,1)/sqrt(Nris); A=u*b'; B=b*v';
M=64; phi=2*pi*(0:M-1)/M;
rhos=[0.1 0.3 0.5 1.0];
fprintf('==== kappa=10, rank-1 RIS aligned to LoS ====\n');
fprintf('%6s %14s %14s\n','rho','matrix_dB','e2e_dB');
for r=1:numel(rhos)
    rho=rhos(r); scale=sigma*rho; H_RIS=@(theta) scale*(A*diag(exp(1j*theta))*B);
    best=inf; best_theta=[];
    for i=1:M
        theta=phi(i)*ones(Nris,1); Ht=Hd+H_RIS(theta);
        W=design_precoder(Hc,Ht,params.precoder_type); leak=norm(Ht*W,'fro')^2;
        if leak<best, best=leak; best_theta=theta; end
    end
    imp_mat=10*log10(leakd/best);
    p=params; p.H_SI=Hd+H_RIS(best_theta); p.H_SI_matrix=p.H_SI;
    tx=generate_mimo_ofdm_waveform(p); rx=simulate_radar_channel_3d(tx.X,p);
    pow1=mean(abs(rx(:)).^2); imp_e2e=10*log10(pow0/pow1);
    fprintf('%6.2f %14.2f %14.2f\n',rho,imp_mat,imp_e2e);
end
end
