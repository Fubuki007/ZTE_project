clear; close all; clc;
fprintf('=================================================\n');
fprintf('  不同天线数 (Mx=My) 下的算法运行时间仿真\n');
fprintf('=================================================\n');

% --- 1. 基础参数初始化 ---
params = struct();
params.c = 3e8;
params.fc = 26.5e9;
params.lambda = params.c / params.fc;
params.B = 1.5e9; 
params.N = 1024; % 固定子载波数（为了加快测试速度，不用6144）
params.Ts = 5e-6; 
params.d = params.lambda / 2;
params.K = 128; % 固定符号数
params.num_targets = 2;
params.theta_true = [28.6, 12.1];
params.phi_true = [8.4, -15.6];
params.R_true = [150.36, 200.78];
params.v_true = [15.1, -5.4];
params.alpha = [1.0, 0.8];
params.SNR = 10;
params.mod_order = 4;
params.pilot_spacing = 4;
params.use_interpolation = true; 

% --- 2. 仿真配置 ---
antenna_list = [4, 8, 12, 16, 24, 32]; % Mx = My 的取值
num_tests = length(antenna_list);
time_records = zeros(1, num_tests);

% 提前生成发射信号 (N 和 K 是固定的)
tx_signal = generate_OFDM_signal(struct('N', params.N, 'K', params.K, 'mod_order', params.mod_order, 'pilot_spacing', params.pilot_spacing));

% --- 3. 循环遍历天线数 ---
for i = 1:num_tests
    M = antenna_list(i);
    params.Mx = M;
    params.My = M;
    params.tx_array = struct('Nx', 4, 'Ny', 4, 'd', params.d);
    
    % 更新依赖天线数的 FFT 参数
    params.joint_fft_3d = struct();
    params.joint_fft_3d.Na_x = 16 * params.Mx; 
    params.joint_fft_3d.Na_y = 16 * params.My; 
    params.joint_fft_3d.Nr = params.N;
    params.joint_fft_3d.Nv = 32 * params.K; 
    params.joint_fft_3d.use_single = true;
    
    fprintf('正在仿真天线阵列规模: %d x %d (%d/%d) ... ', M, M, i, num_tests);
    
    % 1. 生成数据
    rx_cube = simulate_radar_channel_3d(tx_signal, params);
    
    % 2. 预热 (仅为了 MATLAB 内部 JIT 编译公平，不计入正式时间)
    if i == 1
        ZTE_3D_estimator(rx_cube, tx_signal, params);
    end
    
    % 3. 正式测时
    t_start = tic;
    ZTE_3D_estimator(rx_cube, tx_signal, params);
    time_records(i) = toc(t_start);
    
    fprintf('耗时: %.4f 秒\n', time_records(i));
end

% --- 4. 绘图 ---
figure('Name', 'Runtime vs Antennas', 'Position', [100, 100, 600, 450]);
plot(antenna_list.^2, time_records, '-o', 'Color', '#A2142F', 'LineWidth', 2, 'MarkerSize', 8, 'MarkerFaceColor', '#A2142F');
grid on;
xlabel('总天线数 (M_x \times M_y)', 'FontWeight', 'bold', 'FontSize', 11);
ylabel('算法运行时间 (秒)', 'FontWeight', 'bold', 'FontSize', 11);
title(sprintf('估计算法耗时随天线数量变化\n(固定参数: N=%d, K=%d)', params.N, params.K), 'FontSize', 13);

% 保存数据
save('Time_vs_Antennas_results.mat', 'antenna_list', 'time_records');
fprintf('\n仿真完成！结果已保存到 Time_vs_Antennas_results.mat\n');