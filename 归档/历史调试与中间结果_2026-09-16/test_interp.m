
% Quick test: compare parabolic vs Jacobsen vs Candan interpolation
% on a single noisy sinusoid (mimicking Doppler FFT peak)

N = 256;           % same as K
n_mc = 1000;       % Monte Carlo
true_bin = 6.446;  % same as target 1

% Generate test signal: complex sinusoid + noise
rng(42);
errors_parabolic = zeros(n_mc, 1);
errors_jacobsen  = zeros(n_mc, 1);
errors_candan    = zeros(n_mc, 1);

for mc = 1:n_mc
    t = (0:N-1).';
    % Complex sinusoid at true_bin / N (normalized freq)
    sig = exp(1j * 2 * pi * true_bin / N * t);
    % Add Hann window
    win = hann(N, 'periodic');
    sig_win = sig .* win;
    % Add noise (SNR ~20dB after FFT gain)
    noise = (randn(N,1) + 1j*randn(N,1)) * 0.3 / sqrt(2);
    sig_noisy = sig_win + noise;
    
    % FFT
    X = fft(sig_noisy, N);
    X = fftshift(X);  % center DC
    P = abs(X).^2;
    
    % Find peak bin
    [~, k] = max(P);
    
    if k > 1 && k < N
        % === Parabolic (current method) ===
        Pl = P(k-1); Pc = P(k); Pr = P(k+1);
        denom = Pl - 2*Pc + Pr;
        if abs(denom) > eps
            delta = 0.5 * (Pl - Pr) / denom;
            delta = max(min(delta, 0.5), -0.5);
            est_bin_p = k - (N/2+1) + delta;  % convert to true bin scale
        else
            est_bin_p = k - (N/2+1);
        end
        
        % === Jacobsen (power spectrum version) ===
        num = Pl - Pr;
        den = 2*Pc - Pl - Pr;
        if abs(den) > eps
            delta_j = num / den;
            delta_j = max(min(delta_j, 0.5), -0.5);
            est_bin_j = k - (N/2+1) + delta_j;
        else
            est_bin_j = k - (N/2+1);
        end
        
        % === Candan (Hann window corrected) ===
        % Candan correction for Hann window: scale delta by approx factor
        % delta_candan = atan(N*tan(pi*delta/N)) / pi  (for rectangular)
        % For Hann: delta ~ delta_jacobsen * correction
        % Actually, use Jacobsen then apply small correction
        if abs(den) > eps
            % Use Jacobsen atan correction (Candan 2011)
            delta_raw = num / den;
            delta_raw = max(min(delta_raw, 0.5), -0.5);
            % Candan refinement for Hann: iterative correction
            delta_c = delta_raw;
            for iter = 1:2
                delta_c = atan(N * tan(pi * delta_c / N)) / pi;
            end
            delta_c = max(min(delta_c, 0.5), -0.5);
            est_bin_c = k - (N/2+1) + delta_c;
        else
            est_bin_c = k - (N/2+1);
        end
        
        errors_parabolic(mc) = est_bin_p - true_bin;
        errors_jacobsen(mc)  = est_bin_j - true_bin;
        errors_candan(mc)    = est_bin_c - true_bin;
    end
end

fprintf('=== Interpolation comparison (N=%d, true_bin=%.3f, MC=%d) ===\n', N, true_bin, n_mc);
fprintf('Method      | Bias(bin) | RMSE(bin) | RMSE(m/s equiv)\n');
fprintf('------------|-----------|-----------|----------------\n');
dv = 2.343;  % m/s per bin for reference
fprintf('Parabolic   | %+9.5f | %9.5f | %9.3f\n', ...
    mean(errors_parabolic), sqrt(mean(errors_parabolic.^2)), ...
    sqrt(mean(errors_parabolic.^2))*dv);
fprintf('Jacobsen    | %+9.5f | %9.5f | %9.3f\n', ...
    mean(errors_jacobsen), sqrt(mean(errors_jacobsen.^2)), ...
    sqrt(mean(errors_jacobsen.^2))*dv);
fprintf('Candan      | %+9.5f | %9.5f | %9.3f\n', ...
    mean(errors_candan), sqrt(mean(errors_candan.^2)), ...
    sqrt(mean(errors_candan.^2))*dv);
fprintf('\nBin-only (no interpol): RMSE = %.4f bin = %.3f m/s\n', ...
    true_bin - round(true_bin), abs(true_bin-round(true_bin))*dv);
