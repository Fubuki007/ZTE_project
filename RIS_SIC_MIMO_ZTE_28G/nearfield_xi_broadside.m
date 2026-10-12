function xi = nearfield_xi_broadside(r, Rcell)
%NEARFIELD_XI_BROADSIDE  论文式(3)的宽边单胞近似
%
% 当发射/接收天线正对单元中心、没有横向偏移时，式(3)的四个边界组合
% 相同，可化简为:
%   xi = term / pi
% 其中 term 是单个 (x,y) 组合的括号项。
%
% 输入 r 可以是标量或矩阵，输出与 r 同维。

side = sqrt(Rcell);
x = (side/2) ./ r;
rad = sqrt(2*x.^2 + 1);
term = x.^2 ./ (3*(x.^2 + 1).*rad) + (2/3)*atan(x.^2 ./ rad);
xi = term / pi;
xi(xi < 0) = 0;

end
