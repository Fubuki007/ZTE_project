function prepared = ris_beta_prepare(cfg, root, prefix)
% Cache the deterministic geometry and RIS phase, preserving the MC seeds.
path = fullfile(root,[prefix '_prepared.mat']);
if isfile(path)
    prepared = load(path);
    assert(isequaln(prepared.config,cfg),'RIS:InvalidCheckpoint','Configuration mismatch: geometry cache.');
    assert(numel(prepared.phi_cont)==64 && all(isfinite(prepared.phi_cont)));
    return;
end
p = build_default_params();
p.enable_SI = true; p.beta_SI = cfg.beta_list(1); p.enable_SIC = false;
p.sic_use_true_channel = false; p.SIC_pilot_len = cfg.sic_pilot_len;
p.SIC_pilot = []; p.sic_error_db = []; p.precoder_type = 'zf';
p.K_stream = 1; p.K = 256;
p.fast_estimator.R_min_gate = 20; p.fast_estimator.R_max_gate = 600;
p.ris = struct('enable',true,'N_ris',64,'Nx',8,'Ny',8, ...
    'd_sep',1.5*p.lambda,'eta',0.8,'target_weights',p.alpha(:).^2, ...
    'max_sweeps',12,'randomize_order',false);
hcfg = struct('model','ura_rician','Nt_total',p.Ntx*p.Nty,'Nr_total',p.Mx*p.My, ...
    'kappa_SI',10,'Ntx',p.Ntx,'Nty',p.Nty,'Mx',p.Mx,'My',p.My, ...
    'd_lambda',0.5,'theta_tx_deg',p.theta_SI,'phi_tx_deg',p.phi_SI, ...
    'theta_rx_deg',p.theta_SI,'phi_rx_deg',p.phi_SI);
rng(2026100201,'twister');
p.H_SI = generate_HSI(hcfg); p.H_SI_matrix = p.H_SI;
rng(2026100202,'twister');
tx = generate_mimo_ofdm_waveform(p);
model = build_ris_target_model(p,tx,zeros(p.ris.N_ris,1));
[phi, opt] = optimize_ris_target_phase(model,p,Inf,ones(p.ris.N_ris,1));
% Avoid saving the optimizer's redundant matrices a second time.
gain_db = opt.gain_db;
prepared = struct('config',cfg,'params',p,'hsi_cfg',hcfg, ...
    'model_template',model,'phi_cont',phi,'target_gain_db',gain_db);
ris_sic_save_atomic(path,prepared);
fprintf('GEOMETRY_CACHE_SAVED target_gain_db=%.9g\n',gain_db);
end
