function test_ris_codebook_sic_v2()
clear; clc; warning('off','all');
rng(20260928);

params = build_default_params();
% match a realistic receive array: Mrx = 64, Nt = 16
params.Mx = 8;
params.My = 8;
params.Ntx = 4;
params.Nty = 4;
params.N = 256;
params.B = params.N * 120e3;
params.K = 32;
params.K_stream = 2;
params.num_targets = 0;
params.enable_SI = true;
params.beta_SI = 100;
params.enable_SIC = false;

params.user_theta_rad = deg2rad([24.63; 15.94]);
params.user_phi_rad   = deg2rad([30.99; 13.58]);

Nt = params.Ntx * params.Nty;
Nr = params.Mx * params.My;

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

% use the same LoS communication channel that generate_mimo_ofdm_waveform builds
p0 = params;
p0.precoder_type = 'zf';
p0.H_SI = H_direct;
p0.H_SI_matrix = H_direct;
tx0 = generate_mimo_ofdm_waveform(p0);
Hc = tx0.H(:,:,1);

% abstract RIS channel
Nris = 128;
rho  = 0.5;
A = (randn(Nr,Nris) + 1j*randn(Nr,Nris)) / sqrt(2);
B = (randn(Nris,Nt) + 1j*randn(Nris,Nt)) / sqrt(2);
H0 = A * B;
scale = sqrt(Nt * Nr * rho^2 / (norm(H0,'fro')^2 + eps));
H_RIS = @(theta) scale * (A * diag(exp(1j*theta)) * B);

M_list = [64 256 1024 4096];
Theta_all = exp(1j*2*pi*rand(Nris, max(M_list)));

fprintf('==== RIS codebook SIC test v2 ====\n');
fprintf('Nt=%d, Nr=%d, Nris=%d, rho=%.2f\n', Nt, Nr, Nris, rho);

methods = {'zf','nullspace'};
for mi = 1:numel(methods)
    method = methods{mi};
    Wd = design_precoder(Hc, H_direct, method);
    leak_direct = norm(H_direct * Wd, 'fro')^2;
    fprintf('\nPrecoder = %s\n', method);
    fprintf('  No RIS leakage: %.6g\n', leak_direct);

    for k = 1:numel(M_list)
        M = M_list(k);
        best_leak = inf;
        for m = 1:M
            theta = Theta_all(:,m);
            Ht = H_direct + H_RIS(theta);
            Wm = design_precoder(Hc, Ht, method);
            leak = norm(Ht * Wm, 'fro')^2;
            if leak < best_leak
                best_leak = leak;
            end
        end
        imp_db = 10*log10(leak_direct / best_leak);
        fprintf('  M=%4d, best leakage=%.6g, improvement=%.2f dB\n', ...
            M, best_leak, imp_db);
    end
end
end
