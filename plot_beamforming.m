% =========================================================================
% plot_beamforming.m  可视化发射/接收波束方向图
% =========================================================================
% 展示:
%   1. 发射端 ZF 波束方向图 (2D 切面)
%   2. 接收端空间谱 (角度-功率图), 标注真实目标和估计目标位置
%   3. 2D 角度谱热力图 (俯仰 × 方位)
% =========================================================================
clear; close all; clc;

% ---- 1. 加载参数和生成信号 ----
params = build_default_params();
tx = generate_mimo_ofdm_waveform(params);

fprintf('=== 波束方向图可视化 ===\n');
fprintf('发射阵列: %d×%d, 接收阵列: %d×%d\n', ...
    params.Ntx, params.Nty, params.Mx, params.My);
fprintf('载波频率: %.2f GHz, 阵元间距: %.4f m (λ/2)\n', ...
    params.fc/1e9, params.d);

% ---- 2. 发射端 ZF 波束方向图 ----
figure('Name', '发射端ZF波束方向图', 'Position', [100 100 1200 500]);

% 扫描角度范围
theta_scan = linspace(-90, 90, 361);
phi_scan = linspace(-90, 90, 361);

% 取第一个子载波的预编码矩阵
W1 = tx.W(:, :, 1);   % (Ntx*Nty, K_stream)
Ntx = params.Ntx;
Nty = params.Nty;
kw = 2*pi * params.d / params.lambda;

% 俯仰角切面 (固定方位角 = 目标1的方位角)
phi_fixed = params.phi_true(1);
AF_theta = zeros(size(theta_scan));
for ii = 1:numel(theta_scan)
    u = sind(theta_scan(ii)) * cosd(phi_fixed);
    v = sind(theta_scan(ii)) * sind(phi_fixed);
    ax = exp(1j * kw * (0:Ntx-1).' * u);
    ay = exp(1j * kw * (0:Nty-1).' * v);
    a_tx = kron(ay, ax);   % (Ntx*Nty, 1)
    AF_theta(ii) = abs(a_tx' * W1)^2;
end
AF_theta_dB = 10*log10(AF_theta / max(AF_theta) + eps);

subplot(1,2,1);
plot(theta_scan, AF_theta_dB, 'b-', 'LineWidth', 1.5);
hold on;
for q = 1:params.num_targets
    xline(params.theta_true(q), 'r--', sprintf('目标%d: %.1f°', q, params.theta_true(q)), ...
        'LineWidth', 1.2, 'LabelOrientation', 'horizontal');
end
xlabel('俯仰角 θ (°)');
ylabel('归一化增益 (dB)');
title(sprintf('发射波束方向图 (俯仰切面, φ=%.1f°)', phi_fixed));
xlim([-90 90]); ylim([-40 5]);
grid on; legend('ZF波束', 'Location', 'best');

% 方位角切面 (固定俯仰角 = 目标1的俯仰角)
theta_fixed = params.theta_true(1);
AF_phi = zeros(size(phi_scan));
for ii = 1:numel(phi_scan)
    u = sind(theta_fixed) * cosd(phi_scan(ii));
    v = sind(theta_fixed) * sind(phi_scan(ii));
    ax = exp(1j * kw * (0:Ntx-1).' * u);
    ay = exp(1j * kw * (0:Nty-1).' * v);
    a_tx = kron(ay, ax);
    AF_phi(ii) = abs(a_tx' * W1)^2;
end
AF_phi_dB = 10*log10(AF_phi / max(AF_phi) + eps);

subplot(1,2,2);
plot(phi_scan, AF_phi_dB, 'b-', 'LineWidth', 1.5);
hold on;
for q = 1:params.num_targets
    xline(params.phi_true(q), 'r--', sprintf('目标%d: %.1f°', q, params.phi_true(q)), ...
        'LineWidth', 1.2, 'LabelOrientation', 'horizontal');
end
xlabel('方位角 φ (°)');
ylabel('归一化增益 (dB)');
title(sprintf('发射波束方向图 (方位切面, θ=%.1f°)', theta_fixed));
xlim([-90 90]); ylim([-40 5]);
grid on;

sgtitle('发射端 ZF 预编码波束方向图');

% ---- 3. 接收端空间谱 (基于回波数据) ----
params_no_si = params;
params_no_si.enable_SI = false;
tx_signal = tx.X;
rx_cube = simulate_radar_channel_3d(tx_signal, params_no_si);

% 计算接收空间谱: 对所有子载波和符号做 beamforming 扫描
Mx = params.Mx;
My = params.My;
kw_rx = 2*pi * params.d / params.lambda;

% 2D 角度谱
theta_grid = linspace(0, 60, 121);
phi_grid = linspace(-30, 60, 121);
P_2d = zeros(numel(theta_grid), numel(phi_grid));

% 对接收数据在子载波和符号维求平均 (非相干累加)
rx_avg = mean(mean(rx_cube, 4), 3);   % (Mx, My)

for it = 1:numel(theta_grid)
    for ip = 1:numel(phi_grid)
        u = sind(theta_grid(it)) * cosd(phi_grid(ip));
        v = sind(theta_grid(it)) * sind(phi_grid(ip));
        ax = exp(1j * kw_rx * (0:Mx-1).' * u);
        ay = exp(1j * kw_rx * (0:My-1).' * v);
        a_rx = ax * ay.';   % (Mx, My)
        % Beamforming: 空间匹配滤波
        P_2d(it, ip) = abs(sum(sum(conj(a_rx) .* rx_avg)))^2;
    end
end
P_2d_dB = 10*log10(P_2d / max(P_2d(:)) + eps);

figure('Name', '接收端2D角度谱', 'Position', [100 650 700 550]);
imagesc(phi_grid, theta_grid, P_2d_dB);
set(gca, 'YDir', 'normal');
hold on;
% 标注真实目标
for q = 1:params.num_targets
    plot(params.phi_true(q), params.theta_true(q), 'r^', ...
        'MarkerSize', 12, 'MarkerFaceColor', 'r', 'LineWidth', 2);
end
colorbar;
caxis([-30 0]);
xlabel('方位角 φ (°)');
ylabel('俯仰角 θ (°)');
title('接收端 2D 空间谱 (Beamforming)');
colormap(jet);
legend('真实目标', 'Location', 'best');

% ---- 4. 接收端 1D 切面 ----
figure('Name', '接收端空间谱切面', 'Position', [850 650 900 450]);

% 俯仰角切面
subplot(1,2,1);
[~, ip_target1] = min(abs(phi_grid - params.phi_true(1)));
plot(theta_grid, P_2d_dB(:, ip_target1), 'b-', 'LineWidth', 1.5);
hold on;
for q = 1:params.num_targets
    xline(params.theta_true(q), 'r--', sprintf('%.1f°', params.theta_true(q)), ...
        'LineWidth', 1.2);
end
xlabel('俯仰角 θ (°)');
ylabel('归一化功率 (dB)');
title(sprintf('俯仰切面 (φ≈%.1f°)', phi_grid(ip_target1)));
xlim([0 60]); ylim([-30 5]);
grid on;

% 方位角切面
subplot(1,2,2);
[~, it_target1] = min(abs(theta_grid - params.theta_true(1)));
plot(phi_grid, P_2d_dB(it_target1, :), 'b-', 'LineWidth', 1.5);
hold on;
for q = 1:params.num_targets
    xline(params.phi_true(q), 'r--', sprintf('%.1f°', params.phi_true(q)), ...
        'LineWidth', 1.2);
end
xlabel('方位角 φ (°)');
ylabel('归一化功率 (dB)');
title(sprintf('方位切面 (θ≈%.1f°)', theta_grid(it_target1)));
xlim([-30 60]); ylim([-30 5]);
grid on;

sgtitle('接收端空间谱 (Beamforming 扫描)');

fprintf('\n图形已生成完毕。\n');
