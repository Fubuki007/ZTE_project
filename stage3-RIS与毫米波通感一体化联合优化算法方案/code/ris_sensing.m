function result = ris_sensing(p)
% RIS辅助通感流程。
% RD检测使用完整网格，粗测角和精估计使用覆盖完整观测范围的抽取样本。

% ---- 1. 16QAM、ZF预编码与直达回波 ----
[data, noise_power] = simulate_radar_channel_3d(p);

% ---- 2. 距离/速度检测与二维角度粗估计 ----
[initial, info] = joint_estimator_fast(data, p); % initial每行代表一个目标[距离, 径向速度, 俯仰角, 方位角]
result.coarse = initial;
result.locked = info.locked;
result.estimate = initial; % 未进入精估计时保留粗估计。
result.runtime = info.runtime;
result.sinr = nan(p.K_stream,1);
result.num_paths = 0;
result.design = {};
result.acquisition = 2*p.K*p.Ts; 
result.latency = result.runtime+result.acquisition;
% 如果粗估计没有可靠检测到目标，就结束本次函数，不继续做RIS优化和精估计
if ~info.locked, return; end

% ---- 3. RIS/发射波束设计 ----
t = tic;
obs = cell(2,1);
design = cell(2,1);
g = channel_geometry(initial,p);
rr = g.rr; %RIS到各目标的距离
scale = max(1e-12,p.ris_side^2*p.d^2/p.lambda ...
    *initial(:,1).'./(norm(p.ris_pos)*rr));
times = round(linspace(0,p.K-1,min(p.K,p.fine_l))); % 从完整观测时段均匀选取符号位置。
for s = 1:2 % 两组RIS配置
    symbols = times(s:2:end); 
    obs{s} = prepare_ris_observation(initial,p,symbols);
end
for s = 1:2
    design{s} = optimize_ris_joint(initial,p,(s-1)*pi); % 根据同一粗位置设计两组波束与RIS相位。
    design{s}.scale = scale;
end
result.runtime = result.runtime + toc(t);

% ---- 4. RIS四路径回波接收数据 ----
projected = cell(2,1);
sinr = zeros(p.K_stream,2);
for s = 1:2
    Y = zeros(p.Mx*p.My,size(obs{s}.symbol,2));
    for q = 1:p.Q
        g = channel_geometry(p.truth(q,:),p); % 真值只用于合成回波。
        a.distance = g.distance;
        a.doppler = g.doppler;
        a.space = [g.receive,g.from_ris];
        a.illumination = [g.transmit';g.to_ris']*design{s}.W;
        a.c = (design{s}.phase.'*g.V)*exp(-1j*2*pi*p.fref/p.c ...
            *(norm(p.ris_pos)+g.rr-p.truth(q,1)));
        phase = exp(-1j*2*pi*p.delta_f/p.c*obs{s}.n_grid*a.distance ...
            +1j*2*pi*obs{s}.time_grid*a.doppler);
        signal = (a.illumination*obs{s}.symbol).';
        wave = [phase(:,1).*signal(:,1)+a.c*phase(:,2).*signal(:,2), ...
            a.c*phase(:,2).*signal(:,1)+a.c^2*phase(:,3).*signal(:,2)];
        Y = Y+p.alpha(q)*a.space*wave.'; % 将目标的四条传播路径叠加到接收阵列。
    end
    Y = Y+sqrt(noise_power/2)*(randn(size(Y))+1j*randn(size(Y)));
    
    t = tic;
    projected{s} = reshape(Y*conj(obs{s}.B),[],1);
    result.runtime = result.runtime+toc(t);
    sinr(:,s) = design{s}.sinr;
end

% ---- 5. 仅用RIS阶段回波进行四路径精估计 ----
t = tic;
[result.estimate, fine] = refine_ris_parameters(vertcat(projected{:}),obs,design,initial,p);
result.runtime = result.runtime+toc(t);
result.num_paths = fine.num_paths;
result.sinr = min(sinr,[],2); % 每个通信用户取两组配置中较小的SINR。
result.design = design; % 保存两组发射预编码及离散RIS相位。
result.acquisition = 2*p.K*p.Ts; % 粗估计和精估计两个阶段的理想观测时长。
result.latency = result.runtime+result.acquisition;
end
