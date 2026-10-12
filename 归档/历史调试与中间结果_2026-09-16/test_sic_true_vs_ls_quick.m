function test_sic_true_vs_ls_quick()
clear; close all; clc; warning('off','all');
methods = {'lagrange','lagrange','lagrange'};
sic_flags = [false, true, true];
true_flags = [false, false, true];
labels = {'Lagrange', 'Lagrange+LS SIC', 'Lagrange+True SIC'};
snr_list = [-20, 0, 20];
n_mc=5; beta=10; N_val=512; L_val=64; Mx=4; My=4;

base=build_default_params();
base.theta_true=[24.63,15.94]; base.phi_true=[30.99,13.58]; base.R_true=[200.6,210.4];
base.v_true=[15.1,-5.4]; base.alpha=[1,0.8]; base.enable_SI=true; base.beta_SI=beta;
base.enable_SIC=false; base.SIC_pilot_len=64; base.K=L_val; base.K_stream=2;
base.Mx=Mx; base.My=My; base.N=N_val; base.B=N_val*120e3;
base.joint_fft_3d.Na_x=Mx; base.joint_fft_3d.Na_y=My; base.joint_fft_3d.Nr=N_val;
base.joint_fft_3d.Nv=L_val; base.fast_estimator.n_samp_l=min(32,max(8,floor(L_val/2)));
base.fast_estimator.n_pad_v=L_val;
base.user_theta_rad=deg2rad(base.theta_true(:)); base.user_phi_rad=deg2rad(base.phi_true(:));
Nt=base.Ntx*base.Nty; Nr=Mx*My;
rng(20260730); hsi_tx=struct('model','ura_rician','Nt_total',Nt,'Nr_total',64,'kappa_SI',10,'Ntx',base.Ntx,'Nty',base.Nty,'Mx',8,'My',8,'d_lambda',0.5,'theta_tx_deg',base.theta_SI,'phi_tx_deg',base.phi_SI,'theta_rx_deg',base.theta_SI,'phi_rx_deg',base.phi_SI); H_common=generate_HSI(hsi_tx);
rng(20260731); hsi_rx=struct('model','ura_rician','Nt_total',Nt,'Nr_total',Nr,'kappa_SI',10,'Ntx',base.Ntx,'Nty',base.Nty,'Mx',Mx,'My',My,'d_lambda',0.5,'theta_tx_deg',base.theta_SI,'phi_tx_deg',base.phi_SI,'theta_rx_deg',base.theta_SI,'phi_rx_deg',base.phi_SI); H_rx=generate_HSI(hsi_rx);
rng(20260801); seeds=randi(2^31-1,3,numel(snr_list),n_mc);
rmse=NaN(3,numel(snr_list),n_mc);
for mi=1:3
 p_tx=base; p_tx.precoder_type='lagrange'; p_tx.H_SI=H_common; p_tx.H_SI_matrix=H_rx;
 tx=generate_mimo_ofdm_waveform(p_tx); X=tx.X; clear tx;
 for si=1:numel(snr_list)
  p=p_tx; p.SNR=snr_list(si); p.enable_SI=true; p.enable_SIC=sic_flags(mi); p.H_SI_matrix=H_rx; p.beta_SI=beta;
  if true_flags(mi), p.sic_use_true_channel=true; else, p.sic_use_true_channel=false; end
  for mc=1:n_mc
   rng(seeds(mi,si,mc)); rx=simulate_radar_channel_3d(X,p); [th,ph,R,v,~]=joint_estimator_fast(rx,X,p); cmp=evaluate_estimation(th,ph,R,v,p,false);
   if isfield(cmp,'rmse_theta') && ~isnan(cmp.rmse_theta), rmse(mi,si,mc)=cmp.rmse_theta; end
   clear rx th ph R v cmp;
  end
 end
 fprintf('%s done\n', labels{mi});
end
med=median(rmse,3,'omitnan');
fprintf('Angle RMSE median:\n');
for si=1:numel(snr_list), fprintf('SNR %+d: %s\n', snr_list(si), sprintf('%.4f  ', med(:,si))); end
save('test_sic_true_vs_ls_quick_results.mat','snr_list','labels','med','rmse');
end
