function g = channel_geometry(z, p)
% 计算目标几何量与阵列响应。z每行：[距离,速度,俯仰角,方位角]。
% 角度单位为度，俯仰角从+z轴量起。

% ---- 1. 目标位置、方向和路径长度 ----
g.u = [sind(z(:,3)).*cosd(z(:,4)), ...
       sind(z(:,3)).*sind(z(:,4)),cosd(z(:,3))].'; % 基站至目标的单位方向。
g.position = g.u.*z(:,1).'; % 目标三维坐标(m)。
rvec = g.position-p.ris_pos; 
g.rr = sqrt(sum(rvec.^2,1)); % RIS至目标的距离(m)。
g.ur = rvec./g.rr; % RIS至目标的单位方向。
g.vr = sum(g.ur.*g.u,1).*z(:,2).'; % 沿RIS至目标方向的速度(m/s)。
dbr = norm(p.ris_pos); 
br = p.ris_pos/dbr; 
g.distance = [2*z(:,1),dbr+g.rr.'+z(:,1),2*(dbr+g.rr.')]; % 直达、单次及双次经RIS的路程(m)。
g.doppler = [2*z(:,2),z(:,2)+g.vr.',2*g.vr.']/p.lambda; % 对应三类路径的多普勒频率(Hz)。

% ---- 2. 半波长均匀面阵的发送和接收响应 ----
[x,y] = ndgrid(0:p.Ntx-1,0:p.Nty-1);
if isfield(p,'tx_positions')
    positions=p.tx_positions; % 米；所有目标及通信信道共用实际端口坐标。
    assert(isequal(size(positions),[p.Ntx*p.Nty,3]) && all(isfinite(positions),'all'));
else
    positions=p.d*[x(:),y(:),zeros(numel(x),1)];
end
g.transmit = exp(1j*2*pi/p.lambda*positions*g.u);
g.to_ris = exp(1j*2*pi/p.lambda*positions*br);
[x,y] = ndgrid(0:p.Mx-1,0:p.My-1);
g.receive = exp(-1j*pi*(x(:)*g.u(1,:)+y(:)*g.u(2,:))); % 目标方向的接收阵列响应。
g.from_ris = exp(-1j*pi*(x(:)*br(1)+y(:)*br(2))); % RIS方向的接收阵列响应。

% ---- 3. 每个RIS阵元到各目标方向的反射响应 ----
v = ((0:p.ris_side-1)-(p.ris_side-1)/2)*p.d;
[x,y] = ndgrid(v,v);
e1 = [0;1;0]; e2 = cross(p.ris_normal,e1);
offset = e1*x(:).'+e2*y(:).'; % RIS阵元相对中心的位置(m)。
ci = max(0,-p.ris_normal.'*br);
co = max(0,p.ris_normal.'*g.ur); % 入射、出射余弦因子。
gain = p.d^2/p.lambda*sqrt(ci*co).*z(:,1).'./(dbr*g.rr); % 相对直达路径的单阵元反射幅度。
g.V = exp(-1j*2*pi/p.lambda*offset.'*(g.ur-br)).*gain; % 阵元至目标的复反射响应。
if isfield(p,'ris_enabled') && ~p.ris_enabled
    g.V(:)=0; % 无RIS对照使用同一几何、波束优化和精估计链。
end
end
