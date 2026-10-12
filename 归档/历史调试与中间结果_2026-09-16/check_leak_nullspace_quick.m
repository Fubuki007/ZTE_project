function check_leak_nullspace_quick()
clear; clc; warning('off','all');
base=build_default_params();
base.theta_true=[24.63,15.94]; base.phi_true=[30.99,13.58]; base.R_true=[200.6,210.4];
base.v_true=[15.1,-5.4]; base.alpha=[1,0.8]; base.enable_SI=true; base.beta_SI=10;
base.enable_SIC=false; base.K=256; base.K_stream=2;
base.Mx=4; base.My=4; base.joint_fft_3d.Na_x=4; base.joint_fft_3d.Na_y=4;
base.fast_estimator.n_samp_l=64; base.SNR=0;
Nt=base.Ntx*base.Nty; Nr=16; Ns=base.N; L=base.K;
rng(20260730); cfg_common=struct('model','ura_rician','Nt_total',Nt,'Nr_total',64,'kappa_SI',10,'Ntx',base.Ntx,'Nty',base.Nty,'Mx',8,'My',8,'d_lambda',0.5,'theta_tx_deg',base.theta_SI,'phi_tx_deg',base.phi_SI,'theta_rx_deg',base.theta_SI,'phi_rx_deg',base.phi_SI); Hc=generate_HSI(cfg_common);
rng(20260731); cfg_rx=struct('model','ura_rician','Nt_total',Nt,'Nr_total',Nr,'kappa_SI',10,'Ntx',base.Ntx,'Nty',base.Nty,'Mx',4,'My',4,'d_lambda',0.5,'theta_tx_deg',base.theta_SI,'phi_tx_deg',base.phi_SI,'theta_rx_deg',base.theta_SI,'phi_rx_deg',base.phi_SI); Hrx=generate_HSI(cfg_rx);
for hi=1:2
 if hi==1, Hdesign=Hc; tag='design=64xNt'; else, Hdesign=Hrx; tag='design=16xNt'; end
 for mi=1:3
  if mi==1, method='zf'; elseif mi==2, method='nullspace'; else method='lagrange'; end
  p=base; p.precoder_type=method; p.H_SI=Hdesign; p.H_SI_matrix=Hrx;
  tx=generate_mimo_ofdm_waveform(p); W=tx.W; X=tx.X;
  leak=0;
  for i=1:Ns
    leak=leak+norm(Hrx*W(:,:,i),'fro')^2;
  end
  leak=leak/Ns;
  fprintf('%-14s method=%-10s  ||Hrx*W||^2_avg=%.4g  (%.1f dB rel ZF?)\n', tag, method, leak, 10*log10(leak));
 end
end
end
