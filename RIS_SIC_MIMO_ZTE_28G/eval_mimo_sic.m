function m = eval_mimo_sic(h_direct_flat, h_ris_flat, phi)
%EVAL_MIMO_SIC  评估展平后的 MIMO 残余 SI
%
% h_direct_flat : Qx1
% h_ris_flat    : NxQ，h_ris_flat' * phi 得到 Qx1 的 RIS 贡献
% phi           : Nx1

if isempty(phi)
    phi = zeros(size(h_ris_flat,1),1);
end

h_eff = h_direct_flat(:) + h_ris_flat' * phi(:);
direct_power   = mean(abs(h_direct_flat).^2);
residual_power = mean(abs(h_eff).^2);

m = struct();
m.direct_power = direct_power;
m.residual_power = residual_power;
m.suppression_db = 10*log10(direct_power / max(residual_power, eps));
m.h_eff = h_eff;
m.phi = phi;
end
