clear; close all; clc;
warning('off', 'all');

fprintf('=================================================\n');
fprintf('  RMSE vs SNR 对比：Mx = 4 / 16（稳健统计+异常抛出+平滑）\n');
fprintf('=================================================\n');

%% 1) 基础参数
base = struct();
base.c = 3e8;
base.fc = 28e9;
base.lambda = base.c / base.fc;
base.d = base.lambda / 2;

base.My = 8;                  % 固定 My
base.K = 256;
base.num_targets = 2;

base.theta_true = [28.8, 28.6];
base.phi_true = [28.6, 28.3];
base.R_true = [600.80, 600.20];
base.v_true = [15.1, -5.4];
base.alpha = [1.0, 0.8];

base.mod_order = 16;       % 16-QAM, 对齐论文
base.pilot_spacing = 0;    % 不再使用

% OFDM 参数
n_rb = 264;
n_sc_per_rb = 12;
delta_f_cfg = 120e3;
T_cp = 0.6e-6;
base.N = n_rb * n_sc_per_rb;
base.B = base.N * delta_f_cfg;
base.Ts = 1 / delta_f_cfg + T_cp;

% local ESPRIT 参数
base.use_interpolation = true;
base.local_esprit = struct();
base.local_esprit.num_candidates = 8;
base.local_esprit.n_samples_range = 384;
base.local_esprit.n_samples_doppler = 48;
base.local_esprit.rd_nms_r = 2;
base.local_esprit.rd_nms_v = 2;

% 阵列幅相失配（可选误差地板）
base.array_mismatch = struct();
base.array_mismatch.enable = true;
base.array_mismatch.amp_sigma_db = 0.30;
base.array_mismatch.phase_sigma_deg = 3.0;

%% 2) 仿真配置
snr_list = -40:5:40;
num_mc = 30;                  % 增大MC次数，减少曲线抖动
mx_list = [4, 16];
num_snr = numel(snr_list);
num_mx = numel(mx_list);

% 异常检测阈值（若触发则直接 error）
min_detect_rate = 0.70;       % 每个SNR点最小有效匹配率
max_up_jump_ratio = 1.8;      % 相邻SNR点允许的最大“向上跳”倍数（线性域）

% 平滑配置
enable_smoothing = true;
smooth_window = 3;            % 移动中值窗口（奇数）

rmse_angle_raw = nan(num_mx, num_snr);
rmse_range_raw = nan(num_mx, num_snr);
rmse_velocity_raw = nan(num_mx, num_snr);

colors = [
    0.85 0.10 0.10;  % 红
    0.10 0.45 0.85   % 蓝
];

t_start = tic;

%% 3) 双层扫描：Mx × SNR（稳健统计：按每次MC先算RMSE，再取中位数）
for im = 1:num_mx
    params = base;
    params.Mx = mx_list(im);

    cfg_tx = struct('N', params.N, 'K', params.K, 'mod_order', params.mod_order, 'pilot_spacing', params.pilot_spacing);
    tx_signal = generate_OFDM_signal(cfg_tx);

    fprintf('\n---- 扫描 Mx=%d, My=%d ----\n', params.Mx, params.My);

    for i = 1:num_snr
        params.SNR = snr_list(i);

        rmse_angle_mc = nan(1, num_mc);
        rmse_range_mc = nan(1, num_mc);
        rmse_velocity_mc = nan(1, num_mc);
        valid_mc = 0;

        for mc = 1:num_mc
            rx_cube = simulate_radar_channel_3d(tx_signal, params);
            [theta_est, phi_est, R_est, v_est, ~] = joint_angle_range_velocity_estimator(rx_cube, tx_signal, params);

            if isempty(theta_est)
                continue;
            end

            num_est = numel(theta_est);
            num_true = numel(params.theta_true);
            used_true = false(1, num_true);

            sq_err_theta = 0;
            sq_err_phi = 0;
            sq_err_R = 0;
            sq_err_v = 0;
            n_match = 0;

            for k = 1:num_est
                candidate_set = find(~used_true);
                if isempty(candidate_set)
                    candidate_set = 1:num_true;
                end

                best_j = candidate_set(1);
                best_cost = inf;
                for ii = 1:numel(candidate_set)
                    j = candidate_set(ii);
                    cost = abs(theta_est(k) - params.theta_true(j)) / 90 + ...
                           abs(phi_est(k) - params.phi_true(j)) / 180 + ...
                           abs(R_est(k) - params.R_true(j)) / max(1, max(params.R_true)) + ...
                           abs(v_est(k) - params.v_true(j)) / max(1, max(abs(params.v_true)));
                    if cost < best_cost
                        best_cost = cost;
                        best_j = j;
                    end
                end

                used_true(best_j) = true;
                sq_err_theta = sq_err_theta + (theta_est(k) - params.theta_true(best_j))^2;
                sq_err_phi = sq_err_phi + (phi_est(k) - params.phi_true(best_j))^2;
                sq_err_R = sq_err_R + (R_est(k) - params.R_true(best_j))^2;
                sq_err_v = sq_err_v + (v_est(k) - params.v_true(best_j))^2;
                n_match = n_match + 1;
            end

            if n_match > 0
                valid_mc = valid_mc + 1;
                rmse_angle_mc(valid_mc) = sqrt((sq_err_theta + sq_err_phi) / (2 * n_match));
                rmse_range_mc(valid_mc) = sqrt(sq_err_R / n_match);
                rmse_velocity_mc(valid_mc) = sqrt(sq_err_v / n_match);
            end
        end

        detect_rate = valid_mc / num_mc;
        if detect_rate < min_detect_rate
            error('异常：Mx=%d, SNR=%d dB 有效检测率仅 %.2f (< %.2f)。请检查参数或提高MC次数。', ...
                params.Mx, params.SNR, detect_rate, min_detect_rate);
        end

        rmse_angle_raw(im, i) = median(rmse_angle_mc(1:valid_mc), 'omitnan');
        rmse_range_raw(im, i) = median(rmse_range_mc(1:valid_mc), 'omitnan');
        rmse_velocity_raw(im, i) = median(rmse_velocity_mc(1:valid_mc), 'omitnan');

        fprintf('Mx=%2d | SNR=%3d dB | angle=%.4f deg, range=%.4f m, velocity=%.4f m/s | valid=%d/%d\n', ...
            params.Mx, snr_list(i), rmse_angle_raw(im, i), rmse_range_raw(im, i), rmse_velocity_raw(im, i), valid_mc, num_mc);
    end

    % 异常跳变检查（角度/距离/速度都检查）
    check_abnormal_jump(rmse_angle_raw(im, :), snr_list, max_up_jump_ratio, sprintf('Angle, Mx=%d', params.Mx));
    check_abnormal_jump(rmse_range_raw(im, :), snr_list, max_up_jump_ratio, sprintf('Range, Mx=%d', params.Mx));
    check_abnormal_jump(rmse_velocity_raw(im, :), snr_list, max_up_jump_ratio, sprintf('Velocity, Mx=%d', params.Mx));
end

fprintf('\n总耗时: %.2f s\n', toc(t_start));

%% 4) 平滑（可选）
if enable_smoothing
    rmse_angle = movmedian(rmse_angle_raw, smooth_window, 2, 'omitnan');
    rmse_range = movmedian(rmse_range_raw, smooth_window, 2, 'omitnan');
    rmse_velocity = movmedian(rmse_velocity_raw, smooth_window, 2, 'omitnan');
else
    rmse_angle = rmse_angle_raw;
    rmse_range = rmse_range_raw;
    rmse_velocity = rmse_velocity_raw;
end

%% 5) 三联图（每张图两条不同颜色曲线）
figure('Name', 'RMSE vs SNR for Mx=4/16', 'Position', [80, 120, 1550, 500], 'Color', 'w');
labels = arrayfun(@(x) sprintf('Mx=%d', x), mx_list, 'UniformOutput', false);

subplot(1, 3, 1); hold on;
for im = 1:num_mx
    semilogy(snr_list, rmse_angle(im, :), '-o', 'LineWidth', 2.0, 'MarkerSize', 5, ...
        'Color', colors(im, :), 'MarkerFaceColor', 'w');
end
grid on; box on;
xlabel('SNR (dB)'); ylabel('RMSE of angle (degree)'); title('Angle'); xlim([-40 40]);
legend(labels, 'Location', 'southwest');

subplot(1, 3, 2); hold on;
for im = 1:num_mx
    semilogy(snr_list, rmse_range(im, :), '-s', 'LineWidth', 2.0, 'MarkerSize', 5, ...
        'Color', colors(im, :), 'MarkerFaceColor', 'w');
end
grid on; box on;
xlabel('SNR (dB)'); ylabel('RMSE of range (m)'); title('Range'); xlim([-40 40]);
legend(labels, 'Location', 'southwest');

subplot(1, 3, 3); hold on;
for im = 1:num_mx
    semilogy(snr_list, rmse_velocity(im, :), '-d', 'LineWidth', 2.0, 'MarkerSize', 5, ...
        'Color', colors(im, :), 'MarkerFaceColor', 'w');
end
grid on; box on;
xlabel('SNR (dB)'); ylabel('RMSE of velocity (m/s)'); title('Velocity'); xlim([-40 40]);
legend(labels, 'Location', 'southwest');

sgtitle('Proposed estimator: RMSE versus SNR (different Mx)', 'FontWeight', 'bold');

%% 6) 保存
saveas(gcf, 'RMSE_vs_SNR_Mx_compare.png');
save('RMSE_vs_SNR_Mx_compare.mat', ...
    'snr_list', 'mx_list', 'rmse_angle', 'rmse_range', 'rmse_velocity', ...
    'rmse_angle_raw', 'rmse_range_raw', 'rmse_velocity_raw', ...
    'num_mc', 'base', 'enable_smoothing', 'smooth_window', ...
    'min_detect_rate', 'max_up_jump_ratio');
fprintf('已保存: RMSE_vs_SNR_Mx_compare.png 与 RMSE_vs_SNR_Mx_compare.mat\n');

function check_abnormal_jump(y, x, max_ratio, tag)
idx = find(isfinite(y));
if numel(idx) < 2
    return;
end
for k = 2:numel(idx)
    i1 = idx(k-1);
    i2 = idx(k);
    if y(i2) > max_ratio * y(i1)
        error('异常跳变：%s 在 SNR=%d -> %d dB 处从 %.4g 跳到 %.4g（> %.2fx）。', ...
            tag, x(i1), x(i2), y(i1), y(i2), max_ratio);
    end
end
end
