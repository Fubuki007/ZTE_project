function params = ris_sic_params()
%RIS_SIC_PARAMS  Wu 2024 RIS-SIC 论文复现参数
% 该文件只在独立验证目录中使用，不修改 ZTE_project 主流程。
%
% 主要参考:
%   Wu et al., "RIS-Based Self-Interference Cancellation for
%   Full-Duplex Broadband Transmission", arXiv:2407.12534.
%
% 本函数给出论文第四节使用的 SISO FD 设备内部小型 RIS 参数。

params = struct();

% ------------------- 基本信息 -------------------
params.c  = 3e8;
params.fc = 5.8e9;
params.lambda = params.c / params.fc;

% ------------------- OFDM 参数（论文仿真值） -------------------
params.M   = 128;
params.B   = 20e6;
params.delta_f = params.B / params.M;
params.freq = params.fc - params.B/2 + (0:params.M-1) * params.delta_f;
params.lambda_m = params.c ./ params.freq;

% ------------------- RIS 与设备几何 -------------------
params.N_ris = 36;
params.Nx_ris = round(sqrt(params.N_ris));
params.Ny_ris = round(sqrt(params.N_ris));
if params.Nx_ris * params.Ny_ris ~= params.N_ris
    error('N_ris 需要是完全平方数，当前为 %d', params.N_ris);
end

params.x_t = 0.02;
params.y_t = 0.00;
params.d   = 0.04;
params.d_direct = 2 * params.x_t;

% 反射效率 (论文仿真: eta=beta=0.8)
params.eta = 0.8;

% ------------------- 发射功率与噪声 -------------------
params.P1 = 1;
params.sigma2 = 1e-8;
params.power_alloc = ones(params.M,1) * params.P1 / params.M;
params.weights = ones(params.M,1);

% ------------------- 硬件模型 -------------------
params.hardware_mode = 'F2';
params.tau_list = [2, 4, 8, 16];
params.use_codebook = true;

% ------------------- RCG 优化参数 -------------------
params.rcg = struct();
params.rcg.max_iter = 2000;
params.rcg.tol      = 1e-12;
params.rcg.step0    = 1.0;
params.rcg.alpha    = 1e-4;
params.rcg.beta     = 0.5;
params.rcg.verbose  = false;
params.rcg.n_restarts = 16;

% ------------------- 码表参数 -------------------
params.codebook.random_K = 256;
params.codebook.cd_sweeps = 20;
params.codebook.cd_verbose = false;

% ------------------- 输出控制 -------------------
params.save_dir = fileparts(mfilename('fullpath'));
params.save_mat = fullfile(params.save_dir, 'ris_sic_results.mat');
params.save_png = fullfile(params.save_dir, 'ris_sic_results.png');
params.save_csv = fullfile(params.save_dir, 'ris_sic_summary.csv');

end


