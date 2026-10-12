function m = eval_sic_performance(h_direct, h_ris, phi, params)
%EVAL_SIC_PERFORMANCE  评估 RIS-SIC 效果
%
% 返回:
%   m.residual_power  : 残余 SI 平均功率
%   m.direct_power    : 无 RIS 时直达 SI 平均功率
%   m.suppression_db  : 10*log10(直达功率/残余功率)
%   m.sic_cap_db      : 论文式(20)的 SIC capability
%
% 说明:
%   式(20)是 sum_m (P_before,m / P_after,m)。
%   另外单独给 suppression_db，表示纯粹残余 SI 功率下降，避免噪声底
%   把 SIC capability 截断后看不出 RIS 相位优化的真实效果。

if nargin < 4 || isempty(params)
    params = ris_sic_params();
end

h_direct = h_direct(:);
if isempty(phi)
    phi = zeros(size(h_ris,1),1);
end
phi = phi(:);

h_eff = h_direct + h_ris' * phi;

direct_power   = mean(abs(h_direct).^2);
residual_power = mean(abs(h_eff).^2);

P_before = abs(h_direct).^2 .* params.power_alloc + params.sigma2;
P_after  = abs(h_eff).^2   .* params.power_alloc + params.sigma2;

m = struct();
m.direct_power   = direct_power;
m.residual_power = residual_power;
m.suppression_db = 10*log10(direct_power / max(residual_power, eps));
m.sic_cap_db     = 10*log10(sum(P_before ./ P_after));
m.h_eff = h_eff;
m.phi = phi;
m.phi_angle = angle(phi);
end
