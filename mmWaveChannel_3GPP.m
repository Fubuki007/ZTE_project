function [H, tau, theta_t, theta_r] = mmWaveChannel_3GPP(Nt, Nr, fc, d, scenario) 
 % 3GPP TR 38.901毫米波信道模型（简化版） 
 % 输入： 
 %   Nt, Nr - 发射/接收天线数 
 %   fc - 载波频率(GHz) 
 %   d  - 收发距离(m) 
 %   scenario - 场景：'UMi'（微蜂窝）或'UMa'（宏蜂窝） 
 % 输出： 
 %   H - 信道矩阵 
 %   tau - 路径时延 
 %   theta_t, theta_r - 发射/接收角度 
 
 fc_GHz = fc/1e9; 
 c = 3e8; 
 lambda = c/fc; 
 
 % 天线阵列（假设ULA） 
 dt = lambda/2; 
 dr = lambda/2; 
 
 % 根据场景设置参数 
 switch scenario 
     case 'UMi' % 城市微蜂窝 
         DS = -6.955 - 0.0963*log10(fc_GHz); % 时延扩展对数正态分布均值 
         ASD = 1.06 + 0.1114*log10(fc_GHz);  % 发射角扩展 
         ASA = 1.81; % 接收角扩展 
         K_dB = 7;   % LOS的K因子(dB) 
         n = 2.1;    % 路径损耗指数 
     case 'UMa' % 城市宏蜂窝 
         DS = -6.28 - 0.204*log10(fc_GHz); 
         ASD = 1.5 - 0.1144*log10(fc_GHz); 
         ASA = 1.75; 
         K_dB = 8; 
         n = 2.35; 
     otherwise 
         error('未知场景'); 
 end 
 
 % 路径损耗 
 PL_dB = 32.4 + 20*log10(fc_GHz) + 10*n*log10(d); 
 PL = 10^(-PL_dB/10); 
 
 % 生成簇（简化：固定簇数） 
 N_cluster = 12; % 簇数 
 N_ray = 20;     % 每簇射线数 
 
 % 簇时延（指数分布） 
 tau = -DS*randn(1, N_cluster); % 对数正态 
 tau = tau - min(tau); % 归一化 
 tau = sort(tau); 
 
 % 簇功率（指数衰减） 
 P = exp(-tau/DS); 
 P = P / sum(P); 
 
 % 簇角度 
 theta_t_cluster = ASD*randn(1, N_cluster); 
 theta_r_cluster = ASA*randn(1, N_cluster); 
 
 % LOS分量（第一个簇） 
 K = 10^(K_dB/10); 
 P(1) = P(1) * K/(K+1); % LOS功率增强 
 P(2:end) = P(2:end) / (K+1); 
 
 % 构建信道矩阵 
 H = zeros(Nr, Nt); 
 for c = 1:N_cluster 
     for r = 1:N_ray 
         % 射线在簇内的偏移角度 
         theta_t_ray = theta_t_cluster(c) + ASD/7*randn; 
         theta_r_ray = theta_r_cluster(c) + ASA/7*randn; 
         
         % 阵列响应向量 
         at = exp(1i*pi*(0:Nt-1)'*sin(theta_t_ray*pi/180))/sqrt(Nt); 
         ar = exp(1i*pi*(0:Nr-1)'*sin(theta_r_ray*pi/180))/sqrt(Nr); 
         
         % 射线复增益 
         alpha = sqrt(P(c)/N_ray) * (randn + 1i*randn)/sqrt(2); 
         
         % 相位项 
         phase = exp(-1i*2*pi*fc*tau(c)*1e-9); 
         
         H = H + alpha * phase * ar * at'; 
     end 
 end 
 
 % 应用路径损耗 
 H = H * sqrt(PL); 
 
 % 输出角度信息 
 theta_t = theta_t_cluster; 
 theta_r = theta_r_cluster; 
 end