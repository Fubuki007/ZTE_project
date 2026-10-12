function diagnose_si_angle_zf_nullspace(global_mc_indices)
% Diagnose why ZF and Nullspace differ mainly in theta RMSE.
% Reuses the exact seeds and simulator settings of the 80-MC beta sweep.

if nargin < 1
    global_mc_indices = [1 21 41 61];
end

close all; clc; warning('off', 'all');
maxNumCompThreads(2);

beta_list = [1, 10, 100, 1000, 1e6];
methods = {'zf', 'nullspace'};
method_labels = {'ZF', 'Nullspace'};

p0 = build_default_params();
p0.theta_true = [24.63, 15.94];
p0.phi_true = [30.99, 13.58];
p0.R_true = [200.6, 210.4];
p0.v_true = [15.1, -5.4];
p0.alpha = [1.0, 0.8];
p0.num_targets = 2;
p0.enable_SI = true;
p0.enable_SIC = false;
p0.sic_use_true_channel = false;
p0.sic_error_db = [];
p0.SIC_pilot_len = 128;
p0.SNR = 0;
p0.K_stream = 2;
p0.user_theta_rad = deg2rad(p0.theta_true(:));
p0.user_phi_rad = deg2rad(p0.phi_true(:));
p0.K = 256;
p0.Mx = 8;
p0.My = 8;
p0.joint_fft_3d.Na_x = p0.Mx;
p0.joint_fft_3d.Na_y = p0.My;
p0.fast_estimator.n_samp_l = 64;
p0.fast_estimator.R_max_gate = 600;

Nt = p0.Ntx * p0.Nty;
Nr = p0.Mx * p0.My;

fprintf('=== ZF/Nullspace angle diagnostic ===\n');
fprintf('MC indices: %s\n', mat2str(global_mc_indices));
fprintf('beta values: %s\n\n', mat2str(beta_list));

for mc = global_mc_indices(:).'
    hsi_seed = 20291000 + mc;
    data_seed = 20292000 + mc;
    data_noise_seed = 20293000 + mc;
    hsi_cfg = struct( ...
        'model', 'ura_rician', 'Nt_total', Nt, 'Nr_total', Nr, ...
        'kappa_SI', 10, 'Ntx', p0.Ntx, 'Nty', p0.Nty, ...
        'Mx', p0.Mx, 'My', p0.My, 'd_lambda', 0.5, ...
        'theta_tx_deg', p0.theta_SI, 'phi_tx_deg', p0.phi_SI, ...
        'theta_rx_deg', p0.theta_SI, 'phi_rx_deg', p0.phi_SI, ...
        'seed', hsi_seed);
    H_SI = generate_HSI(hsi_cfg);

    fprintf('--- global MC=%d ---\n', mc);
    for mi = 1:numel(methods)
        p = p0;
        p.precoder_type = methods{mi};
        p.H_SI = H_SI;
        p.H_SI_matrix = H_SI;
        rng(data_seed);
        tx = generate_mimo_ofdm_waveform(p);
        X = tx.X;

        [target_cube, target_info] = local_target_cube(X, p);
        noise_std = sqrt(target_info.target_signal_power / 2);
        rng(data_noise_seed);
        base_cube = local_add_awgn(target_cube, noise_std);

        tx_ref = squeeze(sum(sum(X, 1), 2));
        tx_ref_norm = tx_ref ./ max(abs(tx_ref), eps);
        tx_coh = zeros(1, 2);
        target_power = zeros(1, 2);
        for q = 1:2
            u = sind(p.theta_true(q)) * cosd(p.phi_true(q));
            v = sind(p.theta_true(q)) * sind(p.phi_true(q));
            nx = (0:p.Ntx-1).';
            ny = (0:p.Nty-1).';
            ax = exp(1j * 2*pi*p.d/p.lambda * nx * u);
            ay = exp(1j * 2*pi*p.d/p.lambda * ny * v);
            a_tx = ax * ay.';
            tx_eff = squeeze(sum(sum(conj(a_tx) .* X, 1), 2));
            target_weight = tx_eff .* conj(tx_ref_norm);
            tx_coh(q) = abs(sum(target_weight(:))) / ...
                max(sum(abs(target_weight(:))), realmin);
            target_power(q) = mean(abs(tx_eff(:)).^2);
        end

        si_power = local_channel_output_power(H_SI, X);
        tx_ref_rms = sqrt(mean(abs(tx_ref_norm(:)).^2));
        fprintf('%s: SIout=%.3e, targetP=[%.3e %.3e], refRMS=%.3f, ', ...
            method_labels{mi}, si_power, target_power(1), target_power(2), tx_ref_rms);
        fprintf('coh(target1/2)=[%.3f %.3f]\n', tx_coh(1), tx_coh(2));

        for bi = 1:numel(beta_list)
            rx_cube = local_add_channel_output( ...
                base_cube, beta_list(bi) * H_SI, X, p0.Mx, p0.My);
            [th, ph, rr, vv, info] = joint_estimator_fast(rx_cube, X, p);
            cmp = evaluate_estimation(th, ph, rr, vv, p, false);
            fprintf('  beta=%-8g det=%d theta=%.3f phi=%.3f R=%.3f v=%.3f | ', ...
                beta_list(bi), info.detected_targets, cmp.rmse_theta, ...
                cmp.rmse_phi, cmp.rmse_R, cmp.rmse_v);
            fprintf('est th=%s ph=%s R=%s v=%s\n', ...
                mat2str(th, 4), mat2str(ph, 4), mat2str(rr, 5), mat2str(vv, 4));
            clear rx_cube;
        end
        clear base_cube target_cube X tx;
    end
end
end

function [target_cube, info] = local_target_cube(X, p)
p_target = p;
p_target.enable_SI = false;
p_target.enable_SIC = false;
p_target.SNR = Inf;
[target_cube, info] = simulate_radar_channel_3d(X, p_target);
end

function rx_cube = local_add_awgn(rx_cube, noise_std)
[Mx, My, Ns, L] = size(rx_cube);
for l_idx = 1:L
    rx_cube(:, :, :, l_idx) = rx_cube(:, :, :, l_idx) + ...
        noise_std * (randn(Mx, My, Ns, 'like', rx_cube) + ...
        1j * randn(Mx, My, Ns, 'like', rx_cube));
end
end

function rx_cube = local_add_channel_output(rx_cube, G, X, Mx, My)
Ns = size(X, 3);
L = size(X, 4);
Nt = size(G, 2);
for l_idx = 1:L
    x_l = reshape(X(:, :, :, l_idx), Nt, Ns);
    channel_l = G * x_l;
    rx_cube(:, :, :, l_idx) = rx_cube(:, :, :, l_idx) + ...
        reshape(channel_l, Mx, My, Ns);
end
end

function power_value = local_channel_output_power(G, X)
Ns = size(X, 3);
L = size(X, 4);
Nt = size(G, 2);
Nr = size(G, 1);
power_sum = 0;
for l_idx = 1:L
    x_l = reshape(X(:, :, :, l_idx), Nt, Ns);
    y_l = G * x_l;
    power_sum = power_sum + sum(abs(y_l(:)).^2);
end
power_value = power_sum / (Nr * Ns * L);
end
