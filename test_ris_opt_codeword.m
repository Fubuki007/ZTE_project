function test_ris_opt_codeword()
clear; clc; warning('off','all');
rng(20260928);
params = build_default_params();
params.Mx=8; params.My=8; params.Ntx=4; params.Nty=4;
params.N=256; params.B=params.N*120e3; params.K=32; params.K_stream=2;
params.num_targets=0; params.enable_SI=true; params.beta_SI=100; params.enable_SIC=false;
params.user_theta_rad=deg2rad([24.63;15.94]); params.user_phi_rad=deg2rad([30.99;13.58]);
Nt=params.Ntx*params.Nty; Nr=params.Mx*params.My;
cfg=struct('model','ura_rician','Nt_total',Nt,'Nr_total',Nr,'kappa_SI',10, ...
 'Ntx',params.Ntx,'Nty',params.Nty,'Mx',params.Mx,'My',params.My,'d_lambda',0.5, ...
 'theta_tx_deg',params.theta_SI,'phi_tx_deg',params.phi_SI, ...
 'theta_rx_deg',params.theta_SI,'phi_rx_deg',params.phi_SI);
Hd=generate_HSI(cfg);
p0=params; p0.precoder_type='zf'; p0.H_SI=Hd; p0.H_SI_matrix=Hd;
tx0=generate_mimo_ofdm_waveform(p0); Hc=tx0.H(:,:,1);
Nris=128; rho=0.5;
A=(randn(Nr,Nris)+1j*randn(Nr,Nris))/sqrt(2);
B=(randn(Nris,Nt)+1j*randn(Nris,Nt))/sqrt(2);
H0=A*B; scale=sqrt(Nt*Nr*rho^2/(norm(H0,'fro')^2+eps));
C=zeros(Nr,Nt,Nris);
for n=1:Nris, C(:,:,n)=scale*A(:,n)*B(n,:); end
H_RIS=@(theta) scale*(A*diag(exp(1j*theta))*B);
% coordinate descent: min ||Hd + sum theta_n C_n||_F^2
theta=exp(1j*2*pi*rand(Nris,1));
for it=1:20
    Hcur=Hd+H_RIS(theta);
    for n=1:Nris
        R=Hcur-C(:,:,n)*theta(n);
        z=trace(C(:,:,n)'*R);
        if abs(z)>eps
            theta(n)=-z/abs(z);
        end
        Hcur=Hd+H_RIS(theta);
    end
    fval=norm(Hcur,'fro')^2;
end
fprintf('Direct ||Hd||_F^2 = %.6g\n', norm(Hd,'fro')^2);
fprintf('Optimized ||Hd+H_RIS||_F^2 = %.6g, ratio=%.2f dB\n', fval, 10*log10(norm(Hd,'fro')^2/fval));
% compare after precoding
for method={'zf','nullspace'}
    m=method{1};
    Wd=design_precoder(Hc,Hd,m); leakd=norm(Hd*Wd,'fro')^2;
    W1=design_precoder(Hc,Hd+H_RIS(theta),m); leak1=norm((Hd+H_RIS(theta))*W1,'fro')^2;
    % best random codebook
    M=1024; Theta=exp(1j*2*pi*rand(Nris,M)); best=inf;
    for i=1:M
        Ht=Hd+H_RIS(Theta(:,i)); Wi=design_precoder(Hc,Ht,m); li=norm(Ht*Wi,'fro')^2;
        if li<best, best=li; end
    end
    fprintf('method=%s: no RIS %.6g, optimized %.6g (%.2f dB), random best %.6g (%.2f dB)\n', ...
        m, leakd, leak1, 10*log10(leakd/leak1), best, 10*log10(leakd/best));
end
end
