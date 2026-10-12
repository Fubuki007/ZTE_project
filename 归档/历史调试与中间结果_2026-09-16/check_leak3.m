function check_leak3()
clear; clc; warning('off','all');
base=build_default_params();
base.theta_true=[24.63,15.94]; base.phi_true=[30.99,13.58]; base.R_true=[200.6,210.4];
base.v_true=[15.1,-5.4]; base.alpha=[1,0.8]; base.K=256; base.K_stream=2;
base.user_theta_rad=deg2rad(base.theta_true(:)); base.user_phi_rad=deg2rad(base.phi_true(:));
base.Mx=4; base.My=4; base.joint_fft_3d.Na_x=4; base.joint_fft_3d.Na_y=4; base.fast_estimator.n_samp_l=64;
Nt=base.Ntx*base.Nty;
rng(20260730); cfgc=struct('model','ura_rician','Nt_total',Nt,'Nr_total',64,'kappa_SI',10,'Ntx',base.Ntx,'Nty',base.Nty,'Mx',8,'My',8,'d_lambda',0.5,'theta_tx_deg',base.theta_SI,'phi_tx_deg',base.phi_SI,'theta_rx_deg',base.theta_SI,'phi_rx_deg',base.phi_SI); Hc=generate_HSI(cfgc);
rng(20260731); cfgr=struct('model','ura_rician','Nt_total',Nt,'Nr_total',16,'kappa_SI',10,'Ntx',base.Ntx,'Nty',base.Nty,'Mx',4,'My',4,'d_lambda',0.5,'theta_tx_deg',base.theta_SI,'phi_tx_deg',base.phi_SI,'theta_rx_deg',base.theta_SI,'phi_rx_deg',base.phi_SI); Hr=generate_HSI(cfgr);
for meth={'zf','nullspace','lagrange'}
 for hi=1:2
  if hi==1, hd=Hc; else, hd=Hr; end
  p=base; p.precoder_type=meth{1}; p.H_SI=hd; tx=generate_mimo_ofdm_waveform(p); W=tx.W;
  s=0; for i=1:size(W,3), A=Hr*W(:,:,i); s=s+sum(abs(A(:)).^2); end; s=s/size(W,3);
  fprintf('%-10s design=%s  actual ||Hrx*W||^2_avg = %.6g\n', meth{1}, mat2str(size(hd)), s);
 end
end
end
