function diagnose_beta_si_invariance()
% Verify how beta_SI propagates through injection and pilot-based LS SIC.

p = build_default_params();
p.N = 64;
p.K = 8;
p.Mx = 4;
p.My = 4;
p.SNR = 0;
p.enable_SI = true;
p.sic_use_true_channel = false;
p.SIC_pilot_len = 128;

Nt = p.Ntx * p.Nty;
Nr = p.Mx * p.My;

rng(20260921);
X = (randn(p.Ntx, p.Nty, p.N, p.K) + ...
    1j * randn(p.Ntx, p.Nty, p.N, p.K)) / sqrt(2 * Nt);
H = (randn(Nr, Nt) + 1j * randn(Nr, Nt)) / sqrt(2);
H = H / norm(H, 'fro') * sqrt(Nr * Nt);
X_pilot = (randn(Nt, p.SIC_pilot_len) + ...
    1j * randn(Nt, p.SIC_pilot_len)) / sqrt(2);

p.H_SI = H;
p.H_SI_matrix = H;
p.SIC_pilot = X_pilot;

beta_values = [1, 1e2, 1e4, 1e6];

fprintf('=== Paper Eqs. (46)-(47), receiver thermal noise ===\n');
p.sic_error_db = [];
[paper_no_sic_db, paper_sic_db, paper_change] = ...
    run_beta_sweep(p, X, beta_values);
print_sweep(beta_values, paper_no_sic_db, paper_sic_db, paper_change);

fprintf('\n=== Controlled LS channel-estimation NMSE = -60 dB ===\n');
p.sic_error_db = -60;
[controlled_no_sic_db, controlled_sic_db, controlled_change] = ...
    run_beta_sweep(p, X, beta_values);
print_sweep(beta_values, controlled_no_sic_db, ...
    controlled_sic_db, controlled_change);

assert(max(abs(paper_sic_db - paper_sic_db(1))) < 1e-6, ...
    'Paper thermal-noise baseline should be beta-invariant after ideal LS SIC.');
assert(controlled_sic_db(end) - controlled_sic_db(1) > 40, ...
    'Controlled NMSE mode must expose finite SIC capability as beta grows.');
fprintf('\nPASS: beta propagation and controlled-NMSE sensitivity are both verified.\n');
end

function [power_no_sic_db, power_sic_db, relative_change] = ...
        run_beta_sweep(p, X, beta_values)
rx_sic = cell(size(beta_values));
power_no_sic_db = zeros(size(beta_values));
power_sic_db = zeros(size(beta_values));
relative_change = zeros(size(beta_values));

for idx = 1:numel(beta_values)
    p.beta_SI = beta_values(idx);
    p.enable_SIC = false;
    rng(20260922);
    y_no_sic = simulate_radar_channel_3d(X, p);
    power_no_sic_db(idx) = 10 * log10(mean(abs(y_no_sic(:)).^2));

    p.enable_SIC = true;
    rng(20260923);
    rx_sic{idx} = simulate_radar_channel_3d(X, p);
    power_sic_db(idx) = 10 * log10(mean(abs(rx_sic{idx}(:)).^2));
end

for idx = 1:numel(beta_values)
    relative_change(idx) = norm(rx_sic{idx}(:) - rx_sic{1}(:)) / ...
        max(norm(rx_sic{1}(:)), realmin);
end
end

function print_sweep(beta_values, power_no_sic_db, ...
        power_sic_db, relative_change)
fprintf('beta        no-SIC power (dB)   SIC power (dB)   SIC output change vs beta=1\n');
for idx = 1:numel(beta_values)
    fprintf('%-10.0e  %17.4f   %14.4f   %.6e\n', ...
        beta_values(idx), power_no_sic_db(idx), ...
        power_sic_db(idx), relative_change(idx));
end
end
