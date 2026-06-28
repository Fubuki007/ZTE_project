function compare = evaluate_estimation(theta_est, phi_est, R_est, v_est, params, verbose)
% =========================================================================
% EVALUATE_ESTIMATION  估计结果与真值的就近匹配 + RMSE 统计
% -------------------------------------------------------------------------
% 将估计输出的 (theta, phi, R, v) 与 params.*_true 做贪心最近邻匹配 (按各
% 维度归一化后的 L1 代价), 然后计算逐目标误差和整体 RMSE.
%
% 输入:
%   theta_est, phi_est, R_est, v_est - 估计器输出, 可为空 (未检测到目标)
%   params  - 需包含 theta_true, phi_true, R_true, v_true 四个向量
%   verbose - 是否打印详情 (默认 false)
%
% 输出 (struct):
%   match_est_to_true - 每个估计点对应的真值目标索引
%   theta_err/phi_err/R_err/v_err - 逐目标误差 (列向量)
%   rmse_theta/rmse_phi/rmse_R/rmse_v - 整体 RMSE
% =========================================================================
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
phi_err   = zeros(num_est, 1);
R_err     = zeros(num_est, 1);
v_err     = zeros(num_est, 1);

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
               abs(phi_est(i)   - params.phi_true(j))   / 180 + ...
               abs(R_est(i)     - params.R_true(j))     / max(1, max(params.R_true)) + ...
               abs(v_est(i)     - params.v_true(j))     / max(1, max(abs(params.v_true)));
        if cost < best_cost
            best_cost = cost;
            best_j = j;
        end
    end
    used_true(best_j) = true;
    match_est_to_true(i) = best_j;
    theta_err(i) = theta_est(i) - params.theta_true(best_j);
    phi_err(i)   = phi_est(i)   - params.phi_true(best_j);
    R_err(i)     = R_est(i)     - params.R_true(best_j);
    v_err(i)     = v_est(i)     - params.v_true(best_j);
    if verbose
        fprintf('估计目标%d -> 真实目标%d: ', i, best_j);
        fprintf('角度=%.2f°(真值%.2f°,误差%.2f°), ', theta_est(i), params.theta_true(best_j), theta_err(i));
        fprintf('方位=%.2f°(真值%.2f°,误差%.2f°), ', phi_est(i),   params.phi_true(best_j),   phi_err(i));
        fprintf('距离=%.2fm(真值%.2fm,误差%.2fm), ',    R_est(i),     params.R_true(best_j),     R_err(i));
        fprintf('速度=%.2fm/s(真值%.2fm/s,误差%.2fm/s)\n', v_est(i), params.v_true(best_j), v_err(i));
    end
end

compare.match_est_to_true = match_est_to_true;
compare.theta_err = theta_err;
compare.phi_err   = phi_err;
compare.R_err     = R_err;
compare.v_err     = v_err;
compare.rmse_theta = sqrt(mean(theta_err.^2));
compare.rmse_phi   = sqrt(mean(phi_err.^2));
compare.rmse_R     = sqrt(mean(R_err.^2));
compare.rmse_v     = sqrt(mean(v_err.^2));

if verbose
    fprintf('\nRMSE: 角度=%.3f°, 方位=%.3f°, 距离=%.3fm, 速度=%.3fm/s\n', ...
        compare.rmse_theta, compare.rmse_phi, compare.rmse_R, compare.rmse_v);
end
end
