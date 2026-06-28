
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

% Simulate and manually extract RD detection peaks
p3=params; p3.H_SI_matrix=H_SI;
rx3=simulate_radar_channel_3d(tx_sig,p3);

% Replicate stage 1 processing to inspect candidates
rx_cube = rx3; tx_signal = tx_sig;
[Mx, My, Ns, L] = size(rx_cube);
delta_f = params.B / Ns;

% tx_eff
sz_tx = size(tx_signal);
if isequal(sz_tx, [Ns, L])
    tx_eff = tx_signal;
else
    tx_eff = squeeze(sum(sum(tx_signal, 1), 2));
end
tx_norm = tx_eff ./ max(abs(tx_eff), eps);

% RD with multi-beam
Nv_pad = max(L, 256);
top_n_spatial = 8;
win_sx = hann(Mx, 'periodic');
win_sy = hann(My, 'periodic');
rx_cube_win = rx_cube .* (win_sx * win_sy.');
rx_bf = fftshift(fftshift(fft2(rx_cube_win), 1), 2);
P_spatial = squeeze(mean(mean(abs(rx_bf).^2, 3), 4));
[~, sort_idx] = sort(P_spatial(:), 'descend');
top_idx = sort_idx(1:top_n_spatial);

P = zeros(Ns, Nv_pad);
for k = 1:numel(top_idx)
    [mx_i, my_i] = ind2sub([Mx, My], top_idx(k));
    rx_s = squeeze(rx_bf(mx_i, my_i, :, :));
    rx_s_eq = rx_s .* conj(tx_norm);
    win_r = hann(Ns, 'periodic');
    win_l = hann(L, 'periodic');
    rx_s_eq = rx_s_eq .* (win_r * win_l.');
    RD_k = fft(rx_s_eq, Ns, 1);
    RD_k = fft(RD_k, Nv_pad, 2);
    RD_k = fftshift(RD_k, 2);
    P = P + abs(RD_k).^2;
end
P = P / numel(top_idx);

% Find top 20 peaks in P, show their R,v
[Psorted, idx] = maxk(P(:), 20);
fprintf('=== Top 20 RD peaks ===\n');
fprintf('Rank | Power(dB) |  R(m)  |  v(m/s)  | bin_R | bin_v\n');
fprintf('-----|-----------|--------|----------|-------|------\n');
nv_vec = (-floor(Nv_pad/2) : (ceil(Nv_pad/2) - 1)).';
for ii = 1:min(20, numel(idx))
    [ir, iv] = ind2sub([Ns, Nv_pad], idx(ii));
    nr = ir - 1;  % 0-based
    nv_raw = nv_vec(iv);
    nv_L = nv_raw * (L/Nv_pad);  % scale to L-point
    R_val = mod(-params.c * nr / (2 * Ns * delta_f), params.c/(2*delta_f));
    v_val = params.c * nv_L / (2 * L * params.Ts * params.fc);
    power_db = 10*log10(Psorted(ii));
    fprintf('%4d | %+8.1f | %6.1f | %+8.2f | %5d | %+5.1f\n',...
        ii, power_db, R_val, v_val, ir, nv_L);
end

% Where should target 2 be?
fprintf('\nExpected: T1 R=%.1f v=%.1f | T2 R=%.1f v=%.1f\n',...
    params.R_true(1), params.v_true(1), params.R_true(2), params.v_true(2));
fprintf('dR=%.3fm, dv=%.3fm/s\n', dR, dv);
