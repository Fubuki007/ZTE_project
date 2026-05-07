clear; close all; clc;
warning('off', 'all');

load('ZTE_3D_results.mat');

if ~exist('base_result', 'var') || ~exist('results', 'var')
    error('结果文件中缺少 base_result 或 results，请先运行 main.m');
end

% 取每组结果的 RMSE（若存在多次平均则优先使用均值字段）
n = numel(results);
rmse_theta = zeros(1, n + 1);
rmse_phi = zeros(1, n + 1);
rmse_R = zeros(1, n + 1);
rmse_v = zeros(1, n + 1);

rmse_theta(1) = base_result.compare.rmse_theta;
rmse_phi(1) = base_result.compare.rmse_phi;
rmse_R(1) = base_result.compare.rmse_R;
rmse_v(1) = base_result.compare.rmse_v;

for i = 1:n
    if isfield(results(i), 'rmse_theta_mean') && ~isempty(results(i).rmse_theta_mean)
        rmse_theta(i + 1) = results(i).rmse_theta_mean;
        rmse_phi(i + 1) = results(i).rmse_phi_mean;
        rmse_R(i + 1) = results(i).rmse_R_mean;
        rmse_v(i + 1) = results(i).rmse_v_mean;
    else
        rmse_theta(i + 1) = results(i).compare.rmse_theta;
        rmse_phi(i + 1) = results(i).compare.rmse_phi;
        rmse_R(i + 1) = results(i).compare.rmse_R;
        rmse_v(i + 1) = results(i).compare.rmse_v;
    end
end

x = 1:(n + 1);
xtick_labels = cell(1, n + 1);
xtick_labels{1} = '无SI';
for i = 1:n
    if isfield(results(i), 'label') && ~isempty(results(i).label)
        xtick_labels{i + 1} = results(i).label;
    else
        xtick_labels{i + 1} = sprintf('%dx', results(i).scale);
    end
end

figure('Color', 'w', 'Position', [100, 100, 1500, 520]);

subplot(1, 4, 1);
bar(x, rmse_theta, 0.6);
grid on; box on;
set(gca, 'XTick', x, 'XTickLabel', xtick_labels, 'XTickLabelRotation', 25);
ylabel('RMSE of angle (degree)');
title('Angle');

subplot(1, 4, 2);
bar(x, rmse_phi, 0.6);
grid on; box on;
set(gca, 'XTick', x, 'XTickLabel', xtick_labels, 'XTickLabelRotation', 25);
ylabel('RMSE of azimuth (degree)');
title('Azimuth');

subplot(1, 4, 3);
bar(x, rmse_R, 0.6);
grid on; box on;
set(gca, 'XTick', x, 'XTickLabel', xtick_labels, 'XTickLabelRotation', 25);
ylabel('RMSE of range (m)');
title('Range');

subplot(1, 4, 4);
bar(x, rmse_v, 0.6);
grid on; box on;
set(gca, 'XTick', x, 'XTickLabel', xtick_labels, 'XTickLabelRotation', 25);
ylabel('RMSE of velocity (m/s)');
title('Velocity');

sgtitle('Comparison of no-SI and different SI strengths', 'FontWeight', 'bold');
saveas(gcf, 'SI_effect_compare.png');

fprintf('已生成对比图：SI_effect_compare.png\n');
