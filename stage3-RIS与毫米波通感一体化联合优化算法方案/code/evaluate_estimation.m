function compare = evaluate_estimation(estimate, p)
% 将估计目标与真值对应，统计距离、速度、俯仰角、方位角和位置误差。
% 匹配仅用于仿真评估，不参与估计器计算。

% ---- 1. 在所有目标排列中寻找与真值对应的匹配关系 ----
orders = perms(1:p.Q);
cost = zeros(size(orders,1),1);
for k = 1:size(orders,1)
    error = estimate(orders(k,:),:)-p.truth;
    error(:,4) = mod(error(:,4)+180,360)-180;
    cost(k) = sum((error./[5 10 10 20]).^2,'all'); % 按参数尺度归一化匹配代价，避免距离量纲主导匹配。
end
[~,index] = min(cost);
compare.estimate = estimate(orders(index,:),:);

% ---- 2. 分别统计参数误差及三维位置误差 ----
compare.error = compare.estimate-p.truth;
compare.error(:,4) = mod(compare.error(:,4)+180,360)-180; % 方位角误差折算到[-180,180)度。
compare.rmse = sqrt(mean(compare.error.^2,1));
position = position_xyz(compare.estimate);
truth = position_xyz(p.truth);
compare.position_rmse = sqrt(mean(sum((position-truth).^2,2)));
end

function xyz = position_xyz(z)
% 将距离、相对z轴的极角及方位角转换为三维位置。
xyz = z(:,1).*[sind(z(:,3)).*cosd(z(:,4)), ...
    sind(z(:,3)).*sind(z(:,4)),cosd(z(:,3))];
end
