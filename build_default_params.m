function params = build_default_params(overrides)
% =========================================================================
% BUILD_DEFAULT_PARAMS  构造 ISAC 主流程使用的默认参数结构体
% =========================================================================
% 所有参数均标注了对应的论文符号和公式号:
%   论文 [1]: Z. Xiao et al., "A Novel Joint Angle-Range-Velocity Estimation
%             Method for MIMO-OFDM ISAC Systems," IEEE TSP, vol. 72, 2024.
%   论文 Table II 为默认数值来源.
% =========================================================================

params = struct();

% ====================== 物理常数与载波 ===================================
params.c  = 3e8;       % c: 光速 (m/s)
params.fc = 28e9;      % f_c: 载波频率 (Hz), 论文 Table II

% ====================== 接收阵列 =========================================
% 论文原文: M_rx 个接收天线 (ULA). 本工程扩展为 URA: M_rx = Mx × My.
params.Mx = 8;         % M_rx,x: 接收 URA x 方向天线数
params.My = 8;         % M_rx,y: 接收 URA y 方向天线数
                       % 总接收天线数 M_rx = Mx·My = 64

% ====================== 时域 / CPI =======================================
params.K  = 256;       % L: CPI 内 OFDM 符号数 (论文 Table II: L=256)
                       % 注: 工程变量名用 K 存放, 对应论文符号 L

% ====================== 目标场景 =========================================
params.num_targets = 2;                    % Q: 目标数量
params.theta_true  = [25.83, 15.94];       % θ_q: 各目标俯仰角真值 (度)
params.phi_true    = [28.51, 13.58];       % φ_q: 各目标方位角真值 (度)
params.R_true      = [600.80, 600.20];     % R_q: 各目标径向距离真值 (m)
params.v_true      = [15.1, -5.4];         % v_q: 各目标径向速度真值 (m/s)
params.alpha       = [1.0, 0.8];           % β_q: 各目标复反射系数幅度
params.SNR         = 10;                   % 接收端信噪比 (dB)

% ====================== 自干扰 (SI) 项 ===================================
params.enable_SI            = true;
params.beta_SI              = 0.001;       % SI 相对强度 (相对最强目标幅度)
params.beta_SI_scale_list   = [1, 10, 100, 1000, 10000];
params.beta_SI_scale_names  = {'1倍', '10倍', '100倍', '1000倍', '10000倍'};
params.theta_SI             = 10.5;        % SI 俯仰角 (度)
params.phi_SI               = 10.5;        % SI 方位角 (度)
params.R_SI                 = 10 * (params.c / params.fc);  % SI 距离 ≈ 10λ
params.v_SI                 = 0;           % SI 径向速度 (m/s)

% ====================== 发射端 (MIMO) ====================================
% 论文公式 (2): x_i[l] = W_i · s_i[l]
%   s_i[l] ∈ C^K: 通信符号向量, 16-QAM, 单位平均功率
%   W_i ∈ C^{Ntx×K}: ZF 预编码矩阵
%   x_i[l] ∈ C^{Ntx}: 第 i 子载波第 l 符号的发射信号
params.mod_order     = 16;     % M: QAM 调制阶数 (论文 Table II: 16-QAM)
params.pilot_spacing = 0;      % 不插入导频 (论文假设符号全随机)
params.Ntx      = 4;           % N_tx,x: 发射 URA x 方向天线数
params.Nty      = 4;           % N_tx,y: 发射 URA y 方向天线数
                               % 总发射天线数 N_tx = Ntx·Nty = 16 (论文 Table II)
params.K_stream = 1;           % K: 通信用户/空间流数 (论文 Table II 仿真: K=1)

% ====================== 3GPP FR2 OFDM 参数 ===============================
% 严格遵循 3GPP 5G NR FR2 高频标准 (工程验收要求):
%   --- 单载波 (Component Carrier, CC) 规格 (3GPP TS 38.104, TS 38.211) ---
%   N_RB = 264 个资源块, 每 RB 含 12 个子载波 → 单 CC 子载波数 = 3168
%   Δf = 120 kHz (FR2 子载波间隔, μ=3)
%   单 CC 带宽 B_cc = 3168 × 120 kHz = 380.16 MHz (≤ FR2 最大 400 MHz)
%   T_d = 1/Δf = 8.33 μs, T_cp = 0.6 μs, T = 8.93 μs
%   L = 256 (CPI 内 OFDM 符号数), N_tx = 16, 阵元间距 = λ/2
%   --- 载波聚合 (Carrier Aggregation, 3GPP TS 38.101-2) ---
%   工程验收要求距离分辨率 0.1 m → 需带宽 B ≥ c/(2ΔR) = 1.5 GHz
%   FR2 CA 支持最多 16 个 CC, 本工程聚合 n_cc=4 个 CC:
%     总带宽 B = 4 × 380.16 = 1520.64 MHz (合规, 在 FR2 CA 上限内)
%     距离分辨率 ΔR = c/(2B) ≈ 0.099 m (满足 0.1 m 验收指标)
n_rb                       = 264;      % N_RB: 单 CC 资源块数 (3GPP FR2)
n_sc_per_rb                = 12;       % 每 RB 子载波数
delta_f_cfg                = 120e3;    % Δf: 子载波间隔 (Hz), 3GPP FR2 μ=3
T_cp                       = 0.6e-6;   % T_cp: 循环前缀时长 (s), 3GPP FR2
range_margin               = 15;       % 距离安全裕量 (m)
target_range_resolution    = 0.1;      % 工程验收距离分辨率要求 (m)
enable_carrier_aggregation = true;     % 启用 3GPP FR2 载波聚合 (满足 0.1m 分辨率)

% 估计器开关
params.use_interpolation = true;

% 4D DFT 补零倍数
% 受内存限制 (Na_x*Na_y*Ns*L*16B), 空间维不补零, 改用峰值二次插值
% 提升亚 bin 精度 (论文 Section III-D 结尾提到的 interpolation 补偿)
spatial_pad_factor = 1;    % Na_x = spatial_pad_factor × Mx = 8
doppler_pad_factor = 1;    % Nv   = doppler_pad_factor × L

params.joint_fft_3d_cfar_pfa   = 1e-4;
params.joint_fft_3d_cfar_guard = [1 1 1 1];
params.joint_fft_3d_cfar_train = [1 1 2 2];
params.joint_fft_3d_nms_guard  = [1 1 1 1];

% ====================== 由公式推导的参数 =================================
% 论文公式 (6a): ω_a = -2π d_r sinθ / λ_c
params.lambda = params.c / params.fc;      % λ_c: 波长 (m)
params.d      = params.lambda / 2;         % d = d_r = d_t = λ/2: 阵元间距 (m)

% 载波聚合: 扩展子载波数以满足距离分辨率要求
required_Rmax = max(params.R_true) + range_margin;
N_per_cc      = n_rb * n_sc_per_rb;        % 单载波子载波数
B_per_cc      = N_per_cc * delta_f_cfg;    % 单载波带宽 (Hz)
B_required    = params.c / (2 * target_range_resolution);
if enable_carrier_aggregation
    n_cc = max(1, ceil(B_required / B_per_cc));
else
    n_cc = 1; %#ok<UNRCH>
end
params.N  = n_cc * N_per_cc;               % N_s: 聚合后总子载波数
params.B  = params.N * delta_f_cfg;        % B: 总带宽 (Hz)
delta_f   = params.B / params.N;           % Δf: 子载波间隔 (Hz), 论文式 (6b)
T_u       = 1 / delta_f;                   % T_d: 有效符号时长 (s)
params.Ts = T_u + T_cp;                    % T = T_d + T_cp: 总符号周期 (s), 论文式 (6c)

% 论文式 (25b): ΔR = c / (2·N_s·Δf) = c / (2B)
range_resolution = params.c / (2 * params.B);
% 论文式 (23b): R_max = c / (2Δf)
R_max            = params.c / (2 * delta_f);

% ====================== 结构化参数打包 ===================================
params.tx_array = struct('Nx', params.Ntx, 'Ny', params.Nty, 'd', params.d);

% joint_fft_3d: 传给 joint_angle_range_velocity_estimator 的 DFT 点数
%   Na_x: 空间 x 向 DFT 点数 (论文 N_a, 默认 = M_rx,x)
%   Na_y: 空间 y 向 DFT 点数 (默认 = M_rx,y)
%   Nr:   快时间 DFT 点数 (论文 N_r, 默认 = N_s)
%   Nv:   慢时间 DFT 点数 (论文 N_v, 默认 = L)
params.joint_fft_3d = struct();
params.joint_fft_3d.Na_x = spatial_pad_factor * params.Mx;
params.joint_fft_3d.Na_y = spatial_pad_factor * params.My;
params.joint_fft_3d.Nr   = params.N;
params.joint_fft_3d.Nv   = doppler_pad_factor * params.K;
params.joint_fft_3d.num_candidates = 15;
params.joint_fft_3d.cfar_pfa   = params.joint_fft_3d_cfar_pfa;
params.joint_fft_3d.cfar_guard = params.joint_fft_3d_cfar_guard;
params.joint_fft_3d.cfar_train = params.joint_fft_3d_cfar_train;
params.joint_fft_3d.nms_guard  = params.joint_fft_3d_nms_guard;

% joint_4d: 新版估计器配置
params.joint_4d = struct();
params.joint_4d.num_candidates   = 32;
params.joint_4d.local_topk       = 4;
params.joint_4d.nms_na_x         = 1;
params.joint_4d.nms_na_y         = 1;
params.joint_4d.nms_r            = 2;
params.joint_4d.nms_v            = 2;
params.joint_4d.memory_cap_gb    = 12;
params.joint_4d.use_double_power = false;

% 历史兼容字段 (新估计器不使用)
params.local_esprit = struct();
params.local_esprit.num_candidates       = 8;
params.local_esprit.n_samples_range      = 384;
params.local_esprit.n_samples_doppler    = 48;
params.local_esprit.rd_nms_r             = 2;
params.local_esprit.rd_nms_v             = 2;
params.local_esprit.enable_coeff_removal = false;
params.local_esprit.eps_div              = 1e-6;
params.local_esprit.coeff_refine_blend   = 0.5;

% 派生量 (便于打印/保存)
params.meta = struct( ...
    'N_per_cc', N_per_cc, ...
    'B_per_cc', B_per_cc, ...
    'n_cc', n_cc, ...
    'delta_f', delta_f, ...
    'range_resolution', range_resolution, ...
    'R_max', R_max, ...
    'required_Rmax', required_Rmax, ...
    'target_range_resolution', target_range_resolution);

% ====================== 用户覆盖 ========================================
if nargin >= 1 && ~isempty(overrides) && isstruct(overrides)
    f = fieldnames(overrides);
    for k = 1:numel(f)
        params.(f{k}) = overrides.(f{k});
    end
end
end
