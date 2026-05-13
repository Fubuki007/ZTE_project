% =========================================================================
% task1_reproduce_bf.m
% -------------------------------------------------------------------------
% 目的: 复现师兄 bf.m 的结论, 确认 design_precoder + generate_HSI 两个新函
%   数与 bf.m 的 W0/W1/W2 等价.
%
% 场景参数对齐 bf.m:
%   M = 36 发射天线, N = 36 接收天线, K = 4 通信流
%   Hk (通信信道): 瑞利 1/sqrt(2)*(randn+j*randn) (M × K)
%   Hint (自干扰): 10 * [sqrt(κ/(κ+1))·a_rx(-65°)·a_tx(65°)' +
%                         sqrt(1/(κ+1))·瑞利]
%   两组 κ 对比:
%     κ = 1e10 (近 LoS)    —— 师兄截图 2, 预期抑制 ≈ 100 dB
%     κ = 1    (莱斯小κ)  —— 师兄截图 1, 预期抑制 ≈ 20 dB
% =========================================================================
clear; close all; clc;
rng(0);                         % 与 bf.m 同一 seed

M = 36;   % 发射
N = 36;   % 接收
K = 4;    % 通信流

% --- 通信信道 (与 bf.m 完全一致: 瑞利) ---
Hk = 1/sqrt(2) * (randn(M, K) + 1j*randn(M, K));

cases = struct('label', {}, 'kappa', {}, 'expected_db', {});
cases(1) = struct('label', 'κ=1e10 (近 LoS)',   'kappa', 1e10, 'expected_db', 100);
cases(2) = struct('label', 'κ=1    (莱斯小κ)', 'kappa', 1,    'expected_db',  20);

fprintf('=================================================\n');
fprintf('  任务 1: 复现 bf.m 的 3 种预编码抑制效果\n');
fprintf('  M=%d, N=%d, K=%d, seed=0\n', M, N, K);
fprintf('=================================================\n');

for c = 1:numel(cases)
    kap = cases(c).kappa;
    % --- 自干扰信道: 师兄 bf.m 风格 (ULA 外积 + 瑞利, 外层 ×10) ---
    % 我们用 generate_HSI 的 'ula_simple' 模式 (未带 ×10 系数),
    % 然后再乘 10, 让 Hint 与 bf.m 完全一致.
    hsi_cfg = struct( ...
        'model',    'ula_simple', ...
        'Nt_total', M, ...
        'Nr_total', N, ...
        'kappa_SI', kap, ...
        'theta_tx_deg',  65, ...
        'theta_rx_deg', -65, ...
        'seed', []);
    Hint = 10 * generate_HSI(hsi_cfg);

    % --- 三种预编码 ---
    [W0, d0] = design_precoder(Hk, Hint, 'zf',        struct('normalize', true));
    [W1, d1] = design_precoder(Hk, Hint, 'nullspace', struct('normalize', true));
    [W2, d2] = design_precoder(Hk, Hint, 'lagrange',  struct('normalize', true));

    % --- 打印 ---
    fprintf('\n--- %s (kappa=%g) ---\n', cases(c).label, kap);
    fprintf('以下记录 ||Hint*W||^2 (自干扰泄漏功率):\n');
    fprintf('  传统 ZF (未考虑干扰抑制):  %.4g\n', d0.si_leak);
    fprintf('  拉格朗日法 (公式 16):      %.4g\n', d2.si_leak);
    fprintf('  零空间法   (公式 17):      %.4g\n', d1.si_leak);
    supp_ns = 10*log10(max(d0.si_leak, eps) / max(d1.si_leak, eps));
    supp_lg = 10*log10(max(d0.si_leak, eps) / max(d2.si_leak, eps));
    fprintf('  零空间 vs ZF 抑制:    %+.1f dB  (期望 ≈ %d dB)\n', ...
        supp_ns, cases(c).expected_db);
    fprintf('  拉格朗日 vs ZF 抑制:  %+.1f dB  (期望 ≈ %d dB)\n', ...
        supp_lg, cases(c).expected_db);
    fprintf('  通信约束 ||Hk''*W - I||^2: ZF=%.2e, 零空间=%.2e, 拉格朗日=%.2e\n', ...
        d0.comm_err, d1.comm_err, d2.comm_err);
end

fprintf('\n任务 1 完成.\n');
