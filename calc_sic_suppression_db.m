function calc_sic_suppression_db()
clear; clc; warning('off','all');
base = build_default_params();
base.theta_true=[24.63,15.94]; base.phi_true=[30.99,13.58]; base.R_true=[200.6,210.4];
base.v_true=[15.1,-5.4]; base.alpha=[1,0.8]; base.K=64; base.K_stream=2;
base.Mx=4; base.My=4; base.N=512; base.B=512*120e3;
base.joint_fft_3d.Na_x=4; base.joint_fft_3d.Na_y=4; base.joint_fft_3d.Nr=512; base.joint_fft_3d.Nv=64;
base.fast_estimator.n_samp_l=32; base.fast_estimator.n_pad_v=64;
base.user_theta_rad=deg2rad(base.theta_true(:)); base.user_phi_rad=deg2rad(base.phi_true(:));
Nt=base.Ntx*base.Nty; Nr=16; L=size(base.theta_true(:),1); % just placeholder
Nt_total=base.Ntx*base.Nty;
rng(20260730); hsi_tx=struct('model','ura_rician','Nt_total',Nt_total,'Nr_total',64,'kappa_SI',10,'Ntx',base.Ntx,'Nty',base.Nty,'Mx',8,'My',8,'d_lambda',0.5,'theta_tx_deg',base.theta_SI,'phi_tx_deg',base.phi_SI,'theta_rx_deg',base.theta_SI,'phi_rx_deg',base.phi_SI); H_common=generate_HSI(hsi_tx);
rng(20260731); hsi_rx=struct('model','ura_rician','Nt_total',Nt_total,'Nr_total',16,'kappa_SI',10,'Ntx',base.Ntx,'Nty',base.Nty,'Mx',4,'My',4,'d_lambda',0.5,'theta_tx_deg',base.theta_SI,'phi_tx_deg',base.phi_SI,'theta_rx_deg',base.theta_SI,'phi_rx_deg',base.phi_SI); H_rx=generate_HSI(hsi_rx);
beta=10;
p=base; p.precoder_type='lagrange'; p.H_SI=H_common;
tx=generate_mimo_ofdm_waveform(p); X=tx.X;
Ns=size(X,3); Lsym=size(X,4);
% target power for noise std
p.enable_SI=false; rx=simulate_radar_channel_3d(X,p); target_pow=mean(abs(rx(:)).^2);
clear rx;
for snr_db=[-20,0,20,40]
 noise_std=sqrt(target_pow/10^(snr_db/10)/2);
 for Lp=[64,128,256]
   rng(12345);
   pilot_idx=randi([0 15], Nt_total, Lp); X0=qammod(pilot_idx,16,'UnitAveragePower',true);
   Y0=beta*(H_rx*X0)+noise_std*(randn(16,Lp)+1j*randn(16,Lp));
   Ghat=Y0*X0'/(X0*X0');
   before=0; after=0;
   for l=1:Lsym
     x_l=reshape(X(:,:,:,l),Nt_total,Ns);
     y_si=beta*H_rx*x_l;
     y_res=(beta*H_rx-Ghat)*x_l;
     before=before+sum(abs(y_si(:)).^2);
     after=after+sum(abs(y_res(:)).^2);
   end
   before=before/(16*Ns*Lsym); after=after/(16*Ns*Lsym);
   fprintf('SNR=%+d dB, Lp=%d, suppression=%.1f dB\n', snr_db, Lp, 10*log10(before/max(after,eps)));
 end
end
end
