function params = zte_ris_mimo_params()
%ZTE_RIS_MIMO_PARAMS  企业项目配置下的 MIMO RIS-SIC 参数
%
% 复用主项目 build_default_params.m 里的 28 GHz / 1.52064 GHz /
% 16发64收 / 3GPP FR2 配置，只覆盖本验证需要的字段:
%   - 选取 M 个代表性子载波而不是全部 12672 个，保证能快速跑通；
%   - 加入 28 GHz 近场 RIS 的几何、反射效率和优化参数。

root = fileparts(mfilename('fullpath'));
addpath(fullfile(root, '..'));                       % ZTE_project 根目录
addpath(fullfile(root, '..', 'RIS_SIC_Wu2024_验证')); % 复用 RCG / 码表函数

base = build_default_params();
params = base;

% ------------------- 企业配置保持不变 -------------------
% params.fc = 28e9
% params.B  = 1.52064e9
% params.Ntx = 4, params.Nty = 4  -> 16 发
% params.Mx  = 8, params.My  = 8  -> 64 收
% params.lambda = 10.714 mm

% ------------------- 取完整带宽内的代表性子载波 -------------------
params.M_full = base.N;                 % 12672
params.M = 64;                          % 验证用 64 个代表性子载波
params.subcarrier_idx = round(linspace(1, params.M_full, params.M));
params.delta_f_full = base.B / base.N;  % 120 kHz
freq_full = params.fc - params.B/2 + (0:params.M_full-1).' * params.delta_f_full;
params.freq = freq_full(params.subcarrier_idx);
params.lambda_m = params.c ./ params.freq;

% ------------------- 28 GHz 内部 RIS 几何 -------------------
% RIS 在 z=0 平面，收发阵列都在 z=d_sep 平面，中心分别在
% (+x_c,0,d_sep) 和 (-x_c,0,d_sep)。
% 这里取亚波长/几波长量级，保证论文近场模型适用。
params.N_ris = 64;                      % 8x8 RIS
params.Nx_ris = 8;
params.Ny_ris = 8;
if params.Nx_ris * params.Ny_ris ~= params.N_ris
    error('N_ris 必须等于 Nx_ris*Ny_ris');
end

params.d_sep_wl = 1.5;                  % 天线平面到 RIS 平面的距离，单位波长
params.x_c_wl   = 1.5;                  % 收发阵列中心到 RIS 中轴的距离，单位波长
params.d_sep = params.d_sep_wl * params.lambda;
params.x_c   = params.x_c_wl   * params.lambda;
params.eta   = 0.8;                     % 反射效率

% ------------------- 优化参数 -------------------
params.weights = ones(params.M,1);      % 子载波权重（后面展平为 Q 维）
params.sigma2  = 1e-8;
params.tau_list = [2, 4, 8, 16];

params.rcg = struct();
params.rcg.max_iter = 1500;
params.rcg.tol      = 1e-10;
params.rcg.step0    = 1.0;
params.rcg.alpha    = 1e-4;
params.rcg.beta     = 0.5;
params.rcg.n_restarts = 8;
params.rcg.verbose  = false;

params.codebook = struct();
params.codebook.random_K = 256;
params.codebook.cd_sweeps = 10;
params.codebook.cd_verbose = false;

% ------------------- 输出路径 -------------------
params.save_dir = root;
params.save_mat = fullfile(root, 'zte_ris_mimo_results.mat');
params.save_csv = fullfile(root, 'zte_ris_mimo_summary.csv');
params.save_png = fullfile(root, 'zte_ris_mimo_results.png');

end

