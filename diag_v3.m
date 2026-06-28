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

dv = params.c/(2*params.fc*params.Ts*params.K);
dR = params.c/(2*params.B);
fprintf('dR=%.3fm dv=%.3fm/s | True: T1(R=%.1f,v=%.1f) T2(R=%.1f,v=%.1f)\n\n',...
    dR,dv,params.R_true(1),params.v_true(1),params.R_true(2),params.v_true(2));

% Simulate
p3=params; p3.H_SI_matrix=H_SI;
rx3=simulate_radar_channel_3d(tx_sig,p3);

% Manually build RD power map
rx_cube=rx3; tx_signal=tx_sig;
[Mx,My,Ns,L]=size(rx_cube);
delta_f=params.B/Ns; Rmax_val=params.c/(2*delta_f);
Nv_pad=256;

tx_eff=squeeze(sum(sum(tx_signal,1),2));
tx_norm=tx_eff./max(abs(tx_eff),eps);

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

% Top peaks
nv_vec=(-Nv_pad/2:Nv_pad/2-1).';
[Ps,idx]=maxk(P(:),200);

fprintf('Top 30 RD peaks (R>20m gate):\n');
fprintf('Rank | Pwr(dB) |  R(m)  |  v(m/s) | ir  | nv(L)\n');
cnt=0; found_t1=false; found_t2=false;
for ii=1:min(200,numel(idx))
    [ir,iv]=ind2sub([Ns,Nv_pad],idx(ii));
    nr=ir-1; nv_L=nv_vec(iv)*(L/Nv_pad);
    R=mod(-params.c*nr/(2*Ns*delta_f),Rmax_val);
    v=params.c*nv_L/(2*L*params.Ts*params.fc);
    if R<20, continue; end
    cnt=cnt+1;
    if cnt<=30
        fprintf('%4d | %+7.1f | %6.1f | %+7.2f | %4d | %+5.1f\n',...
            cnt,10*log10(Ps(ii)),R,v,ir,nv_L);
    end
    if abs(R-200.6)<2 && abs(v-15.1)<3, found_t1=true; end
    if abs(R-210.4)<2 && abs(v-(-5.4))<3, found_t2=true; end
end

fprintf('\nTarget 1 (R=200.6 v=15.1): %s\n', ternary(found_t1,'FOUND','MISSING'));
fprintf('Target 2 (R=210.4 v=-5.4): %s\n', ternary(found_t2,'FOUND','MISSING'));

% Search T2 specifically
fprintf('\nSearching for T2 in 200 candidates...\n');
for ii=1:min(200,numel(idx))
    [ir,iv]=ind2sub([Ns,Nv_pad],idx(ii));
    nr=ir-1; nv_L=nv_vec(iv)*(L/Nv_pad);
    R=mod(-params.c*nr/(2*Ns*delta_f),Rmax_val);
    v=params.c*nv_L/(2*L*params.Ts*params.fc);
    if abs(R-210.4)<3 && abs(v+5.4)<5
        fprintf('T2 at rank %d: R=%.1f v=%.2f pwr=%.1fdB ir=%d nv=%.1f\n',...
            ii,R,v,10*log10(Ps(ii)),ir,nv_L);
    end
end

function s = ternary(cond,t,f)
    if cond, s=t; else, s=f; end
end
