function [W, diag_info] = design_precoder(H_c, H_SI, method, opts)
% =========================================================================
% DESIGN_PRECODER  设计发射端预编码矩阵 W, 对应文档公式 (14)-(17)
% -------------------------------------------------------------------------
% 输入:
%   H_c    (Nt × K)   通信信道 (等效 H_k), 每列对应一个通信用户/空间流
%   H_SI   (Nr × Nt)  自干扰信道
%   method 字符串:
%     'zf'         —— 传统 ZF, 不考虑自干扰 (文档未编号, bf.m 的 W0)
%     'nullspace'  —— 公式 (17), 零空间法 (bf.m 的 W1):
%                      W = W0 - Nc*pinv(H_SI*Nc)*H_SI*W0
%     'lagrange'   —— 公式 (16), 拉格朗日法封闭解 (bf.m 的 W2):
%                      W = R^(-1) H_c (H_c^H R^(-1) H_c)^(-1),  R = H_SI^H H_SI
%
% 可选 opts:
%   opts.normalize (默认 true)  —— 是否对 W 做 Frobenius 归一
%   opts.eps_reg   (默认 1e-9)  —— 拉格朗日法 R 正则项, 防止奇异
%
% 输出:
%   W           (Nt × K) 预编码矩阵
%   diag_info   struct: si_leak (||H_SI*W||_F^2), comm_err (||H_c'*W-I||_F^2)
% =========================================================================

if nargin < 4 || isempty(opts), opts = struct(); end
if ~isfield(opts, 'normalize'), opts.normalize = true; end
if ~isfield(opts, 'eps_reg'),   opts.eps_reg   = 1e-9; end

[Nt, K] = size(H_c);
I_K = eye(K);

switch lower(method)
    case 'zf'
        % W0 = H_c (H_c^H H_c)^(-1)
        W = H_c / (H_c' * H_c);

    case 'nullspace'
        % 先算 W0
        W0 = H_c / (H_c' * H_c);
        % 在 ZF 基础上做零空间修正
        % Nc: H_c^H 的零空间, 即满足 H_c^H * Nc = 0 的基
        Nc = null(H_c');
        if isempty(Nc)
            % 没有零空间自由度, 只能退化成 ZF
            W = W0;
        else
            W = W0 - Nc * pinv(H_SI * Nc) * (H_SI * W0);
        end

    case 'lagrange'
        % R = H_SI^H * H_SI (Nt × Nt)
        R = H_SI' * H_SI + opts.eps_reg * eye(Nt);
        Rinv = R \ eye(Nt);
        M = H_c' * Rinv * H_c;
        W = Rinv * H_c / (M + opts.eps_reg * I_K);

    otherwise
        error('未知 precoder method: %s (可选 zf | nullspace | lagrange)', method);
end

% ------------------- Frobenius 归一 --------------------------------------
if opts.normalize
    fro = norm(W, 'fro');
    if fro > eps
        W = W / fro;
    end
end

% ------------------- 诊断指标 --------------------------------------------
diag_info = struct();
diag_info.si_leak  = norm(H_SI * W, 'fro')^2;
diag_info.comm_err = norm(H_c' * W - I_K, 'fro')^2;   % 通信约束偏差
diag_info.w_fro    = norm(W, 'fro')^2;
diag_info.method   = lower(method);
end
