clear; close all; clc;
fprintf('=================================================\n');
fprintf('  不同子载波数 (N) 下的算法运行时间仿真\n');
fprintf('=================================================\n');

% --- 1. 基础参数初始化 ---
params = struct();
params.c = 3e8;
params.fc = 26.5e9;
params.lambda = params.c / params.fc;
params.B = 1.5e9; 
params.Ts = 5e-6; 
params.d = params.lambda / 2;
params.Mx = 8;  % 固定天线数
params.My = 8;
params.K = 128; % 固定符号数
params.num_targets = 2;
params.theta_true = [28.6, 12.1];
params.phi_true = [8.4, -15.6];
params.R_true = [150.36, 200.78];
params.v_true = [15.1, -5.4];
params.alpha = [1.0, 0.8];
params.SNR = 10;
params.mod_order = 16;     % 16-QAM, 对齐论文
params.pilot_spacing = 0;  % 不再使用
params.use_interpolation = true; 
params.tx_array = struct('Nx', 4, 'Ny', 4, 'd', params.d);

% --- 2. 仿真配置 ---
subcarrier_list = [256, 512, 1024, 2048, 4096, 6144, 8192]; % 子载波数的取值
num_tests = length(subcarrier_list);
time_records = zeros(1, num_tests);

% --- 3. 循环遍历子载波数 ---
for i = 1:num_tests
    N_val = subcarrier_list(i);
    params.N = N_val;
    
    % 更新依赖子载波数的 FFT 参数
    params.joint_fft_3d = struct();
    params.joint_fft_3d.Na_x = 16 * params.Mx; 
    params.joint_fft_3d.Na_y = 16 * params.My; 
    params.joint_fft_3d.Nr = params.N;
    params.joint_fft_3d.Nv = 32 * params.K; 
    params.joint_fft_3d.use_single = true;
    
    fprintf('正在仿真子载波数: %d (%d/%d) ... ', N_val, i, num_tests);
    
    % 1. 生成数据 (发射信号需随N重新生成)
    tx_signal = generate_OFDM_signal(struct('N', params.N, 'K', params.K, 'mod_order', params.mod_order, 'pilot_spacing', params.pilot_spacing));
    rx_cube = simulate_radar_channel_3d(tx_signal, params);
    
    % 2. 预热 (仅为了 MATLAB 内部 JIT 编译公平)
    if i == 1
        joint_angle_range_velocity_estimator(rx_cube, tx_signal, params);
    end
    
    % 3. 正式测时
    t_start = tic;
    joint_angle_range_velocity_estimator(rx_cube, tx_signal, params);
    time_records(i) = toc(t_start);
    
    fprintf('耗时: %.4f 秒\n', time_records(i));
end

% --- 4. 绘图 ---
figure('Name', 'Runtime vs Subcarriers', 'Position', [720, 100, 600, 450]);
plot(subcarrier_list, time_records, '-s', 'Color', '#0072BD', 'LineWidth', 2, 'MarkerSize', 8, 'MarkerFaceColor', '#0072BD');
grid on;
xlabel('子载波数量 (N)', 'FontWeight', 'bold', 'FontSize', 11);
ylabel('算法运行时间 (秒)', 'FontWeight', 'bold', 'FontSize', 11);
title(sprintf('估计算法耗时随子载波数量变化\n(固定参数: 阵列=%dx%d, K=%d)', params.Mx, params.My, params.K), 'FontSize', 13);

% 保存数据
save('Time_vs_Subcarriers_results.mat', 'subcarrier_list', 'time_records');
fprintf('\n仿真完成！结果已保存到 Time_vs_Subcarriers_results.mat\n');