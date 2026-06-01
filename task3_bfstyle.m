% =========================================================================
% task3_bfstyle.m
% -------------------------------------------------------------------------
% 按照 bf.m 原始公式重写的 task3：三种预编码 × 三种 SI 信道 × 六种 SI 强度
%
% 与 task3_precoder_system_comparison.m 的区别:
%   - 预编码 W 用 bf.m 的原始公式（无 Tikhonov 正则化）
%   - 零空间法用 pinv 而非 Gram\ 
%   - 拉格朗日法用 R\H_c/(H_c'*(R\H_c))，无正则项
%
% bf.m 公式映射（注意: bf.m 注释标签写反了，这里以公式为准）:
%   W0 (ZF):       W = H_c/(H_c'*H_c), Frobenius 归一
%   W1 (零空间):   W = W0 - Nc*pinv(H_SI*Nc)*H_SI*W0,  Nc=null(H_c')
%   W2 (拉格朗日): R = H_SI'*H_SI,  W = R\H_c/(H_c'*(R\H_c))
% =========================================================================
clear; close all; clc;
t_all = tic;
warning('off', 'all');
rng(0);

fprintf('==========================================================\n');
fprintf('  任务 3 (bf.m 风格): 预编码 × SI 信道 系统级对比\n');
fprintf('  预编码公式完全来自 bf.m，无 Tikhonov 正则化\n');
fprintf('==========================================================\n');

% ---- 1. 参数 (复用主流程参数) ----
params = build_default_params();

FAST_MODE = true;
if FAST_MODE
    params.K = 64;
    params.joint_fft_3d.Nv = params.K;
    params.joint_4d.memory_cap_gb = 4;
end

Nt_total = params.Ntx * params.Nty;
Nr_total = params.Mx  * params.My;
K_stream = params.K_stream;
fprintf('规模: Nt=%d, Nr=%d, Ns=%d, L=%d, K=%d, FAST_MODE=%d\n', ...
    Nt_total, Nr_total, params.N, params.K, K_stream, FAST_MODE);
fprintf('Rmax=%.1fm, ΔR=%.3fm\n', params.meta.R_max, params.meta.range_resolution);

% ---- 2. 构造通信信道 H_c (LoS 导向矢量，所有子载波相同) ----
% 与 generate_mimo_ofdm_waveform 中完全一致
user_theta = deg2rad(params.theta_true(1));
user_phi   = deg2rad(params.phi_true(1));

k_wave = 2*pi * params.d / params.lambda;
nx_vec = (0:params.Ntx-1).';
ny_vec = (0:params.Nty-1).';

u = sin(user_theta) * cos(user_phi);
v = sin(user_theta) * sin(user_phi);
ax = exp(1j * k_wave * nx_vec * u);
ay = exp(1j * k_wave * ny_vec * v);
A  = ax * ay.';
H_c = A(:);  % (Nt_total × 1)

fprintf('通信信道 H_c 构造完成 (LoS), ||H_c||=%.4f\n', norm(H_c));

% ---- 3. 通信符号 S (16-QAM) ----
M_qam = 16;
Ns = params.N;
L  = params.K;
DATA = randi([0, M_qam - 1], K_stream, L, Ns);
S = zeros(K_stream, L, Ns);
if exist('qammod', 'file') == 2
    for i = 1:Ns
        S(:, :, i) = qammod(DATA(:, :, i), M_qam, 'UnitAveragePower', true);
    end
else
    mside = round(sqrt(M_qam));
    norm_factor = sqrt((2/3) * (M_qam - 1));
    levels = (2*(0:mside-1) - (mside - 1)) / norm_factor;
    i_idx = mod(DATA, mside) + 1;
    q_idx = floor(DATA / mside) + 1;
    S = levels(i_idx) + 1j * levels(q_idx);
end
fprintf('通信符号生成完成 (16-QAM)\n');

% ---- 4. 实验矩阵 ----
channel_cases = struct('label', {}, 'kappa', {});
channel_cases(1) = struct('label', 'E1_LoS',      'kappa', 1e4);
channel_cases(2) = struct('label', 'E2_mixed',    'kappa', 1);
channel_cases(3) = struct('label', 'E3_Rayleigh', 'kappa', 1e-6);

precoders = {'zf', 'nullspace', 'lagrange'};

si_scale_list = [0, 1, 10, 100, 1000, 10000];
beta_q_max = max(params.alpha);

thr_theta_deg = 2.0;
thr_R_m       = 5.0;

% ---- 5. 主实验循环 ----
fprintf('\n--- 开始实验 ---\n');

results = struct();
results.channel_cases = channel_cases;
results.precoders     = precoders;
results.si_scale_list = si_scale_list;

n_ch   = numel(channel_cases);
n_prec = numel(precoders);
n_sc   = numel(si_scale_list);

data = cell(n_ch, n_prec, n_sc);

for ch_i = 1:n_ch
    kap = channel_cases(ch_i).kappa;
    ch_label = channel_cases(ch_i).label;
    fprintf('\n=========== 信道 %s (κ=%g) ===========\n', ch_label, kap);

    % 生成 H_SI
    hsi_cfg = struct( ...
        'model',    'ura_rician', ...
        'Nt_total', Nt_total, ...
        'Nr_total', Nr_total, ...
        'kappa_SI', kap, ...
        'Ntx', params.Ntx, 'Nty', params.Nty, ...
        'Mx',  params.Mx,  'My',  params.My, ...
        'd_lambda', 0.5, ...
        'theta_tx_deg', params.theta_SI, 'phi_tx_deg', params.phi_SI, ...
        'theta_rx_deg', params.theta_SI, 'phi_rx_deg', params.phi_SI, ...
        'seed', 1234 + ch_i);
    H_SI = generate_HSI(hsi_cfg);
    H_SI = H_SI / norm(H_SI, 'fro') * sqrt(Nt_total * Nr_total);

    for prec_i = 1:n_prec
        pt = precoders{prec_i};
        fprintf('\n  预编码: %-10s\n', pt);

        % ------ 用 bf.m 原始公式设计 W ------
        switch pt
            case 'zf'
                % bf.m W0: W = H_c/(H_c'*H_c)，Frobenius 归一
                W_pre = H_c / (H_c' * H_c);
                f_norm = norm(W_pre, 'fro');
                if f_norm > eps
                    W_pre = W_pre / f_norm;
                end
                % 诊断
                si_leak  = NaN;  % ZF 不涉及 H_SI
                comm_err = norm(H_c' * W_pre - eye(K_stream), 'fro')^2;

            case 'nullspace'
                % bf.m W1 (虽然 bf.m 误标为"拉格朗日"):
                %   Nc = null(H_c'); 
                %   W = W0 - Nc*pinv(H_SI*Nc)*H_SI*W0;
                W0 = H_c / (H_c' * H_c);
                Nc = null(H_c');
                if isempty(Nc)
                    W_pre = W0;
                    fprintf('    警告: 零空间为空，退化为 ZF\n');
                else
                    % 用 pinv 而非 Gram\（与 bf.m 一致）
                    W_pre = W0 - Nc * pinv(H_SI * Nc) * H_SI * W0;
                end
                f_norm = norm(W_pre, 'fro');
                if f_norm > eps
                    W_pre = W_pre / f_norm;
                end
                si_leak  = norm(H_SI * W_pre, 'fro')^2;
                comm_err = norm(H_c' * W_pre - eye(K_stream), 'fro')^2;

            case 'lagrange'
                % bf.m W2 (虽然 bf.m 误标为"零空间法"):
                %   R = H_SI'*H_SI;
                %   W = R\H_c/(H_c'*(R\H_c));
                R = H_SI' * H_SI;
                Rinv_Hc = R \ H_c;
                M_mat = H_c' * Rinv_Hc;
                W_pre = Rinv_Hc / M_mat;
                f_norm = norm(W_pre, 'fro');
                if f_norm > eps
                    W_pre = W_pre / f_norm;
                end
                si_leak  = norm(H_SI * W_pre, 'fro')^2;
                comm_err = norm(H_c' * W_pre - eye(K_stream), 'fro')^2;

            otherwise
                error('未知 precoder: %s', pt);
        end

        fprintf('    诊断: si_leak=%.4g, comm_err=%.4g\n', si_leak, comm_err);

        % ------ 构造发射信号 X = W * S ------
        % W_pre: (Nt_total × K_stream), S: (K_stream × L × Ns)
        % 先扩展 W_pre 到所有子载波: (Nt_total × K_stream × Ns)
        % 注意: 所有子载波用同一个 W（频率平坦假设，与 task3 一致）
        X_flat = zeros(Nt_total, L, Ns);
        for i = 1:Ns
            X_flat(:, :, i) = W_pre * S(:, :, i);
        end
        % reshape + permute → (Ntx, Nty, Ns, L)
        X_4d = reshape(X_flat, params.Ntx, params.Nty, L, Ns);
        X_4d = permute(X_4d, [1, 2, 4, 3]);
        tx_signal = single(X_4d);

        % ------ 对每个 SI 强度跑估计 ------
        for sc_i = 1:n_sc
            scale = si_scale_list(sc_i);
            beta_SI_val = beta_q_max * scale;

            p = params;
            if scale == 0
                p.enable_SI = false;
            else
                p.enable_SI  = true;
                p.beta_SI    = beta_SI_val;
                p.beta_SI_abs= beta_SI_val;
                p.H_SI_matrix = H_SI;
            end

            t_est = tic;
            rx_cube = simulate_radar_channel_3d(tx_signal, p);

            tx_sum = squeeze(sum(sum(tx_signal, 1), 2));
            [th, ph, R, v, ~] = joint_estimator_fast(rx_cube, tx_sum, p);
            rt = toc(t_est);

            cmp = evaluate_estimation(th, ph, R, v, p, false);

            clear rx_cube;

            data{ch_i, prec_i, sc_i} = struct( ...
                'channel',   ch_label, ...
                'kappa',     kap, ...
                'precoder',  pt, ...
                'scale',     scale, ...
                'beta_SI',   beta_SI_val, ...
                'si_leak',   si_leak, ...
                'comm_err',  comm_err, ...
                'compare',   cmp, ...
                'runtime',   rt);

            if isfield(cmp, 'theta_err') && ~isempty(cmp.theta_err)
                et = mean(abs(cmp.theta_err));
                ep = mean(abs(cmp.phi_err));
                eR = mean(abs(cmp.R_err));
                ev = mean(abs(cmp.v_err));
                fprintf('    scale=%-6g : θ=%6.3f° φ=%6.3f° R=%6.2fm v=%5.2fm/s  (%.1fs)\n', ...
                    scale, et, ep, eR, ev, rt);
            else
                fprintf('    scale=%-6g : 估计失败  (%.1fs)\n', scale, rt);
            end
        end
    end
end

results.data = data;
results.total_runtime = toc(t_all);

% ---- 6. 汇总 ----
fprintf('\n==========================================================\n');
fprintf('  汇总: SI 失锁门限 (θ>%.1f° 或 R>%.1fm 即失锁)\n', thr_theta_deg, thr_R_m);
fprintf('==========================================================\n');
fprintf('%-12s | %-10s | %-12s | %-12s | %-10s\n', ...
    '信道', '预编码', '失锁 scale', 'ρ_th (dB)', 'si_leak');
fprintf('%s\n', repmat('-', 1, 70));

summary_tbl = cell(0);
for ch_i = 1:n_ch
    for prec_i = 1:n_prec
        first_fail = NaN;
        sl_report = NaN;
        for sc_i = 1:n_sc
            d = data{ch_i, prec_i, sc_i};
            sl_report = d.si_leak;
            if d.scale == 0, continue; end
            cmp = d.compare;
            if ~isfield(cmp, 'theta_err') || isempty(cmp.theta_err)
                first_fail = d.scale;
                break;
            end
            et = mean(abs(cmp.theta_err));
            eR = mean(abs(cmp.R_err));
            if et > thr_theta_deg || eR > thr_R_m
                first_fail = d.scale;
                break;
            end
        end
        rho_th_db = NaN;
        if ~isnan(first_fail) && first_fail > 0
            rho_th_db = 10 * log10(first_fail);
        end
        ch_label = channel_cases(ch_i).label;
        pt = precoders{prec_i};
        fprintf('%-12s | %-10s | %-12g | %-+12.1f | %-10.3g\n', ...
            ch_label, pt, first_fail, rho_th_db, sl_report);
        summary_tbl{end+1} = struct( ...
            'channel', ch_label, ...
            'precoder', pt, ...
            'first_fail_scale', first_fail, ...
            'rho_th_db', rho_th_db, ...
            'si_leak', sl_report);
    end
    fprintf('%s\n', repmat('-', 1, 70));
end

results.summary = summary_tbl;
results.threshold = struct('theta_deg', thr_theta_deg, 'R_m', thr_R_m);

outfile = 'task3_bfstyle_results.mat';
save(outfile, '-struct', 'results', '-v7.3');
fprintf('\n结果保存到 %s\n', outfile);
fprintf('总耗时: %.1f 分钟\n', results.total_runtime / 60);
