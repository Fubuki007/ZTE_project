function perf = evaluate_performance(params, theta_est, R_est, v_est)
    % 性能评估函数
    % 输入: params - 系统参数
    %       theta_est, R_est, v_est - 估计值
    % 输出: perf - 性能指标
    
    % 计算RMSE
    theta_rmse = sqrt(mean((theta_est - params.theta_true).^2));
    range_rmse = sqrt(mean((R_est - params.R_true).^2));
    velocity_rmse = sqrt(mean((v_est - params.v_true).^2));
    
    % 计算相对误差
    theta_rel_error = mean(abs(theta_est - params.theta_true) ./ abs(params.theta_true)) * 100;
    range_rel_error = mean(abs(R_est - params.R_true) ./ abs(params.R_true)) * 100;
    velocity_rel_error = mean(abs(v_est - params.v_true) ./ abs(params.v_true)) * 100;
    
    % 保存结果
    perf = struct(...
        'theta_rmse', theta_rmse, ...
        'range_rmse', range_rmse, ...
        'velocity_rmse', velocity_rmse, ...
        'theta_rel_error', theta_rel_error, ...
        'range_rel_error', range_rel_error, ...
        'velocity_rel_error', velocity_rel_error);
end