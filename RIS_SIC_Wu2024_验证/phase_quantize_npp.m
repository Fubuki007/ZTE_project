function phi_q = phase_quantize_npp(phi, tau)
%PHASE_QUANTIZE_NPP  论文式(60)(61)的最近点投影 (NPP)
%
% 将连续相位 phi 投影到 {0, 2*pi/tau, ..., 2*pi*(tau-1)/tau}。

grid = 2*pi * (0:tau-1) / tau;
ang  = angle(phi(:));
D    = abs(angle(exp(1j * (ang - grid))));   % N x tau 角度距离
[~, idx] = min(D, [], 2);
phi_q = exp(1j * grid(idx)).';
end
