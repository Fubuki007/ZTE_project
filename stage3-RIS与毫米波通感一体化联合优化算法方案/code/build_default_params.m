function p = build_default_params()

% 物理参数与算法参数集中配置。
% 坐标约定：基站位于原点，角度均使用度。

% ---- 1. 电磁与OFDM波形参数 ----
p.c=3e8;                       % 电磁波传播速度，单位m/s。
p.fc=28e9;                     % 载波中心频率，单位Hz。
p.delta_f=120e3;               % 子载波间隔，单位Hz。

p.N=12672;                       % OFDM的子载波数
p.K=256;                        % 粗估计和精估计各自的符号数

% ---- 2. 基站收发阵列及多目标场景；阵元采用半波长间距 ----
p.Ntx=4;                       % 发射阵，x轴的阵元数。
p.Nty=4;                       % 发射阵，y轴的阵元数。
p.Mx=8;                        % 接收阵，x轴的阵元数。
p.My=8;                        % 接收阵，y轴的阵元数。

% 感知目标
p.R_true=[600.80 600.20]+5*randn(1,2);       % 基站至目标的距离，单位m。
p.v_true=[15.1 -5.4]+2*randn(1,2);           % 径向速度，单位m/s
p.theta_true=[24.63 15.94]+3*randn(1,2);     % 目标俯仰角，单位deg
p.phi_true=[30.99 13.58]+3*randn(1,2);       % 目标方位角，单位deg
p.alpha=[1 .8];               % 各目标往返路径的等效复回波幅度归一化量。
p.SNR=-20;                     % 感知输入SNR，以粗估计直接路径回波平均功率标定噪声。

% ---- 3. RIS规模、相位量化及安装位置 ----
p.ris_side=16;                 % 方形RIS总阵元数为ris_side^2，默认256。
p.ris_bits=2;                  % 每个RIS阵元的相位量化位数；可选相位数为2^ris_bits，默认间隔pi/2。
p.ris_pos=[20;0;0];            % RIS坐标。
p.ris_normal=[-1;0;1]/sqrt(2);  % RIS反射面的单位法向量，决定受照侧和出射方向增益。

% ---- 4. 通信用户位置及SINR约束 ----
p.K_stream=2;                  % 通信用户数。
p.user_R=[600.8 450];             % 用户至基站距离。
p.user_theta=[24.63 45];        % 用户俯仰角，单位deg。
p.user_phi=[30.99 -30];         % 用户方位角，单位deg。
p.comm_noise=.05;              % 通信接收噪声功率，按当前信道和总发射功率归一化。
p.comm_sinr_db=10;             % 各用户所需最低通信SINR。

% ---- 5. 样本抽取规模与固定迭代次数 ----
p.coarse_n=384;                % 粗测角使用的子载波样本数，覆盖整个带宽。
p.coarse_l=64;                 % 粗测角使用的符号样本数，覆盖整个观测时段。
p.fine_n=256;                  % 精估计使用的子载波样本数，覆盖整个带宽。
p.fine_l=64;                   % 两组RIS配置合计的精估计符号样本数。
p.fine_iterations=10;           % 四路径联合精估计的迭代次数。
p.sca_iterations=8;            % 每轮发射波束优化的SCA固定迭代次数。
p.outer_iterations=4;          % 波束与离散相位交替轮数。

% ---- 6. 由物理配置计算波长、带宽、分辨率和目标真值 ----
p.Ts=1/p.delta_f+0.6e-6;       % OFDM符号周期，含0.6微秒循环前缀，单位s。
p.lambda=p.c/p.fc;             % 载波波长。
p.d=p.lambda/2;                % 阵元间距。
p.B=p.N*p.delta_f;             % 总带宽。
p.fref=p.fc-floor(p.N/2)*p.delta_f; % 0号子载波频率。
p.resolution=p.c/(2*p.B);      % 单站往返测距的距离分辨率。
p.Rmax=p.c/(2*p.delta_f);       % 子载波间隔决定的最大无模糊距离。
p.truth=[p.R_true(:),p.v_true(:),p.theta_true(:),p.phi_true(:)]; % 真值矩阵[距离,速度,俯仰角,方位角]。
p.Q=size(p.truth,1);           % 感知目标数量，由真值矩阵行数确定。


% ---- 7. 按通信用户数量整理位置、噪声功率和SINR门限 ----
p.user_R=p.user_R(1:p.K_stream);
p.user_theta=p.user_theta(1:p.K_stream); 
p.user_phi=p.user_phi(1:p.K_stream);
p.comm_noise=p.comm_noise(:).*ones(p.K_stream,1); % 每个用户的噪声功率。
p.comm_sinr_db=p.comm_sinr_db(:).*ones(p.K_stream,1); % 每个用户的SINR门限。

end
