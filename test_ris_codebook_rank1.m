function test_ris_codebook_rank1()
clear; clc; warning('off','all');
rng(20260928);
params = build_default_params();
params.Mx=8; params.My=8; params.Ntx=4; params.Nty=4;
params.N=256; params.B=params.N*120e3; params.K=32; params.K_stream=2;
params.num_targets=0; params.enable_SI=true; params.beta_SI=100; params.enable_SIC=false;
params.user_theta_rad=deg2rad([24.63;15.94]); params.user_phi_rad=deg2rad([30.99;13.58]);
Nt=params.Ntx*params.Nty; Nr=params.Mx*params.My;
cfg=struct('model','ura_rician','Nt_total',Nt,'Nr_total',Nr,'kappa_SI',1e6, ...
 'Ntx',params.Ntx,'Nty',params.Nty,'Mx',params.Mx,'My',params.My,'d_lambda',0.5, ...
 'theta_tx_deg',params.theta_SI,'phi_tx_deg',params.phi_SI, ...
 'theta_rx_deg',params.theta_SI,'phi_rx_deg',params.phi_SI);
[Hd, info] = generate_HSI(cfg);
Hlos = info.H_LoS;
[U,S,V] = svd(Hlos);
u = U(:,1); v = V(:,1); sigma = S(1,1);
% communication channel
p0=params; p0.precoder_type='zf'; p0.H_SI=Hd; p0.H_SI_matrix=Hd;
tx0=generate_mimo_ofdm_waveform(p0); Hc=tx0.H(:,:,1);
% rank-1 RIS path aligned with direct LoS
Nris=128; rho=1.0;
b_ris = ones(Nris,1)/sqrt(Nris);
A = u * b_ris';
B = b_ris * v';
scale = sigma * rho;
H_RIS = @(theta) scale*(A*diag(exp(1j*theta))*B);
% codebook: constant phase over all elements
M=64; phi=2*pi*(0:M-1)/M;
methods={'zf','nullspace'};
fprintf('==== RIS rank-1 codebook test ====\n');
fprintf('Nt=%d, Nr=%d, Nris=%d, rho=%.2f, M=%d\n',Nt,Nr,Nris,rho,M);
for mi=1:numel(methods)
    m=methods{mi};
    Wd=design_precoder(Hc,Hd,m); leakd=norm(Hd*Wd,'fro')^2;
    best=inf; best_i=0;
    for i=1:M
        theta=phi(i)*ones(Nris,1);
        Ht=Hd+H_RIS(theta);
        W=design_precoder(Hc,Ht,m);
        leak=norm(Ht*W,'fro')^2;
        if leak<best, best=leak; best_i=i; end
    end
    imp=10*log10(leakd/best);
    fprintf('method=%s: direct=%.6g, best RIS=%.6g (phase=%.1f deg), improvement=%.2f dB\n', ...
        m, leakd, best, rad2deg(phi(best_i)), imp);
end
end
