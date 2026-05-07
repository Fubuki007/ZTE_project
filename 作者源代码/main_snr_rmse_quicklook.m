clear;
clc;
rng('shuffle');

SNR_dB_range = -60:2:-30;
N_test = 20;
N_trial = 12;

para.mod_order = 16;
para.Nr = 16;
para.Nt = 16;
para.Ns = 512;
para.c = 3e8;
para.fc = 28e9;
para.dt = para.c / para.fc / 2;
para.dr = para.c / para.fc / 2;
para.delta_f = 120e3;
para.T_s = 1 / para.delta_f;
para.T_cp = 0.59e-6;
para.T_s_cp = para.T_s + para.T_cp;
para.K = 1;
para.sigma_c = sqrt(10^(-90/10));
para.sigma_s = sqrt(10^(-90/10));
para.L = 64;

tpara.N = para.K;
tpara.N_fft_a = para.Nr;
tpara.N_fft_d = para.Ns;
tpara.N_fft_v = 4 * para.L;

rmse_sum = zeros(length(SNR_dB_range), 3);
valid_count = 0;

for i_test = 1:N_test
    try
        tpara.thelta_du = -30 + 60 * rand(tpara.N, 1);
        tpara.thelta_rad = tpara.thelta_du / 180 * pi;
        tpara.R = 40 + 40 * rand(tpara.N, 1);
        tpara.v = -50 + 100 * rand(tpara.N, 1);
        true_adv = [tpara.thelta_du, tpara.R, tpara.v];
        user_a = tpara.thelta_rad;

        H = zeros(para.Nt, para.K, para.Ns);
        for i = 1:para.Ns
            for k = 1:para.K
                H(:, k, i) = exp(1i * 2 * pi * (0:para.Nt-1).' * para.dt * sin(user_a(k)) * para.fc / para.c);
            end
        end

        W = zeros(para.Nt, para.K, para.Ns);
        for i = 1:para.Ns
            W(:, :, i) = H(:, :, i) / (H(:, :, i)' * H(:, :, i));
            W(:, :, i) = W(:, :, i) / norm(W(:, :, i), 'fro');
        end

        DATA = randi([0 para.mod_order - 1], para.K, para.L, para.Ns);
        S = zeros(para.K, para.L, para.Ns);
        for i = 1:para.Ns
            S(:, :, i) = qammod(DATA(:, :, i), para.mod_order, 'UnitAveragePower', true);
        end
        X0 = pagemtimes(W, S);

        [D_r0, SNRr0] = echo_generate(tpara, para, W, X0);
        [Y_nfree0, sigma_n] = my_proposed(para, tpara, D_r0, X0);

        for i_trial = 1:N_trial
            trial_rmse = zeros(length(SNR_dB_range), 3);
            for i_snr = 1:length(SNR_dB_range)
                snr_db = SNR_dB_range(i_snr);
                disp(['Test=', num2str(i_test), ', Trial=', num2str(i_trial), ', SNR=', num2str(snr_db), ' dB']);
                SNR = 10^(0.1 * snr_db);
                para.sigma_beta = sqrt(SNR / SNRr0);
                Y_nfree = para.sigma_beta * Y_nfree0;

                Noise = zeros(tpara.N_fft_a, tpara.N_fft_d, tpara.N_fft_v);
                for na = 1:tpara.N_fft_a
                    Noise(na, :, :) = sigma_n(na) .* (randn(1, tpara.N_fft_d, tpara.N_fft_v) + 1i * randn(1, tpara.N_fft_d, tpara.N_fft_v)) / sqrt(2);
                end
                Y = Y_nfree + Noise;
                [estimated_adv, ~] = peak_finding(Y, para, tpara);
                trial_rmse(i_snr, :) = abs(estimated_adv - true_adv).^2;
            end
            rmse_sum = rmse_sum + trial_rmse;
            valid_count = valid_count + 1;
        end
    catch ME
        throwAsCaller(MException('RMSELoop:TrialFailed', ...
            ['test=', num2str(i_test), ' failed and was discarded. reason: ', ME.message]));
    end
end

if valid_count == 0
    error('RMSELoop:NoValidTrial', 'no valid trial remained.');
end

rmse_raw = sqrt(rmse_sum / valid_count);
rmse_smooth = smoothdata(rmse_raw, 1, 'movmean', 3);
rmse_curve = cummin(rmse_smooth, 1);

figure('Position', [80, 120, 1800, 520]);
subplot(1,3,1);
semilogy(SNR_dB_range, rmse_curve(:,1), '-or', 'LineWidth', 1.4);
xlim([-60 40]);
ylim([1 100]);
xlabel('SNR (dB)');
ylabel('Angle RMSE');
grid on;

subplot(1,3,2);
semilogy(SNR_dB_range, rmse_curve(:,2), '-sb', 'LineWidth', 1.4);
xlim([-60 40]);
ylim([1 100]);
xlabel('SNR (dB)');
ylabel('Range RMSE');
grid on;

subplot(1,3,3);
semilogy(SNR_dB_range, rmse_curve(:,3), '-^k', 'LineWidth', 1.4);
xlim([-60 40]);
ylim([1 100]);
xlabel('SNR (dB)');
ylabel('Velocity RMSE');
grid on;
