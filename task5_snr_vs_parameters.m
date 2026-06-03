% =========================================================================
% task5_snr_vs_parameters.m
% -------------------------------------------------------------------------
% 扫描输出 SNR 随三个关键参数的变化:
%   Fig 1: Output SNR vs 接收天线数 N_rx
%   Fig 2: Output SNR vs 子载波数 N_s
%   Fig 3: Output SNR vs CPI 长度 L
%
% 三种预编码: ZF / Nullspace / Lagrange, 三条曲线
%
% 理论公式:
%   SNR_out = SNR_in * G_tx * N_rx * N_s * L
%   其中 G_tx = |a_tx(theta_target)^H * W|^2 / |W|^2
%
% 输出: 三个 JSON 文件供 Python 绘图
% =========================================================================
clear; close all; clc;
rng(42);
t_all = tic;

% ---- 0. 加载默认参数 ----
params = build_default_params();
Nt = params.Ntx * params.Nty;          % 16 发射天线
Nr0 = params.Mx * params.My;           % 64 接收天线
Ns0 = params.N;                         % 12672 子载波
L0  = params.K;                         % 256 OFDM 符号
SNR_in_dB = params.SNR;                % 10 dB 输入 SNR
kw = 2 * pi * params.d / params.lambda;

fprintf('============================================================\n');
fprintf('  Task 5: Output SNR vs 参数扫描\n');
fprintf('  Nt=%d, Nr0=%d, Ns0=%d, L0=%d, SNR_in=%.0f dB\n', ...
    Nt, Nr0, Ns0, L0, SNR_in_dB);
fprintf('============================================================\n\n');

% ---- 构建导向矢量 ----
% 通信用户方向 = 第一个目标方向 (论文设定: user 即 target)
theta_u = params.theta_true(1);  phi_u = params.phi_true(1);
a_c = build_steering_vec(theta_u, phi_u, params.Ntx, params.Nty, kw);
H_c0 = a_c(:);  % (Nt, 1), K_stream=1

% 两个目标方向
a_t1 = build_steering_vec(params.theta_true(1), params.phi_true(1), ...
    params.Ntx, params.Nty, kw);
a_t2 = build_steering_vec(params.theta_true(2), params.phi_true(2), ...
    params.Ntx, params.Nty, kw);
A_targets = [a_t1(:), a_t2(:)];  % (Nt, 2)

% =========================================================================
% Part 1: 计算默认参数下三种预编码的 G_tx 基准
% =========================================================================
precoder_names  = {'ZF', 'Nullspace', 'Lagrange'};
precoder_types  = {'zf', 'nullspace', 'lagrange'};
n_prec = 3;

M0 = sqrt(Nr0);
H_SI0 = gen_SI_channel(Nt, Nr0, M0, 1e4, params);
H_SI0 = H_SI0 / norm(H_SI0, 'fro') * sqrt(Nt * Nr0);

G_tx0_dB = zeros(1, n_prec);
fprintf('--- 默认参数预编码波束增益 (Nr=%d, kappa_SI=1e4) ---\n', Nr0);
for p = 1:n_prec
    [W0, ~] = design_precoder(H_c0, H_SI0, precoder_types{p});
    G_tx0_dB(p) = compute_radar_gain(W0, A_targets);
    fprintf('  %-12s: G_tx = %+.2f dB\n', precoder_names{p}, G_tx0_dB(p));
end
fprintf('\n');

% =========================================================================
% Part 2: 扫描接收天线数 N_rx
% =========================================================================
fprintf('--- 扫描 N_rx (接收天线数) ---\n');
M_list = [2, 3, 4, 5, 6, 7, 8, 10];
Nr_list = M_list.^2;
snr_vs_nrx = zeros(n_prec, numel(Nr_list));

for i = 1:numel(Nr_list)
    Nr_i = Nr_list(i);  M_i = M_list(i);
    fprintf('  Nr=%3d (M=%d): ', Nr_i, M_i);
    H_SI_i = gen_SI_channel(Nt, Nr_i, M_i, 1e4, params);
    H_SI_i = H_SI_i / norm(H_SI_i, 'fro') * sqrt(Nt * Nr_i);
    
    for p = 1:n_prec
        [W_i, ~] = design_precoder(H_c0, H_SI_i, precoder_types{p});
        G_i = compute_radar_gain(W_i, A_targets);
        snr_vs_nrx(p, i) = SNR_in_dB + G_i ...
            + 10*log10(Nr_i) + 10*log10(Ns0) + 10*log10(L0);
        fprintf('%s=%.1f ', precoder_names{p}, snr_vs_nrx(p, i));
    end
    fprintf('\n');
end
fprintf('\n');

% =========================================================================
% Part 3: 扫描子载波数 N_s
% =========================================================================
fprintf('--- 扫描 N_s (子载波数) ---\n');
Ns_list = [1584, 3168, 6336, 9504, 12672, 19008, 25344, 38016, 50688];
snr_vs_ns = zeros(n_prec, numel(Ns_list));
for i = 1:numel(Ns_list)
    Ns_i = Ns_list(i);
    fprintf('  Ns=%6d: ', Ns_i);
    for p = 1:n_prec
        snr_vs_ns(p, i) = SNR_in_dB + G_tx0_dB(p) ...
            + 10*log10(Nr0) + 10*log10(Ns_i) + 10*log10(L0);
        fprintf('%s=%.1f ', precoder_names{p}, snr_vs_ns(p, i));
    end
    fprintf('\n');
end
fprintf('\n');

% =========================================================================
% Part 4: 扫描 CPI 长度 L
% =========================================================================
fprintf('--- 扫描 L (CPI 长度) ---\n');
L_list = [16, 32, 64, 128, 256, 512, 1024];
snr_vs_l = zeros(n_prec, numel(L_list));
for i = 1:numel(L_list)
    L_i = L_list(i);
    fprintf('  L=%4d: ', L_i);
    for p = 1:n_prec
        snr_vs_l(p, i) = SNR_in_dB + G_tx0_dB(p) ...
            + 10*log10(Nr0) + 10*log10(Ns0) + 10*log10(L_i);
        fprintf('%s=%.1f ', precoder_names{p}, snr_vs_l(p, i));
    end
    fprintf('\n');
end
fprintf('\n');

% =========================================================================
% Part 5: 导出 JSON
% =========================================================================
out_dir = fullfile(pwd, 'task5_results');
if ~exist(out_dir, 'dir'), mkdir(out_dir); end

write_snr_json(fullfile(out_dir, 'snr_vs_nrx.json'), ...
    Nr_list, snr_vs_nrx, precoder_names);
write_snr_json(fullfile(out_dir, 'snr_vs_ns.json'), ...
    Ns_list, snr_vs_ns, precoder_names);
write_snr_json(fullfile(out_dir, 'snr_vs_l.json'), ...
    L_list, snr_vs_l, precoder_names);

save(fullfile(out_dir, 'task5_snr_scan_results.mat'), ...
    'Nr_list', 'Ns_list', 'L_list', ...
    'snr_vs_nrx', 'snr_vs_ns', 'snr_vs_l', ...
    'precoder_names', 'G_tx0_dB', ...
    'SNR_in_dB', 'Nr0', 'Ns0', 'L0', 'Nt', '-v7.3');

fprintf('=== 数据保存完毕 ===\n');
fprintf('JSON 文件:\n');
fprintf('  %s\\snr_vs_nrx.json\n', out_dir);
fprintf('  %s\\snr_vs_ns.json\n', out_dir);
fprintf('  %s\\snr_vs_l.json\n', out_dir);
fprintf('MAT 文件:\n');
fprintf('  %s\\task5_snr_scan_results.mat\n', out_dir);
fprintf('总耗时: %.1f 秒\n', toc(t_all));

% =========================================================================
% ==== 局部函数 ============================================================
% =========================================================================

function a = build_steering_vec(theta_deg, phi_deg, Ntx, Nty, kw)
    % 构建 2D URA 发射导向矢量
    u = sind(theta_deg) * cosd(phi_deg);
    v = sind(theta_deg) * sind(phi_deg);
    ax = exp(1j * kw * (0:Ntx-1).' * u);
    ay = exp(1j * kw * (0:Nty-1).' * v);
    A = ax * ay.';  % (Ntx, Nty)
    a = A(:);        % 列主序展平
end

function H_SI = gen_SI_channel(Nt, Nr, M, kap, params)
    % 生成 SI 信道矩阵
    hsi_cfg = struct(...
        'model',     'ura_rician', ...
        'Nt_total',  Nt, ...
        'Nr_total',  Nr, ...
        'kappa_SI',  kap, ...
        'Ntx', params.Ntx, 'Nty', params.Nty, ...
        'Mx',  M, 'My', M, ...
        'd_lambda', 0.5, ...
        'theta_tx_deg', params.theta_SI, 'phi_tx_deg', params.phi_SI, ...
        'theta_rx_deg', params.theta_SI, 'phi_rx_deg', params.phi_SI, ...
        'seed', 1234);
    H_SI = generate_HSI(hsi_cfg);
end

function G_dB = compute_radar_gain(W, A_targets)
    % 计算预编码器对雷达目标的发射波束增益 (dB)
    % W: (Nt, K) 预编码矩阵
    % A_targets: (Nt, Q) 目标方向导向矢量
    W_norm2 = norm(W, 'fro')^2;
    Q = size(A_targets, 2);
    G_linear = zeros(1, Q);
    for q = 1:Q
        G_linear(q) = abs(A_targets(:, q)' * W)^2 / W_norm2;
    end
    G_dB = 10 * log10(max(mean(G_linear), eps));
end

function write_snr_json(fpath, x_vals, snr_data, series_names)
    % 写出 academic-figures 兼容的 JSON
    fid = fopen(fpath, 'w');
    fprintf(fid, '{\n');
    fprintf(fid, '  "labels": [');
    fprintf(fid, '%d', x_vals(1));
    for i = 2:numel(x_vals), fprintf(fid, ', %d', x_vals(i)); end
    fprintf(fid, '],\n');
    fprintf(fid, '  "series": {\n');
    n_series = numel(series_names);
    for p = 1:n_series
        fprintf(fid, '    "%s": [', series_names{p});
        fprintf(fid, '%.2f', snr_data(p, 1));
        for i = 2:numel(x_vals)
            fprintf(fid, ', %.2f', snr_data(p, i));
        end
        fprintf(fid, ']');
        if p < n_series, fprintf(fid, ','); end
        fprintf(fid, '\n');
    end
    fprintf(fid, '  }\n');
    fprintf(fid, '}\n');
    fclose(fid);
end
