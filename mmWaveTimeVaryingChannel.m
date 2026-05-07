function H_t = mmWaveTimeVaryingChannel(Nt, Nr, fc, v, t, delta_t) 
 % 时变毫米波信道（考虑用户移动） 
 % 输入： 
 %   v - 速度向量 [vx, vy, vz] (m/s) 
 %   t - 时间向量 
 %   delta_t - 采样间隔 
 % 输出： 
 %   H_t - 时间维度上的信道矩阵序列 
 
 c = 3e8; 
 lambda = c/fc; 
 
 % 初始信道 
 H0 = mmWaveChannel_SV(Nt, Nr, 10, fc, 100); 
 
 % 生成时变信道 
 num_samples = length(t); 
 H_t = zeros(Nr, Nt, num_samples); 
 
 for n = 1:num_samples 
     % 计算相位变化（多普勒效应） 
     doppler_shift = (v(1)*cosd(0) + v(2)*sind(0))/lambda; % 简化，假设角度0 
     phase_shift = exp(1i*2*pi*doppler_shift*t(n)); 
     
     H_t(:, :, n) = H0 * phase_shift; 
     
     % 模拟信道变化（简化：随机相位扰动） 
     if n > 1 
         random_phase = 0.01*pi*(randn(Nr, Nt) + 1i*randn(Nr, Nt)); 
         H_t(:, :, n) = H_t(:, :, n) .* exp(1i*random_phase); 
     end 
 end 
 end