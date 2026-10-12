function diagnose_admm()
root=fileparts(mfilename('fullpath'));
addpath(root); addpath(fullfile(root,'..')); addpath(fullfile(root,'..','RIS_SIC_Wu2024_验证'));
rng(20240920,'twister');
p=zte_ris_mimo_params();
p.N_ris=144; p.Nx_ris=12; p.Ny_ris=12;
p.d_sep_wl=1.5; p.x_c_wl=1.5; p.d_sep=p.d_sep_wl*p.lambda; p.x_c=p.x_c_wl*p.lambda;
p.M=64; p.rcg.n_restarts=4; p.rcg.max_iter=1000;
ch=generate_ris_mimo_channels(p);
p_tx=p; p_tx.N=p.M; p_tx.K=8; p_tx.K_stream=1; p_tx.precoder_type='zf';
p_tx.user_theta_rad=deg2rad(p.theta_true(1)); p_tx.user_phi_rad=deg2rad(p.phi_true(1));
if isfield(p_tx,'H_SI'), p_tx=rmfield(p_tx,'H_SI'); end
if isfield(p_tx,'H_SI_per_cc'), p_tx=rmfield(p_tx,'H_SI_per_cc'); end
tx=generate_mimo_ofdm_waveform(p_tx); W=tx.W;
[a,h_r,info]=build_mimo_ris_objective(ch,W); B=info.B_all; direct=mean(abs(a).^2);

t=tic; [phi_admm,info_admm]=solve_ideal_amplitude_admm(a,B,struct('max_iter',2000,'tol',1e-10)); dt=toc(t);
res_admm=mean(abs(a+B.'*phi_admm).^2);
fprintf('ADMM ideal: supp=%.2f dB, max|phi|=%.3f, iter=%d, %.1fs\n',10*log10(direct/res_admm),max(abs(phi_admm)),info_admm.num_iter,dt);

phi_init=exp(1j*angle(phi_admm));
[phi_rcg,info_rcg]=rcg_phase_optimize(a,h_r,ones(numel(a),1),p,phi_init);
res_rcg=mean(abs(a+B.'*phi_rcg).^2);
fprintf('RCG from ADMM phase: supp=%.2f dB, iter=%d\n',10*log10(direct/res_rcg),info_rcg.num_iter);
end
