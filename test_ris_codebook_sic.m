function test_ris_codebook_sic()
clear; clc; warning('off','all');
rng(20260928);

params = build_default_params();

% ---- small test configuration ----
params.Mx = 4;
params.My = 4;
params.Ntx = 4;
params.Nty = 4;
params.N = 256;
params.B = params.N * 120e3;
params.K = 32;
params.K_stream = 2;
params.num_targets = 0;          % SI-only test
params.enable_SI = true;
params.beta_SI = 100;
params.enable_SIC = false;       % first test without digital SIC
params.precoder_type = 'nullspace';

params.user_theta_rad = deg2rad([24.63; 15.94]);
params.user_phi_rad   = deg2rad([30.99; 13.58]);

Nt = params.Ntx * params.Nty;
Nr = params.Mx * params.My;

% ---- direct SI channel ----
cfg = struct( ...
    'model','ura_rician', ...
    'Nt_total',Nt, 'Nr_total',Nr, ...
    'kappa_SI',10, ...
    'Ntx',params.Ntx, 'Nty',params.Nty, ...
    'Mx',params.Mx, 'My',params.My, ...
    'd_lambda',0.5, ...
    'theta_tx_deg',params.theta_SI, 'phi_tx_deg',params.phi_SI, ...
    'theta_rx_deg',params.theta_SI, 'phi_rx_deg',params.phi_SI);

H_direct = generate_HSI(cfg);

% ---- abstract RIS channel ----
% H_RIS(theta) = scale * A * diag(exp(1j*theta)) * B
Nris = 128;
rho  = 0.3;   % RIS path amplitude relative to direct SI

A = (randn(Nr,Nris) + 1j*randn(Nr,Nris)) / sqrt(2);
B = (randn(Nris,Nt) + 1j*randn(Nris,Nt)) / sqrt(2);

H0 = A * B;
scale = sqrt(Nt * Nr * rho^2 / (norm(H0,'fro')^2 + eps));

H_RIS = @(theta) scale * (A * diag(exp(1j*theta)) * B);

% ---- communication channel for precoder ----
Hc = (randn(Nt,params.K_stream) + 1j*randn(Nt,params.K_stream)) / sqrt(2);

W_direct = design_precoder(Hc, H_direct, params.precoder_type);
leak_direct = norm(H_direct * W_direct, 'fro')^2;

fprintf('==== RIS codebook SIC test ====\n');
fprintf('Direct SI leakage (no RIS): %.6g\n', leak_direct);

% ---- codebook sweep ----
M_list = [16 32 64 128 256];
Theta_all = exp(1j*2*pi*rand(Nris, max(M_list)));

best_theta = [];
best_leak  = inf;

fprintf('\nCodebook sweep:\n');
for k = 1:numel(M_list)
    M = M_list(k);
    best_k = inf;
    theta_k = [];

    for m = 1:M
        theta = Theta_all(:,m);
        Ht = H_direct + H_RIS(theta);

        Wm = design_precoder(Hc, Ht, params.precoder_type);
        leak = norm(Ht * Wm, 'fro')^2;

        if leak < best_k
            best_k = leak;
            theta_k = theta;
        end
    end

    imp_db = 10*log10(leak_direct / best_k);
    fprintf('M=%3d, best leakage=%.6g, improvement=%.2f dB\n', ...
        M, best_k, imp_db);

    if best_k < best_leak
        best_leak = best_k;
        best_theta = theta_k;
    end
end

% ---- optional end-to-end SI-only test ----
try
    p = params;
    p.H_SI = H_direct + H_RIS(best_theta);
    p.H_SI_matrix = p.H_SI;

    tx = generate_mimo_ofdm_waveform(p);
    rx = simulate_radar_channel_3d(tx.X, p);
    pow_ris = mean(abs(rx(:)).^2);

    p2 = params;
    p2.H_SI = H_direct;
    p2.H_SI_matrix = H_direct;

    tx2 = generate_mimo_ofdm_waveform(p2);
    rx2 = simulate_radar_channel_3d(tx2.X, p2);
    pow_direct = mean(abs(rx2(:)).^2);

    fprintf('\nEnd-to-end SI-only power:\n');
    fprintf('  no RIS : %.6g\n', pow_direct);
    fprintf('  RIS    : %.6g\n', pow_ris);
    fprintf('  improvement = %.2f dB\n', ...
        10*log10(pow_direct / pow_ris));

catch ME
    fprintf('\nEnd-to-end simulation skipped: %s\n', ME.message);
end
end
