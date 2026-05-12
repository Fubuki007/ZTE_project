clear; close all; clc;
t_total = tic;
warning('off', 'all');
fprintf('=================================================\n');
fprintf('  MIMO-OFDM ISAC 三维联合估计主流程\n');
fprintf('=================================================\n');

params = struct();
% ====================== 可调初始参数（集中配置） ======================
% [物理与载波参数]
params.c = 3e8; % c: 光速(m/s)
params.fc = 28e9; % fc: 载波频率(Hz)

% [阵列与时域采样参数]
params.Mx = 8; % Mx: 接收阵列x方向天线数
params.My = 8; % My: 接收阵列y方向天线数
params.K = 256; % K: 慢时间OFDM符号数(每帧脉冲数)

% [目标场景参数]
params.num_targets = 2; % Q: 目标数量
params.theta_true = [28.83, 15.94]; % theta_true: 俯仰角真值(度)
params.phi_true = [28.51, 13.58]; % phi_true: 方位角真值(度)
params.theta_SI = 10.5; % SI俯仰角(度)
params.phi_SI = 10.5; % SI方位角(度)
params.R_true = [600.80, 600.20]; % R_true: 目标径向距离真值(m)
params.v_true = [15.1, -5.4]; % v_true: 目标径向速度真值(m/s)
params.alpha = [1.0, 0.8]; % alpha: 复反射系数幅度(散射强度)
params.SNR = 10; % SNR: 接收信噪比(dB)

% [自干扰/近端散射项参数]
params.enable_SI = true; % 是否加入SI项
params.beta_SI = 0.001; % beta_SI: SI相对强度（相对最强真实目标的幅度比例）
params.beta_SI_scale_list = [1, 10, 100, 1000, 10000]; % SI强度扫描倍数：1倍、10倍、100倍、1000倍、10000倍
params.beta_SI_scale_names = {'1倍', '10倍', '100倍', '1000倍', '10000倍'}; % 便于汇报和后续修改的文字标签
params.theta_SI = 10.5; % theta_SI: SI项俯仰角(度)
params.phi_SI = 10.5; % phi_SI: SI项方位角(度)
params.R_SI = 10 * (params.c / params.fc); % R_SI: SI项传播距离(约10lambda)
params.v_SI = 0; % v_SI: SI项径向速度(m/s)

% [发射信号参数]
params.mod_order = 16; % M_mod: 调制阶数 (16 表示 16-QAM, 对齐论文 Table II)
params.pilot_spacing = 0; % 已弃用: 新版 generate_OFDM_signal 不再插入导频 (论文 Step 2 要求符号随机)

% [3GPP FR2 OFDM参数]
n_rb = 264; % N_RB: 资源块数量
n_sc_per_rb = 12; % 每个资源块的子载波数
delta_f_cfg = 120e3; % Δf: 子载波间隔(Hz)
T_cp = 0.6e-6; % T_cp: 循环前缀时长(s)
range_margin = 15; % 距离安全裕量(m)，用于覆盖最远目标之外的缓冲
target_range_resolution = 0.1; % 工程验收要求的距离分辨率(m)
enable_carrier_aggregation = true; % 是否启用多载波聚合以扩展等效带宽

% [估计器开关参数]
params.use_interpolation = true; % 启用抛物线插值

% [3D FFT 与检测参数]
spatial_pad_factor = 16; % 空域FFT补零倍数，提升角度栅格精细度
doppler_pad_factor = 32; % 多普勒FFT补零倍数，提升速度栅格精细度
params.joint_fft_3d_cfar_pfa = 1e-4; % CFAR虚警概率
params.joint_fft_3d_cfar_guard = [1 1 1 1]; % CFAR保护单元[ax ay r v]
params.joint_fft_3d_cfar_train = [1 1 2 2]; % CFAR训练单元[ax ay r v]
params.joint_fft_3d_nms_guard = [1 1 1 1]; % NMS邻域抑制窗口[ax ay r v]

% ====================== 由公式推导的参数（一般不手改） ======================
params.lambda = params.c / params.fc; % λ: 波长(m)
params.d = params.lambda / 2; % d: 阵元间距(m)，半波长
required_Rmax = max(params.R_true) + range_margin; % 设计最大不模糊距离需求(m)
N_per_cc = n_rb * n_sc_per_rb; % 单载波子载波总数
B_per_cc = N_per_cc * delta_f_cfg; % 单载波带宽(Hz)
B_required = params.c / (2 * target_range_resolution); % 达到目标分辨率所需总带宽(Hz)
if enable_carrier_aggregation
    n_cc = max(1, ceil(B_required / B_per_cc)); % 载波聚合数
else
    n_cc = 1;
end
params.N = n_cc * N_per_cc; % N: 聚合后的总子载波数
params.B = params.N * delta_f_cfg; % B: 总带宽(Hz)
delta_f = params.B / params.N; % Δf: 子载波间隔(Hz)
T_u = 1 / delta_f; % T_u: 有效符号时长(s)
params.Ts = T_u + T_cp; % Ts: OFDM符号周期(含CP, s)
range_resolution = params.c / (2 * params.B); % ΔR: 距离分辨率(m)
R_max = params.c / (2 * delta_f); % R_max: 最大不模糊距离(m)

% ====================== 结构化参数打包 ======================
params.tx_array = struct('Nx', 4, 'Ny', 4, 'd', params.d); % 发射阵列参数
params.joint_fft_3d = struct();
params.joint_fft_3d.Na_x = spatial_pad_factor * params.Mx; % Na_x: x向角域FFT点数
params.joint_fft_3d.Na_y = spatial_pad_factor * params.My; % Na_y: y向角域FFT点数
params.joint_fft_3d.Nr = params.N; % Nr: 距离FFT点数
params.joint_fft_3d.Nv = doppler_pad_factor * params.K; % Nv: 多普勒FFT点数
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
% 轻量版论文核心思想开关（若影响刷新率可关闭）
params.local_esprit.enable_coeff_removal = false;
params.local_esprit.eps_div = 1e-6;
params.local_esprit.coeff_refine_blend = 0.5;

fprintf('参数: 阵列=%dx%d, 单载波子载波=%d, 聚合后等效子载波=%d, 符号=%d, 目标数=%d\n', ...
    params.Mx, params.My, N_per_cc, params.N, params.K, params.num_targets);
fprintf('距离分辨率=%.3fm, 最大不模糊距离=%.1fm\n', params.c/(2*params.B), params.c/(2*(params.B/params.N)));
fprintf('载波频率=%.2fGHz, 子载波间隔=%.3fkHz, OFDM符号周期=%.3fus\n', params.fc/1e9, delta_f/1e3, params.Ts*1e6);
fprintf('3GPP单载波带宽=%.2fMHz, 聚合载波数=%d, 等效总带宽=%.2fMHz\n', B_per_cc/1e6, n_cc, params.B/1e6);
fprintf('验收指标: 目标分辨率=%.3fm, 实际分辨率=%.3fm, 距离覆盖需求=%.1fm, 实际Rmax=%.1fm\n', ...
    target_range_resolution, range_resolution, required_Rmax, R_max);
tx_signal = generate_OFDM_signal(struct('N', params.N, 'K', params.K, 'mod_order', params.mod_order, 'pilot_spacing', params.pilot_spacing));

% 先估计“真实目标”的接收端等效幅度量级，用它来标定 SI 的相对强度
ref_target_amp = max(abs(params.alpha));
if isfield(params, 'use_physical_pathloss') && params.use_physical_pathloss
    ref_target_amp = ref_target_amp * (params.lambda / (4 * pi * max(params.R_true)))^2;
end
if ref_target_amp <= 0 || ~isfinite(ref_target_amp)
    ref_target_amp = 1;
end

% 先跑一组“无SI”基线，方便和后续干扰结果对比
params_no_si = params;
params_no_si.enable_SI = false;
rx_cube = simulate_radar_channel_3d(tx_signal, params_no_si);
tic;
[theta_est, phi_est, R_est, v_est, info] = joint_angle_range_velocity_estimator(rx_cube, tx_signal, params_no_si);
base_runtime = toc;
base_compare = evaluate_estimation(theta_est, phi_est, R_est, v_est, params_no_si, true);
base_result = struct('label', '无SI', 'beta_SI', 0, 'beta_SI_abs', 0, 'theta_est', theta_est, 'phi_est', phi_est, 'R_est', R_est, 'v_est', v_est, 'info', info, 'compare', base_compare, 'runtime', base_runtime);

scale_list = params.beta_SI_scale_list;
num_mc_si = 10;
results = repmat(struct('scale', [], 'label', [], 'beta_SI', [], 'beta_SI_abs', [], 'theta_est', [], 'phi_est', [], 'R_est', [], 'v_est', [], 'info', [], 'compare', [], 'runtime', [], 'rmse_theta_mean', [], 'rmse_phi_mean', [], 'rmse_R_mean', [], 'rmse_v_mean', []), numel(scale_list), 1);

for idx = 1:numel(scale_list)
    params_run = params;
    params_run.beta_SI_abs = params.beta_SI * ref_target_amp * scale_list(idx);
    fprintf('\n==================== SI强度测试 %d/%d ====================\n', idx, numel(scale_list));
    fprintf('SI强度 = %s, 相对比例 = %.3f, 绝对幅度 = %.3e\n', params.beta_SI_scale_names{idx}, params.beta_SI * scale_list(idx), params_run.beta_SI_abs);

    rmse_theta_mc = nan(1, num_mc_si);
    rmse_phi_mc = nan(1, num_mc_si);
    rmse_R_mc = nan(1, num_mc_si);
    rmse_v_mc = nan(1, num_mc_si);
    theta_est_last = [];
    phi_est_last = [];
    R_est_last = [];
    v_est_last = [];
    info_last = [];

    tic;
    for mc = 1:num_mc_si
        rx_cube = simulate_radar_channel_3d(tx_signal, params_run);
        [theta_est, phi_est, R_est, v_est, info] = joint_angle_range_velocity_estimator(rx_cube, tx_signal, params_run);
        compare = evaluate_estimation(theta_est, phi_est, R_est, v_est, params_run, false);
        rmse_theta_mc(mc) = compare.rmse_theta;
        rmse_phi_mc(mc) = compare.rmse_phi;
        rmse_R_mc(mc) = compare.rmse_R;
        rmse_v_mc(mc) = compare.rmse_v;
        theta_est_last = theta_est;
        phi_est_last = phi_est;
        R_est_last = R_est;
        v_est_last = v_est;
        info_last = info;
    end
    cost_time = toc;

    compare_mean = struct();
    compare_mean.rmse_theta = mean(rmse_theta_mc, 'omitnan');
    compare_mean.rmse_phi = mean(rmse_phi_mc, 'omitnan');
    compare_mean.rmse_R = mean(rmse_R_mc, 'omitnan');
    compare_mean.rmse_v = mean(rmse_v_mc, 'omitnan');

    results(idx).scale = scale_list(idx);
    results(idx).label = params.beta_SI_scale_names{idx};
    results(idx).beta_SI = params.beta_SI * scale_list(idx);
    results(idx).beta_SI_abs = params_run.beta_SI_abs;
    results(idx).theta_est = theta_est_last;
    results(idx).phi_est = phi_est_last;
    results(idx).R_est = R_est_last;
    results(idx).v_est = v_est_last;
    results(idx).info = info_last;
    results(idx).compare = compare_mean;
    results(idx).runtime = cost_time;
    results(idx).rmse_theta_mean = compare_mean.rmse_theta;
    results(idx).rmse_phi_mean = compare_mean.rmse_phi;
    results(idx).rmse_R_mean = compare_mean.rmse_R;
    results(idx).rmse_v_mean = compare_mean.rmse_v;

    fprintf('三维估计完成（joint_arv 4D），用时 %.3f 秒（%d次平均）\n', cost_time, num_mc_si);
    fprintf('平均RMSE: 角度=%.3f°, 方位=%.3f°, 距离=%.3fm, 速度=%.3fm/s\n', compare_mean.rmse_theta, compare_mean.rmse_phi, compare_mean.rmse_R, compare_mean.rmse_v);
end

compare_interp = [];
out = struct();
out.base_result = base_result;
out.results = results;
out.params = params;
out.total_runtime = toc(t_total);
out.compare_interp = compare_interp;
save('ZTE_3D_results.mat', '-struct', 'out', '-v7.3');
fprintf('\n结果已保存到 ZTE_3D_results.mat\n');
fprintf('=================================================\n');
fprintf('无SI基线运行时间: %.3f 秒\n', base_runtime);
fprintf('总运行时间:   %.3f 秒\n', out.total_runtime);
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

if verbose
    disp('估计结果 [theta, phi, R, v]:');
    disp([theta_est(:), phi_est(:), R_est(:), v_est(:)]);
end

num_est = numel(theta_est);
num_true = numel(params.theta_true);
used_true = false(1, num_true);
match_est_to_true = zeros(num_est, 1);
theta_err = zeros(num_est, 1);
phi_err = zeros(num_est, 1);
R_err = zeros(num_est, 1);
v_err = zeros(num_est, 1);

if verbose
    fprintf('\n与真实值对比:\n');
end

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
    if verbose
        fprintf('估计目标%d -> 真实目标%d: ', i, best_j);
        fprintf('角度=%.2f°(真值%.2f°,误差%.2f°), ', theta_est(i), params.theta_true(best_j), theta_err(i));
        fprintf('方位=%.2f°(真值%.2f°,误差%.2f°), ', phi_est(i), params.phi_true(best_j), phi_err(i));
        fprintf('距离=%.2fm(真值%.2fm,误差%.2fm), ', R_est(i), params.R_true(best_j), R_err(i));
        fprintf('速度=%.2fm/s(真值%.2fm/s,误差%.2fm/s)\n', v_est(i), params.v_true(best_j), v_err(i));
    end
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

if verbose
    fprintf('\nRMSE: 角度=%.3f°, 方位=%.3f°, 距离=%.3fm, 速度=%.3fm/s\n', ...
        compare.rmse_theta, compare.rmse_phi, compare.rmse_R, compare.rmse_v);
end
end


