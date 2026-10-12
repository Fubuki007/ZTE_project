function run_mimo_ris_targetbeam_simple()
root=fileparts(mfilename('fullpath'));
addpath(root); addpath(fullfile(root,'..')); addpath(fullfile(root,'..','RIS_SIC_Wu2024_验证'));
rng(20240920,'twister');
p=zte_ris_mimo_params();
p.N_ris=144; p.Nx_ris=12; p.Ny_ris=12;
p.d_sep_wl=1.5; p.x_c_wl=1.5; p.d_sep=p.d_sep_wl*p.lambda; p.x_c=p.x_c_wl*p.lambda;
p.M=64; p.rcg.n_restarts=8; p.rcg.max_iter=1200; p.codebook.cd_sweeps=12;
ch=generate_ris_mimo_channels(p);
p_tx=p; p_tx.N=p.M; p_tx.K=8; p_tx.K_stream=1; p_tx.precoder_type='zf';
p_tx.user_theta_rad=deg2rad(p.theta_true(1)); p_tx.user_phi_rad=deg2rad(p.phi_true(1));
if isfield(p_tx,'H_SI'), p_tx=rmfield(p_tx,'H_SI'); end
if isfield(p_tx,'H_SI_per_cc'), p_tx=rmfield(p_tx,'H_SI_per_cc'); end
tx=generate_mimo_ofdm_waveform(p_tx); W=tx.W;
[a_all,h_r_all,info]=build_mimo_ris_objective(ch,W); B_all=info.B_all;
Nr=ch.Nr; M=p.M; N=p.N_ris;
theta=p.theta_true(1); phi=p.phi_true(1); kw=2*pi*p.d/p.lambda;
mx=(0:p.Mx-1).'; my=(0:p.My-1).';
u=sin(theta*pi/180)*cos(phi*pi/180); v=sin(theta*pi/180)*sin(phi*pi/180);
uvec=(exp(-1j*kw*mx*u)*exp(-1j*kw*my*v).'); uvec=uvec(:); uvec=uvec/norm(uvec);
HdW=zeros(Nr,M); for m=1:M, HdW(:,m)=ch.H_direct(:,:,m)*W(:,:,m); end
a_beam=(uvec'*HdW).'; a_beam=a_beam(:);
B_beam=zeros(N,M);
for m=1:M
  Wm=W(:,:,m);
  for n=1:N
    contrib=ch.G_rx(:,n,m)*(ch.G_tx(n,:,m)*Wm);
    B_beam(n,m)=uvec'*contrib;
  end
end
names={}; phis={}; notes={};
names{end+1}='No RIS'; phis{end+1}=zeros(N,1); notes{end+1}='off';
phi_rand=exp(1j*2*pi*rand(N,1)); names{end+1}='Random phase'; phis{end+1}=phi_rand; notes{end+1}='random';
[phi_rcg,info_rcg]=rcg_phase_optimize(a_beam,conj(B_beam),ones(M,1),p); names{end+1}='RCG continuous'; phis{end+1}=phi_rcg; notes{end+1}=sprintf('iter=%d',info_rcg.num_iter);
opt=p; opt.weights=ones(M,1);
for tau=p.tau_list
  phi_npp=phase_quantize_npp(phi_rcg,tau);
  names{end+1}=sprintf('NPP tau=%d',tau); phis{end+1}=phi_npp; notes{end+1}='npp';
  [phi_cd,info_cd]=codebook_coordinate_descent(a_beam,conj(B_beam),tau,phi_npp,opt);
  names{end+1}=sprintf('Codebook CD tau=%d',tau); phis{end+1}=phi_cd; notes{end+1}=sprintf('sweeps=%d',info_cd.sweeps);
end
n=numel(names); res=struct();
fprintf('%-30s %12s %12s %10s\n','Method','BeamSupp','TotalSupp','max|phi|');
for i=1:n
  ph=phis{i};
  rb=mean(abs(a_beam+B_beam.'*ph).^2); rt=mean(abs(a_all+B_all.'*ph).^2);
  bs=10*log10(mean(abs(a_beam).^2)/max(rb,eps)); ts=10*log10(mean(abs(a_all).^2)/max(rt,eps));
  res(i).name=names{i}; res(i).note=notes{i}; res(i).beam_supp_db=bs; res(i).total_supp_db=ts; res(i).max_abs_phi=max(abs(ph)); res(i).phi=ph;
  fprintf('%-30s %12.2f %12.2f %10.3f\n',names{i},bs,ts,max(abs(ph)));
end
out=struct('params',p,'results',res,'info_rcg',info_rcg,'a_beam',a_beam,'B_beam',B_beam,'B_all',B_all);
save(fullfile(root,'zte_mimo_ris_targetbeam.mat'),'-struct','out','-v7.3');
T=struct2table(rmfield(res,'phi'));
writetable(T,fullfile(root,'zte_mimo_ris_targetbeam.csv'));
fprintf('saved zte_mimo_ris_targetbeam.csv\n');
end

