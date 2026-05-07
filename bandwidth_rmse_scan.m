clear; clc;
t_total = tic;
warning('off', 'all');
fprintf('=================================================\n');
fprintf('  带宽-RMSE蒙特卡洛扫描\n');
fprintf('=================================================\n');

params = struct();
params.c = 3e8;
params.fc = 28e9;
params.Mx = 8;
params.My = 8;
params.K = 256;
params.num_targets = 2;
params.theta_true = [28.6, 28.6];
params.phi_true = [28.6, 28.6];
params.R_true = [600.88, 600.81];
params.v_true = [15.1, -5.4];
params.alpha = [1.0, 0.8];
params.SNR = 10;
params.mod_order = 4;
params.pilot_spacing = 4;

n_rb = 264;
n_sc_per_rb = 12;
delta_f_cfg = 120e3;
T_cp = 0.6e-6;
range_margin = 15;
target_range_resolution = 0.1;
enable_carrier_aggregation = true;

params.use_interpolation = false;
estimator_mode = 'local_esprit';
bw_rmse_mc = 5;
bw_rmse_scan_half_width = 2;

spatial_pad_factor = 16;
doppler_pad_factor = 32;
params.joint_fft_3d_cfar_pfa = 1e-4;
params.joint_fft_3d_cfar_guard = [1 1 1 1];
params.joint_fft_3d_cfar_train = [1 1 2 2];
params.joint_fft_3d_nms_guard = [1 1 1 1];

params.lambda = params.c / params.fc;
params.d = params.lambda / 2;
required_Rmax = max(params.R_true) + range_margin;
N_per_cc = n_rb * n_sc_per_rb;
B_per_cc = N_per_cc * delta_f_cfg;
B_required = params.c / (2 * target_range_resolution);
if enable_carrier_aggregation
    n_cc = max(1, ceil(B_required / B_per_cc));
else
    n_cc = 1;
end
params.N = n_cc * N_per_cc;
params.B = params.N * delta_f_cfg;
delta_f = params.B / params.N;
T_u = 1 / delta_f;
params.Ts = T_u + T_cp;
range_resolution = params.c / (2 * params.B);
R_max = params.c / (2 * delta_f);

params.tx_array = struct('Nx', 4, 'Ny', 4, 'd', params.d);
params.joint_fft_3d = struct();
params.joint_fft_3d.Na_x = spatial_pad_factor * params.Mx;
params.joint_fft_3d.Na_y = spatial_pad_factor * params.My;
params.joint_fft_3d.Nr = params.N;
params.joint_fft_3d.Nv = doppler_pad_factor * params.K;
params.joint_fft_3d.num_candidates = 15;
params.joint_fft_3d.cfar_pfa = params.joint_fft_3d_cfar_pfa;
params.joint_fft_3d.cfar_guard = params.joint_fft_3d_cfar_guard;
params.joint_fft_3d.cfar_train = params.joint_fft_3d_cfar_train;
params.joint_fft_3d.nms_guard = params.joint_fft_3d_nms_guard;
params.local_esprit = struct();
params.local_esprit.num_candidates = 8;
params.local_esprit.n_samples_range = 384;
params.local_esprit.n_samples_doppler = 48;
params.local_esprit.rd_nms_r = 2;
params.local_esprit.rd_nms_v = 2;

fprintf('参数: 阵列=%dx%d, 单载波子载波=%d, 聚合后等效子载波=%d, 符号=%d, 目标数=%d\n', ...
    params.Mx, params.My, N_per_cc, params.N, params.K, params.num_targets);
fprintf('距离分辨率=%.3fm, 最大不模糊距离=%.1fm\n', params.c/(2*params.B), params.c/(2*(params.B/params.N)));
fprintf('载波频率=%.2fGHz, 子载波间隔=%.3fkHz, OFDM符号周期=%.3fus\n', params.fc/1e9, delta_f/1e3, params.Ts*1e6);
fprintf('3GPP单载波带宽=%.2fMHz, 聚合载波数=%d, 等效总带宽=%.2fMHz\n', B_per_cc/1e6, n_cc, params.B/1e6);
fprintf('验收指标: 目标分辨率=%.3fm, 实际分辨率=%.3fm, 距离覆盖需求=%.1fm, 实际Rmax=%.1fm\n', ...
    target_range_resolution, range_resolution, required_Rmax, R_max);
fprintf('蒙特卡洛次数=%d\n', bw_rmse_mc);

cc_candidates = (max(1, n_cc - bw_rmse_scan_half_width)):(n_cc + bw_rmse_scan_half_width);
cc_candidates = unique(cc_candidates);
bw_vals_mhz = zeros(size(cc_candidates));
rmse_angle_vals = nan(size(cc_candidates));
rmse_R_vals = nan(size(cc_candidates));
rmse_v_vals = nan(size(cc_candidates));
fprintf('\n开始扫描带宽与RMSE关系...\n');
for idx = 1:numel(cc_candidates)
    n_cc_i = cc_candidates(idx);
    params_bw = params;
    params_bw.N = n_cc_i * N_per_cc;
    params_bw.B = params_bw.N * delta_f_cfg;
    params_bw.Ts = 1 / delta_f_cfg + T_cp;
    params_bw.joint_fft_3d.Nr = params_bw.N;
    bw_vals_mhz(idx) = params_bw.B / 1e6;
    rmse_angle_samples = nan(1, bw_rmse_mc);
    rmse_R_samples = nan(1, bw_rmse_mc);
    rmse_v_samples = nan(1, bw_rmse_mc);
    for mc_i = 1:bw_rmse_mc
        try
            tx_i = generate_OFDM_signal(struct('N', params_bw.N, 'K', params_bw.K, 'mod_order', params_bw.mod_order, 'pilot_spacing', params_bw.pilot_spacing));
            rx_i = simulate_radar_channel_3d(tx_i, params_bw);
            if strcmpi(estimator_mode, 'local_esprit')
                [th_i, ph_i, r_i, v_i] = local_ESPRIT_estimator_3d(rx_i, tx_i, params_bw);
            else
                [th_i, ph_i, r_i, v_i] = ZTE_3D_estimator(rx_i, tx_i, params_bw);
            end
            compare_i = evaluate_estimation(th_i, ph_i, r_i, v_i, params_bw, false);
            rmse_angle_samples(mc_i) = compare_i.rmse_angle;
            rmse_R_samples(mc_i) = compare_i.rmse_R;
            rmse_v_samples(mc_i) = compare_i.rmse_v;
        catch
            continue;
        end
    end
    valid_angle_samples = rmse_angle_samples(~isnan(rmse_angle_samples));
    valid_R_samples = rmse_R_samples(~isnan(rmse_R_samples));
    valid_v_samples = rmse_v_samples(~isnan(rmse_v_samples));
    if ~isempty(valid_angle_samples)
        rmse_angle_vals(idx) = mean(valid_angle_samples);
    end
    if ~isempty(valid_R_samples)
        rmse_R_vals(idx) = mean(valid_R_samples);
    end
    if ~isempty(valid_v_samples)
        rmse_v_vals(idx) = mean(valid_v_samples);
    end
    fprintf('带宽=%.2fMHz, RMSE[角度=%.4f°, 距离=%.4fm, 速度=%.4fm/s]\n', ...
        bw_vals_mhz(idx), rmse_angle_vals(idx), rmse_R_vals(idx), rmse_v_vals(idx));
end

valid_angle = rmse_angle_vals(~isnan(rmse_angle_vals));
valid_R = rmse_R_vals(~isnan(rmse_R_vals));
valid_v = rmse_v_vals(~isnan(rmse_v_vals));
impact_angle = 0;
impact_R = 0;
impact_v = 0;
if numel(valid_angle) >= 2
    impact_angle = (max(valid_angle) - min(valid_angle)) / max(min(valid_angle), eps);
end
if numel(valid_R) >= 2
    impact_R = (max(valid_R) - min(valid_R)) / max(min(valid_R), eps);
end
if numel(valid_v) >= 2
    impact_v = (max(valid_v) - min(valid_v)) / max(min(valid_v), eps);
end

impact_vals = [impact_angle, impact_R, impact_v];
metric_names = {'angle', 'range', 'velocity'};
[~, dominant_idx] = max(impact_vals);
dominant_metric = metric_names{dominant_idx};

if strcmp(dominant_metric, 'angle')
    dominant_curve = rmse_angle_vals;
    y_label_text = '角度RMSE (°)';
    title_text = '带宽与角度RMSE关系';
    output_png = 'bandwidth_rmse_dominant_angle.png';
elseif strcmp(dominant_metric, 'range')
    dominant_curve = rmse_R_vals;
    y_label_text = '距离RMSE (m)';
    title_text = '带宽与距离RMSE关系';
    output_png = 'bandwidth_rmse_dominant_range.png';
else
    dominant_curve = rmse_v_vals;
    y_label_text = '速度RMSE (m/s)';
    title_text = '带宽与速度RMSE关系';
    output_png = 'bandwidth_rmse_dominant_velocity.png';
end

figure('Name', '带宽与主导RMSE关系', 'Color', 'w');
plot(bw_vals_mhz, dominant_curve, '-o', 'LineWidth', 1.5, 'MarkerSize', 6);
grid on;
xlabel('等效总带宽 (MHz)');
ylabel(y_label_text);
title(title_text);
saveas(gcf, output_png);

out = struct();
out.n_cc = cc_candidates(:);
out.bandwidth_mhz = bw_vals_mhz(:);
out.rmse_angle = rmse_angle_vals(:);
out.rmse_R = rmse_R_vals(:);
out.rmse_v = rmse_v_vals(:);
out.impact_angle = impact_angle;
out.impact_R = impact_R;
out.impact_v = impact_v;
out.dominant_metric = dominant_metric;
out.dominant_curve = dominant_curve(:);
out.output_png = output_png;
out.params = params;
out.total_runtime = toc(t_total);
save('bandwidth_rmse_scan_results.mat', '-struct', 'out', '-v7.3');
fprintf('带宽影响最大指标: %s\n', dominant_metric);
fprintf('图已保存: %s\n', output_png);
fprintf('结果已保存到 bandwidth_rmse_scan_results.mat\n');
fprintf('总运行时间: %.3f 秒\n', out.total_runtime);
fprintf('=================================================\n');

function compare = evaluate_estimation(theta_est, phi_est, R_est, v_est, params, verbose)
if nargin < 6
    verbose = false;
end

compare = struct();
if isempty(theta_est)
    if verbose
        fprintf('未检测到目标\n');
    end
    compare.match_est_to_true = [];
    compare.theta_err = [];
    compare.phi_err = [];
    compare.R_err = [];
    compare.v_err = [];
    compare.rmse_theta = NaN;
    compare.rmse_phi = NaN;
    compare.rmse_R = NaN;
    compare.rmse_v = NaN;
    return;
end

num_est = numel(theta_est);
num_true = numel(params.theta_true);
used_true = false(1, num_true);
match_est_to_true = zeros(num_est, 1);
theta_err = zeros(num_est, 1);
phi_err = zeros(num_est, 1);
R_err = zeros(num_est, 1);
v_err = zeros(num_est, 1);

for i = 1:num_est
    candidate_set = find(~used_true);
    if isempty(candidate_set)
        candidate_set = 1:num_true;
    end
    best_j = candidate_set(1);
    best_cost = inf;
    for k = 1:numel(candidate_set)
        j = candidate_set(k);
        cost = abs(theta_est(i) - params.theta_true(j)) / 90 + ...
               abs(phi_est(i) - params.phi_true(j)) / 180 + ...
               abs(R_est(i) - params.R_true(j)) / max(1, max(params.R_true)) + ...
               abs(v_est(i) - params.v_true(j)) / max(1, max(abs(params.v_true)));
        if cost < best_cost
            best_cost = cost;
            best_j = j;
        end
    end
    used_true(best_j) = true;
    match_est_to_true(i) = best_j;
    theta_err(i) = theta_est(i) - params.theta_true(best_j);
    phi_err(i) = phi_est(i) - params.phi_true(best_j);
    R_err(i) = R_est(i) - params.R_true(best_j);
    v_err(i) = v_est(i) - params.v_true(best_j);
end

compare.match_est_to_true = match_est_to_true;
compare.theta_err = theta_err;
compare.phi_err = phi_err;
compare.R_err = R_err;
compare.v_err = v_err;
compare.rmse_theta = sqrt(mean(theta_err.^2));
compare.rmse_phi = sqrt(mean(phi_err.^2));
compare.rmse_R = sqrt(mean(R_err.^2));
compare.rmse_v = sqrt(mean(v_err.^2));
compare.rmse_angle = sqrt(0.5 * (compare.rmse_theta^2 + compare.rmse_phi^2));
end
