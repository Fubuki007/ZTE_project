% find_max_dpdOutNN.m
% 加载 nndpdTestData.mat，求 dpdOutNN 的最大幅值

clear; clc;

% 加载数据
data_path = 'C:\Users\Fubuki\Documents\MATLAB\Examples\R2024a\deeplearning_shared\NeuralNetworkDigitalPredistortionOfflineTrainingExample\nndpdTestData.mat';
load(data_path, 'dpdOutNN');

fprintf('dpdOutNN 大小: %dx%d\n', size(dpdOutNN,1), size(dpdOutNN,2));
fprintf('dpdOutNN 类型: %s\n\n', class(dpdOutNN));

% 求最大值
[max_abs, max_idx] = max(abs(dpdOutNN(:)));
[max_row, max_col] = ind2sub(size(dpdOutNN), max_idx);

fprintf('=== 结果 ===\n');
fprintf('dpdOutNN 幅值最大值 = %.6f\n', max_abs);
fprintf('位置: 第 %d 行, 第 %d 列\n', max_row, max_col);
fprintf('该位置复数值 = %.6f + %.6fj\n', real(dpdOutNN(max_row,max_col)), imag(dpdOutNN(max_row,max_col)));

% 统计
fprintf('\n=== 统计 ===\n');
fprintf('均值(幅值)   = %.6f\n', mean(abs(dpdOutNN(:))));
fprintf('标准差(幅值) = %.6f\n', std(abs(dpdOutNN(:))));
fprintf('最小值(幅值) = %.6f\n', min(abs(dpdOutNN(:))));
