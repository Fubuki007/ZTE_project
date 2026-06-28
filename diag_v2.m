rng(42);
params = build_default_params();
params.K = 256; params.K_stream = 4;
params.comm_channel_type = 'random';
params.enable_SI = true; params.beta_SI = 0.02; params.SNR = 10;
params.fast_estimator.n_pad_v = 256;
params.precoder_type = 'lagrange';

Nt_total = params.Ntx * params.Nty; Nr_total = params.Mx * params.My;
hsi_cfg = struct('model','ura_rician','Nt_total',Nt_total,'Nr_total',Nr_total,...
    'kappa_SI',100,'Ntx',params.Ntx,'Nty',params.Nty,...
    'Mx',params.Mx,'My',params.My,'d_lambda',0.5,...
    'theta_tx_deg',params.theta_SI,'phi_tx_deg',params.phi_SI,...
    'theta_rx_deg',params.theta_SI,'phi_rx_deg',params.phi_SI,'seed',42);
H_SI = generate_HSI(hsi_cfg);
H_SI = H_SI / norm(H_SI,'fro') * sqrt(Nt_total*Nr_total);

tx_cfg = params; tx_cfg.H_SI = H_SI;
tx = generate_mimo_ofdm_waveform(tx_cfg);
tx_sig = tx.X;

% Beam power check (direct from design_precoder)
fprintf('=== BEAM PATTERN CHECK ===\n');
Ntx=4; Nty=4; d=params.lambda/2; kw=2*pi/params.lambda;
% Call design_precoder directly to get W
Nt=Ntx*Nty; Nr=64; Ks=params.K_stream;
H_c_test = (randn(Nr,Nt)+1j*randn(Nr,Nt))/sqrt(2);
opts=struct('SNR_dB',params.SNR,'H_SI',H_SI,'K',Ks,'Nt',Nt,'Nr',Nr,'comm_channel_type','random');
[W_test,~]=design_precoder(H_c_test,H_SI,'lagrange',opts);
for q=1:2
    u=sind(params.theta_true(q))*cosd(params.phi_true(q));
    v=sind(params.theta_true(q))*sind(params.phi_true(q));
    atx = exp(1j*kw*d*((0:Ntx-1)'*u + (0:Nty-1)*v));
    atx=atx(:);
    gain=abs(atx'*W_test(:))^2/norm(W_test(:))^2;
    fprintf('Target %d (th=%.1f, ph=%.1f): gain=%.4f (%.1f dB)\n',...
        q,params.theta_true(q),params.phi_true(q),gain,10*log10(gain+eps));
end

% RD peak analysis
p3=params; p3.H_SI_matrix=H_SI;
rx3=simulate_radar_channel_3d(tx_sig,p3);
rx_cube=rx3; tx_signal=tx_sig;
[Mx,My,Ns,L]=size(rx_cube);
delta_f=params.B/Ns; dv=params.c/(2*params.fc*params.Ts*params.K);
Nv_pad=256;
tx_eff=squeeze(sum(sum(tx_signal,1),2));
tx_norm=tx_eff./max(abs(tx_eff),eps);

% Multi-beam RD
win_sx=hann(Mx,'periodic'); win_sy=hann(My,'periodic');
rx_bf=fftshift(fftshift(fft2(rx_cube.*(win_sx*win_sy.')),1),2);
P_spatial=squeeze(mean(mean(abs(rx_bf).^2,3),4));
[~,si]=sort(P_spatial(:),'descend');
top_idx=si(1:8);
P=zeros(Ns,Nv_pad);
for k=1:8
    [mx,my]=ind2sub([Mx,My],top_idx(k));
    rs=squeeze(rx_bf(mx,my,:,:));
    rs_eq=rs.*conj(tx_norm).*(hann(Ns,'periodic')*hann(L,'periodic')');
    RDk=fftshift(fft(fft(rs_eq,Ns,1),Nv_pad,2),2);
    P=P+abs(RDk).^2;
end
P=P/8;

% Top peaks with distance gating
nv_vec=(-Nv_pad/2:Nv_pad/2-1).';
[Ps,idx]=maxk(P(:),128);
fprintf('\n=== RD PEAKS (top after R>20m gate) ===\n');
fprintf('Rank | Pwr(dB) |  R(m)  |  v(m/s) | bin_R | bin_v\n');
cnt=0;
for ii=1:min(128,numel(idx))
    [ir,iv]=ind2sub([Ns,Nv_pad],idx(ii));
    nr=ir-1; nv_L=nv_vec(iv)*(L/Nv_pad);
    R=mod(-params.c*nr/(2*Ns*delta_f),params.c/(2*delta_f));
    v=params.c*nv_L/(2*L*params.Ts*params.fc);
    if R<20, continue; end  % distance gate
    cnt=cnt+1;
    if cnt<=25
        fprintf('%4d | %+7.1f | %6.1f | %+7.2f | %5d | %+5.1f\n',...
            cnt,10*log10(Ps(ii)),R,v,ir,nv_L);
    end
end

fprintf('\nGround truth: T1(R=%.1f,v=%.1f) T2(R=%.1f,v=%.1f)\n',...
    params.R_true(1),params.v_true(1),params.R_true(2),params.v_true(2));

% Check if T2 is in candidate list
for ii=1:min(128,numel(idx))
    [ir,iv]=ind2sub([Ns,Nv_pad],idx(ii));
    nr=ir-1; nv_L=nv_vec(iv)*(L/Nv_pad);
    R=mod(-params.c*nr/(2*Ns*delta_f),params.c/(2*delta_f));
    v=params.c*nv_L/(2*L*params.Ts*params.fc);
    if abs(R-210.4)<2 && abs(v-(-5.4))<5
        fprintf('T2 FOUND at rank %d: R=%.1f v=%.2f power=%.1fdB\n',ii,R,v,10*log10(Ps(ii)));
    end
end
