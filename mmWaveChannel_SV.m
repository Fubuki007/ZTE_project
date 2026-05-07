function H = mmWaveChannel_SV(Nt, Nr, L, fc, d) 
 % 毫米波SV几何信道模型 
 % 输入： 
 %   Nt - 发射天线数 
 %   Nr - 接收天线数 
 %   L   - 可分辨的路径数（包括LOS和NLOS） 
 %   fc - 载波频率(Hz) 
 %   d  - 收发距离(m) 
 % 输出： 
 %   H - Nr x Nt 信道矩阵 
 
 c = 3e8; % 光速 
 lambda = c/fc; % 波长 
 
 % 天线阵列假设为均匀线阵 
 dt = lambda/2; % 发射天线间距 
 dr = lambda/2; % 接收天线间距 
 
 % 生成L条路径的参数 
 tau = zeros(1, L); % 时延 
 alpha = (randn(1, L) + 1i*randn(1, L))/sqrt(2); % 复增益 
 theta_t = 2*pi*rand(1, L) - pi; % 发射角AOD (Azimuth) 
 theta_r = 2*pi*rand(1, L) - pi; % 接收角AOA (Azimuth) 
 
 % LOS路径（第一条）参数特殊处理 
 tau(1) = d/c; % LOS时延 
 alpha(1) = exp(-1i*2*pi*fc*tau(1)); % LOS相位 
 theta_t(1) = 0; % 假设LOS方向为0度 
 theta_r(1) = 0; 
 
 % NLOS路径参数 
 for l = 2:L 
     tau(l) = tau(1) + 1e-9*randn; % 相对时延，ns级 
     alpha(l) = alpha(l) * exp(-tau(l)/tau(1))/sqrt(L); % 功率衰减 
 end 
 
 % 构建信道矩阵 
 H = zeros(Nr, Nt); 
 for l = 1:L 
     % 发射阵列响应向量 
     at = exp(1i*2*pi*dt/lambda * (0:Nt-1)' * sin(theta_t(l))); 
     % 接收阵列响应向量 
     ar = exp(1i*2*pi*dr/lambda * (0:Nr-1)' * sin(theta_r(l))); 
     % 累加 
     H = H + sqrt(Nt*Nr/L) * alpha(l) * ar * at'; 
 end 
 
 % 添加路径损耗（简化自由空间模型） 
 PL_dB = 20*log10(4*pi*d/lambda); 
 H = H * 10^(-PL_dB/20); 
 end