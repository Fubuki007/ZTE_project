% profile_execution_breakdown.m
% 端到端时间拆解：波形生成 / 回波仿真(SI+SIC) / 估计器
function profile_execution_breakdown()
warning('off','all');

cases = { ...
    'ZF, Ns=3168, L=256',       'zf',       3168, 256; ...
    'Null-space+SIC, Ns=3168,L=256','nullspace', 3168, 256; ...
    'ZF, Ns=6336, L=64',        'zf',       6336, 64; ...
    'Null-space+SIC, Ns=6336,L=64','nullspace', 6336, 64 };

base = build_default_params();
base.theta_true=[24.63,15.94]; base.phi_true=[30.99,13.58]; base.R_true=[200.6,210.4];
base.v_true=[15.1,-5.4]; base.alpha=[1,0.8]; base.enable_SI=true; base.beta_SI=10;
base.enable_SIC=false; base.sic_use_true_channel=false; base.SIC_pilot_len=128;
base.SNR=0; base.K_stream=2; base.user_theta_rad=deg2rad(base.theta_true(:));
base.user_phi_rad=deg2rad(base.phi_true(:)); base.Mx=4; base.My=4;
base.joint_fft_3d.Na_x=4; base.joint_fft_3d.Na_y=4; base.fast_estimator.R_max_gate=600;
Nt=base.Ntx*base.Nty; Nr=16;
rng(20260731); H=generate_HSI(struct('model','ura_rician','Nt_total',Nt,'Nr_total',Nr,'kappa_SI',10,'Ntx',base.Ntx,'Nty',base.Nty,'Mx',4,'My',4,'d_lambda',0.5,'theta_tx_deg',base.theta_SI,'phi_tx_deg',base.phi_SI,'theta_rx_deg',base.theta_SI,'phi_rx_deg',base.phi_SI,'seed',20260731));

fprintf('%-35s %12s %12s %12s %12s\n','case','gen(s)','sim(s)','est(s)','total(s)');
for ci=1:size(cases,1)
    label=cases{ci,1}; method=cases{ci,2}; Ns=cases{ci,3}; Lv=cases{ci,4};
    p=base; p.precoder_type=method; p.N=Ns; p.B=Ns*120e3; p.K=Lv;
    p.meta.range_resolution=p.c/(2*p.B); p.joint_fft_3d.Nr=Ns; p.joint_fft_3d.Nv=Lv;
    p.fast_estimator.n_samp_l=min(64,max(8,floor(Lv/2))); p.H_SI=H; p.H_SI_matrix=H;
    if strcmp(method,'nullspace'), p.enable_SIC=true; end
    rng(20260801);
    tic; tx=generate_mimo_ofdm_waveform(p); tg=toc;
    X=tx.X; clear tx;
    tic; rx=simulate_radar_channel_3d(X,p); ts=toc;
    tic; joint_estimator_fast(rx,X,p); te=toc;
    fprintf('%-35s %12.4f %12.4f %12.4f %12.4f\n', label, tg, ts, te, tg+ts+te);
    clear X rx;
end
end
