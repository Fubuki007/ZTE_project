function xi = nearfield_xi_cells(t, P, Rcell)
%NEARFIELD_XI_CELLS  论文式(3)的近场单元功率增益
%
% 输入:
%   t      : 3x1 发射/接收天线坐标 [x;y;z]
%   P      : 3xN RIS 单元中心坐标
%   Rcell  : 标量，单元面积 R_m = (lambda_m/5)^2
%
% 输出:
%   xi     : 1xN，每个 RIS 单元的功率增益 xi_{m,t,p}
%
% 说明:
%   这是论文式(3)的向量化实现。每个单元对 x,y 各有两个边界，
%   因此每个单元有 4 个 (x,y) 组合，对 4 项求和后再除以 4*pi。

if nargin < 3 || isempty(Rcell)
    error('nearfield_xi_cells 需要 Rcell');
end

xt = t(1); yt = t(2); d = t(3);
xn = P(1,:); yn = P(2,:);
side = sqrt(Rcell);

% 式(4)(5)的四个边界组合
x1 = side/2 + xn - xt;
x2 = side/2 - xn + xt;
y1 = side/2 + yn - yt;
y2 = side/2 - yn + yt;

% 将四个组合写成同维向量
X = [x1(:), x2(:), x1(:), x2(:)];
Y = [y1(:), y2(:), y2(:), y1(:)];

xd = X / d;
yd = Y / d;
rad = sqrt(xd.^2 + yd.^2 + 1);

term1 = (xd .* yd) ./ (3 * (yd.^2 + 1) .* rad);
term2 = (2/3) * atan((xd .* yd) ./ rad);
S = sum(term1 + term2, 2);   % 每个单元 4 项之和

xi = (S / (4*pi)).';         % 1xN
xi(xi < 0) = 0;              % 数值误差保护

end
