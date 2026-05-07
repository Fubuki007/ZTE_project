function visualize_results(params, rx_signal, ...
    theta_est, R_est, v_est, ...
    perf_esprit, rx_signal_ideal)

    % 集成版结果可视化函数
    
    if nargin < 7
        rx_signal_ideal = [];
    end
    
    fprintf('正在生成核心结果图表...\n');
    
    % ===== 数据准备 =====
    % 1. 构建目标真实参数矩阵 [Range, Angle, Velocity]
    num_targets = params.num_targets;
    true_targets = zeros(num_targets, 3);
    for i = 1:num_targets
        true_targets(i, 1) = params.R_true(i);
        true_targets(i, 2) = params.theta_true(i);
        true_targets(i, 3) = params.v_true(i);
    end
    
    % ===== 窗口1：波束扫描角度谱 =====
    figure('Position', [100, 400, 800, 600], ...
           'Name', 'FFT-ISAC结果: 波束扫描角度谱', ...
           'NumberTitle', 'off', 'Color', 'w');
           
    % 计算FFT角度谱 (基于论文的FFT方法)
    % rx_signal 维度: M x N x K
    [M, N, K] = size(rx_signal);
    
    % 使用空间FFT计算角度谱 (论文方法)
    fft_points_angle = 512;
    angle_fft = fftshift(fft(rx_signal, fft_points_angle, 1), 1);
    angle_power = sum(abs(angle_fft).^2, [2, 3]);
    angle_power = squeeze(angle_power);
    
    % 生成角度轴 (基于论文公式)
    theta_scan = asin((-fft_points_angle/2:fft_points_angle/2-1) * ...
        params.lambda/(fft_points_angle*params.d)) * 180/pi;
    
    % 归一化
    P_spectrum_db = 10*log10(angle_power / max(angle_power));
    
    plot(theta_scan, P_spectrum_db, 'b-', 'LineWidth', 1.5);
    hold on; grid on;
    
    % 标记真实目标角度
    for i = 1:num_targets
        plot([true_targets(i,2), true_targets(i,2)], [-40, 0], 'r--', 'LineWidth', 1);
    end
    
    % 标记估计角度 
    if ~isempty(theta_est)
        plot(theta_est, -5*ones(size(theta_est)), 'g^', ...
             'MarkerSize', 10, 'MarkerFaceColor', 'g');
    end
    
    xlabel('角度 (°)', 'FontSize', 12);
    ylabel('归一化功率 (dB)', 'FontSize', 12);
    title('波束扫描角度谱 (FFT)', 'FontSize', 14);
    legend('角度谱', '真实角度', 'FFT估计', 'Location', 'best');
    xlim([-90, 90]);
    ylim([-40, 5]);
    
    % 保存图片
    saveas(gcf, 'beam_spectrum.png');
    
    % ===== 窗口2：双基站几何示意 =====
    figure('Position', [950, 400, 800, 600], ...
           'Name', 'FFT-ISAC结果: 双基站几何示意', ...
           'NumberTitle', 'off', 'Color', 'w');
           
    hold on; grid on;
    if isfield(params, 'dual_BS') && isfield(params.dual_BS, 'BS_A')
        bs_a = params.dual_BS.BS_A;
    else
        bs_a = [0, 0];
    end
    if isfield(params, 'dual_BS') && isfield(params.dual_BS, 'BS_B')
        bs_b = params.dual_BS.BS_B;
    else
        bs_b = [100, 0];
    end
    bs_a_plot = [bs_a(1), 0];
    bs_b_plot = [bs_b(1), 0];
    
    % 绘制基站
    h_bsa = plot(bs_a_plot(1), bs_a_plot(2), '.', 'MarkerSize', 30, 'Color', [0 0.447 0.741]);
    text(bs_a_plot(1) + 2, bs_a_plot(2), 'BS-A', 'FontSize', 10, 'VerticalAlignment', 'middle');
    
    h_bsb = plot(bs_b_plot(1), bs_b_plot(2), '.', 'MarkerSize', 30, 'Color', [0.85 0.33 0.1]);
    text(bs_b_plot(1) + 2, bs_b_plot(2), 'BS-B', 'FontSize', 10, 'VerticalAlignment', 'middle');
    
    % 计算目标坐标
    target_x = true_targets(:,1) .* cosd(true_targets(:,2));
    target_y = abs(true_targets(:,1) .* sind(true_targets(:,2)));
    
    % 绘制目标
    h_tgt = plot(NaN, NaN, 'o', 'MarkerSize', 8, 'LineWidth', 2, 'Color', [0.9290 0.6940 0.1250]); % Dummy for legend
    
    % 绘制用户
    if isfield(params, 'user_pos')
        user_pos = params.user_pos;
        user_pos_plot = [user_pos(1), -abs(user_pos(2))];
        h_user = plot(user_pos_plot(1), user_pos_plot(2), 'p', 'MarkerSize', 12, 'MarkerFaceColor', 'm', 'MarkerEdgeColor', 'k');
        
        % 数据提示框样式显示用户坐标
        text(user_pos_plot(1) + 5, user_pos_plot(2), sprintf('X %.3f\nY %.4f', user_pos_plot(1), user_pos_plot(2)), ...
             'BackgroundColor', 'w', 'EdgeColor', [0 0.447 0.741], 'FontSize', 9, 'FontWeight', 'bold', 'Color', [0 0.447 0.741]);
        
        text(user_pos_plot(1) + 2, user_pos_plot(2) - 5, 'User', 'FontSize', 10, 'FontWeight', 'bold', 'Color', 'm');
        
        % 绘制基站到用户的通信链路 (实线)
        plot([bs_a_plot(1), user_pos_plot(1)], [bs_a_plot(2), user_pos_plot(2)], '-', 'Color', [0 0.447 0.741], 'LineWidth', 1.5, 'HandleVisibility', 'off');
        plot([bs_b_plot(1), user_pos_plot(1)], [bs_b_plot(2), user_pos_plot(2)], '-', 'Color', [0 0.447 0.741], 'LineWidth', 1.5, 'HandleVisibility', 'off');
    else
        h_user = [];
    end

    colors = {[0.4940 0.1840 0.5560], [0.4660 0.6740 0.1880]}; % 紫色, 绿色
    
    for i = 1:num_targets
        % 绘制目标点 (空心圆圈, 类似图中样式)
        plot(target_x(i), target_y(i), 'o', 'MarkerSize', 8, 'LineWidth', 2, 'Color', [0.9290 0.6940 0.1250]);
        % 目标中心点小黑点
        plot(target_x(i), target_y(i), 'k.', 'MarkerSize', 5);
        
        text(target_x(i) + 5, target_y(i), sprintf('X %.3f\nY %g', target_x(i), target_y(i)), ...
             'BackgroundColor', 'w', 'EdgeColor', [0 0.447 0.741], 'FontSize', 9, 'FontWeight', 'bold', 'Color', [0 0.447 0.741]);
        
        text(target_x(i) + 3, target_y(i) - 5, sprintf('T%d', i), 'FontSize', 10, 'FontWeight', 'bold');
        
        % 连线颜色
        line_color = colors{mod(i-1, length(colors)) + 1};
        
        % BS-A 到 目标连线 (虚线)
        plot([bs_a_plot(1), target_x(i)], [bs_a_plot(2), target_y(i)], '--', 'Color', line_color, 'LineWidth', 1.5, 'HandleVisibility', 'off');
        
        % BS-B 到 目标连线 (虚线)
        plot([bs_b_plot(1), target_x(i)], [bs_b_plot(2), target_y(i)], '--', 'Color', line_color, 'LineWidth', 1.5, 'HandleVisibility', 'off');
        
        % 计算距离
        dist_a = sqrt((target_x(i) - bs_a_plot(1))^2 + (target_y(i) - bs_a_plot(2))^2);
        dist_b = sqrt((target_x(i) - bs_b_plot(1))^2 + (target_y(i) - bs_b_plot(2))^2);
        
        % 标注距离文本 (在线段中间)
        mid_a = [(bs_a_plot(1) + target_x(i))/2, (bs_a_plot(2) + target_y(i))/2];
        mid_b = [(bs_b_plot(1) + target_x(i))/2, (bs_b_plot(2) + target_y(i))/2];
        
        text(mid_a(1), mid_a(2) + 5, sprintf('dA%d=%.1f m', i, dist_a), 'HorizontalAlignment', 'center', 'FontSize', 9);
        text(mid_b(1), mid_b(2) + 5, sprintf('dB%d=%.1f m', i, dist_b), 'HorizontalAlignment', 'center', 'FontSize', 9);
    end
    
    xlabel('X (m)', 'FontSize', 11);
    ylabel('Y (m)', 'FontSize', 11);
    title('两基站与两目标和用户的二维距离关系', 'FontSize', 12);
    grid on;
    box off;
    
    if ~isempty(h_user)
        legend([h_bsa, h_bsb, h_tgt, h_user], {'BS-A', 'BS-B', '目标', '用户'}, 'Location', 'northwest', 'Box', 'on');
    else
        legend([h_bsa, h_bsb, h_tgt], {'BS-A', 'BS-B', '目标'}, 'Location', 'northwest', 'Box', 'on');
    end
    axis equal;
    
    % 调整坐标轴范围以显示所有元素
    all_x = [bs_a_plot(1), bs_b_plot(1), target_x'];
    all_y = [bs_a_plot(2), bs_b_plot(2), target_y'];
    if isfield(params, 'user_pos')
        all_x = [all_x, user_pos_plot(1)];
        all_y = [all_y, user_pos_plot(2)];
    end
    
    xlim([min(all_x) - 20, max(all_x) + 40]);
    ylim([min(all_y) - 20, max(all_y) + 20]);
    x_lim = xlim;
    y_lim = ylim;
    plot([x_lim(1), x_lim(2)], [0, 0], 'k-', 'LineWidth', 1.2, 'HandleVisibility', 'off');
    plot([0, 0], [y_lim(1), y_lim(2)], 'k-', 'LineWidth', 1.2, 'HandleVisibility', 'off');
    dx = 0.05 * (x_lim(2) - x_lim(1));
    dy = 0.05 * (y_lim(2) - y_lim(1));
    quiver(x_lim(2) - dx, 0, dx, 0, 0, 'k', 'LineWidth', 1.2, 'MaxHeadSize', 1.0, 'HandleVisibility', 'off');
    quiver(0, y_lim(2) - dy, 0, dy, 0, 'k', 'LineWidth', 1.2, 'MaxHeadSize', 1.0, 'HandleVisibility', 'off');
    set(gca, 'Layer', 'top');
    
    drawnow;
    
    % 保存图片到本地，防止窗口关闭后丢失
    try
        saveas(gcf, 'simulation_results.png');
        fprintf('图表已保存为 simulation_results.png\n');
    catch
        fprintf('图表保存失败\n');
    end
    
    fprintf('图表绘制完成\n');
end
