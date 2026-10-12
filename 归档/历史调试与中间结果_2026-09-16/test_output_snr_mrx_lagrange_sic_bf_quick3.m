% quick3: Ns=1024, L=128, MC=3, Mrx-matched H_SI, BF output SNR
function test_output_snr_mrx_lagrange_sic_bf_quick3()
clear; close all; clc; warning('off','all'); t_all=tic;
methods={'zf','lagrange','lagrange'}; sic_flags=[false,false,true];
labels={'ZF','Lagrange','Lagrange + digital SIC'}; nm=numel(methods);
M_list=[2,4,6,8]; Mrx_list=M_list.^2; nmrx=numel(Mrx_list);
N_val=1024; L_val=128; n_mc=3; beta=10; input_snr=0;
fprintf('=== Quick BF test v3: Ns=%d L=%d MC=%d ===\n',N_val,L_val,n_mc);
base=build_default_params();
base.theta_true=[24.63,15.94]; base.phi_true=[30.99,13.58]; base.R_true=[200.6,210.4];
base.v_true=[15.1,-5.4]; base.alpha=[1,0.8]; base.enable_SI=true; base.beta_SI=beta;
base.enable_SIC=false; base.sic_use_true_channel=false; base.SIC_pilot_len=128;
base.SNR=input_snr; base.K_stream=2; base.user_theta_rad=deg2rad(base.theta_true(:));
base.user_phi_rad=deg2rad(base.phi_true(:)); base.N=N_val; base.B=N_val*120e3; base.K=L_val;
base.meta.range_resolution=base.c/(2*base.B); base.fast_estimator.n_samp_l=min(32,max(8,floor(L_val/2)));
base.fast_estimator.n_pad_v=L_val; Nt=base.Ntx*base.Nty;
rng(20260801); seeds=randi(2^31-1,nm,nmrx,n_mc);
snr=NaN(nm,nmrx,n_mc);
for mi=1:nm
 for mi_mrx=1:nmrx
  Mv=M_list(mi_mrx); Mrxv=Mrx_list(mi_mrx);
  rng(2026000+mi_mrx);
  cfg=struct('model','ura_rician','Nt_total',Nt,'Nr_total',Mrxv,'kappa_SI',10,'Ntx',base.Ntx,'Nty',base.Nty,'Mx',Mv,'My',Mv,'d_lambda',0.5,'theta_tx_deg',base.theta_SI,'phi_tx_deg',base.phi_SI,'theta_rx_deg',base.theta_SI,'phi_rx_deg',base.phi_SI,'seed',2026000+mi_mrx);
  H=generate_HSI(cfg);
  p=base; p.precoder_type=methods{mi}; p.H_SI=H; p.H_SI_matrix=H; p.Mx=Mv; p.My=Mv;
  p.joint_fft_3d.Na_x=Mv; p.joint_fft_3d.Na_y=Mv;
  tx=generate_mimo_ofdm_waveform(p); X=tx.X; clear tx;
  for mc=1:n_mc
   rng(seeds(mi,mi_mrx,mc)); rx=simulate_radar_channel_3d(X,p);
   snr(mi,mi_mrx,mc)=bf_snr(rx,X,p); clear rx;
  end
  fprintf('  %-28s Mrx=%3d -> %.2f dB\n',labels{mi},Mrxv,mean(snr(mi,mi_mrx,:),'omitnan'));
  clear X;
 end
end
avg=squeeze(mean(snr,3,'omitnan'));
fprintf('\n=== Summary ===\n');
fprintf('%8s %12s %12s %16s\n','Mrx','ZF','Lagrange','Lagrange+SIC');
for i=1:nmrx
 fprintf('%8d %12.2f %12.2f %16.2f\n',Mrx_list(i),avg(1,i),avg(2,i),avg(3,i));
end
fprintf('time %.1f s\n',toc(t_all));
save('test_output_snr_mrx_lagrange_sic_bf_quick3.mat','Mrx_list','methods','labels','snr','avg');
end
function snrDb=bf_snr(rx_cube,tx_signal,params)
[Mx,My,Ns,L]=size(rx_cube); Q=params.num_targets; kw=2*pi*params.d/params.lambda;
mx=(0:Mx-1).'; my=(0:My-1).';
if ismatrix(tx_signal)&&isequal(size(tx_signal),[Ns,L])
 txNorm=tx_signal./max(max(abs(tx_signal(:))),eps);
else
 txSum=squeeze(sum(sum(tx_signal,1),2)); txNorm=txSum./max(max(abs(txSum(:))),eps);
end
maps=zeros(Ns,L,Q);
for q=1:Q
 u=sind(params.theta_true(q))*cosd(params.phi_true(q)); v=sind(params.theta_true(q))*sind(params.phi_true(q));
 bx=exp(-1j*kw*mx*u); by=exp(-1j*kw*my*v); b=bx*by.'; b=b(:);
 rx_bf=squeeze(sum(conj(b).*reshape(rx_cube,Mx*My,Ns,L),1));
 rxEq=rx_bf.*conj(reshape(txNorm,Ns,L));
 rd=fft(rxEq,Ns,1); rd=fftshift(fft(rd,L,2),2); maps(:,:,q)=abs(rd).^2;
end
bad=false(size(maps));
if isfield(params,'fast_estimator')&&isfield(params.fast_estimator,'R_min_gate')
 Rg=params.fast_estimator.R_min_gate; if mod(Ns,2)==0, cidx=Ns/2+1; else cidx=(Ns+1)/2; end
 if isfield(params,'meta')&&isfield(params.meta,'delta_f'), df=params.meta.delta_f; else df=params.B/Ns; end
 gh=ceil(Rg*2*df*Ns/params.c); ridx=max(1,cidx-gh):min(Ns,cidx+gh); bad(ridx,:,:)=true; maps(bad)=0;
end
npeaks=max(1,min(Q,numel(maps))); [pv,pi_]=maxk(maps(:),npeaks);
mask=false(size(maps)); GR=2; GV=2;
for k=1:numel(pi_)
 [ir,iv,iq]=ind2sub(size(maps),pi_(k)); mask(max(1,ir-GR):min(Ns,ir+GR),max(1,iv-GV):min(L,iv+GV),iq)=true;
end
bg=maps(~mask & ~bad); floor=median(bg(:),'omitnan');
snrDb=10*log10(mean(pv,'omitnan')/max(floor,eps));
end
