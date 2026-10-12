%RUN_RIS_SIC_MIMO_ZTE  企业 28 GHz MIMO-ISAC 配置下的 RIS-SIC 验证
%
% 复用 ZTE_project 的 28 GHz / 1.52064 GHz / 16发64收 / 3GPP FR2 配置。
% 论文 Wu 2024 的 SISO RIS-SIC 被扩展为 MIMO:
%   H_ris(phi,m) = G_rx(:,:,m) * diag(phi) * G_tx(:,:,m)
%   min_phi sum_m || [H_direct(:,:,m)+H_ris(phi,m)] W(:,:,m) ||_F^2
%
% 输出:
%   zte_ris_mimo_results.mat
%   zte_ris_mimo_summary.csv
%   zte_ris_mimo_results.png

clear; close all; clc;
root = fileparts(mfilename('fullpath'));
addpath(root);
addpath(fullfile(root, '..'));
addpath(fullfile(root, '..', 'RIS_SIC_Wu2024_验证'));
rng(20240920, 'twister');

params = zte_ris_mimo_params();

fprintf('==============================================================\n');
fprintf(' MIMO RIS-SIC validation with ZTE enterprise configuration\n');
fprintf('==============================================================\n');
fprintf('fc=%.2f GHz, B=%.3f GHz, full subcarriers=%d, used subcarriers=%d\n', ...
    params.fc/1e9, params.B/1e9, params.M_full, params.M);
fprintf('Tx=%dx%d (%d), Rx=%dx%d (%d), N_ris=%d, eta=%.2f\n', ...
    params.Ntx, params.Nty, params.Ntx*params.Nty, ...
    params.Mx, params.My, params.Mx*params.My, params.N_ris, params.eta);

% ---------------- 1. 生成 28 GHz MIMO 近场 RIS SI 信道 ----------------
t_ch = tic;
ch = generate_ris_mimo_channels(params);
fprintf('近场 MIMO RIS 信道生成完成: %.1f s\n', toc(t_ch));

% ---------------- 2. 生成企业配置下的发射预编码 W ----------------
% 用现有 generate_mimo_ofdm_waveform 生成一个 ZF 预编码矩阵。
% 这里只用 W，不生成/保存完整大带宽波形。
p_tx = params;
p_tx.N = params.M;
p_tx.K = 8;                 % 少量符号即可
p_tx.K_stream = 1;          % 1 个空间流，降低验证规模
p_tx.precoder_type = 'zf';
p_tx.user_theta_rad = deg2rad(params.theta_true(1));
p_tx.user_phi_rad   = deg2rad(params.phi_true(1));
if isfield(p_tx,'H_SI'), p_tx = rmfield(p_tx,'H_SI'); end
if isfield(p_tx,'H_SI_per_cc'), p_tx = rmfield(p_tx,'H_SI_per_cc'); end

tx = generate_mimo_ofdm_waveform(p_tx);
W = tx.W;                   % Nt x K_stream x M
fprintf('预编码 W 尺寸: %d x %d x %d\n', size(W,1), size(W,2), size(W,3));

% ---------------- 3. 构建展平的 MIMO RIS 目标 ----------------
[h_direct_flat, h_ris_flat, obj_info] = build_mimo_ris_objective(ch, W);
Q = obj_info.Q;
N = ch.N_ris;
fprintf('展平后 Q=%d, N_ris=%d\n', Q, N);

% ---------------- 4. 各种 RIS 配置 ----------------
method_names = {};
phi_list = {};
notes = {};

% 无 RIS
method_names{end+1} = 'No RIS';
phi_list{end+1} = zeros(N,1);
notes{end+1} = 'RIS off';

% 随机相位
phi_rand = exp(1j * 2*pi * rand(N,1));
method_names{end+1} = 'Random phase';
phi_list{end+1} = phi_rand;
notes{end+1} = 'random unit-modulus';

% 连续相位 RCG
t_rcg = tic;
[phi_rcg, info_rcg] = rcg_phase_optimize(h_direct_flat, h_ris_flat, ones(Q,1), params);
method_names{end+1} = 'RCG continuous';
phi_list{end+1} = phi_rcg;
notes{end+1} = sprintf('iter=%d, restart=%d, %.1fs', info_rcg.num_iter, info_rcg.best_restart, toc(t_rcg));

% 离散相位
opt_params = params;
opt_params.weights = ones(Q,1);

for tau = params.tau_list
    phi_npp = phase_quantize_npp(phi_rcg, tau);
    method_names{end+1} = sprintf('NPP tau=%d', tau); %#ok<SAGROW>
    phi_list{end+1} = phi_npp; %#ok<SAGROW>
    notes{end+1} = 'nearest projection'; %#ok<SAGROW>

    [phi_cd, info_cd] = codebook_coordinate_descent(h_direct_flat, h_ris_flat, tau, phi_npp, opt_params);
    method_names{end+1} = sprintf('Codebook CD tau=%d', tau); %#ok<SAGROW>
    phi_list{end+1} = phi_cd; %#ok<SAGROW>
    notes{end+1} = sprintf('sweeps=%d', info_cd.sweeps); %#ok<SAGROW>
end

% 全局随机码表 baseline (tau=4)
[phi_cb, info_cb] = codebook_random_search(h_direct_flat, h_ris_flat, 4, 256, opt_params);
method_names{end+1} = 'Random codebook tau=4 K=256'; %#ok<SAGROW>
phi_list{end+1} = phi_cb; %#ok<SAGROW>
notes{end+1} = sprintf('best k=%d', info_cb.best_k); %#ok<SAGROW>

% ---------------- 5. 评估 ----------------
n_methods = numel(method_names);
results = struct();
fprintf('\n%-34s %14s %14s\n', 'Method', 'Residual(dB)', 'Suppress(dB)');
fprintf('%s\n', repmat('-', 1, 66));

for i = 1:n_methods
    met = eval_mimo_sic(h_direct_flat, h_ris_flat, phi_list{i});
    results(i).name = method_names{i}; %#ok<AGROW>
    results(i).note = notes{i}; %#ok<AGROW>
    results(i).metrics = met; %#ok<AGROW>
    results(i).phi = phi_list{i}; %#ok<AGROW>

    residual_db = 10*log10(max(met.residual_power, eps) / max(met.direct_power, eps));
    fprintf('%-34s %14.2f %14.2f\n', method_names{i}, residual_db, met.suppression_db);
end

% ---------------- 6. 保存 ----------------
out = struct();
out.params = params;
out.ch = ch;
out.W = W;
out.obj_info = obj_info;
out.results = results;
out.info_rcg = info_rcg;
out.timestamp = datestr(now, 'yyyy-mm-dd HH:MM:SS');
save(params.save_mat, '-struct', 'out', '-v7.3');

fid = fopen(params.save_csv, 'w');
fprintf(fid, 'method,note,residual_dB,suppression_dB\n');
for i = 1:n_methods
    met = results(i).metrics;
    residual_db = 10*log10(max(met.residual_power, eps) / max(met.direct_power, eps));
    fprintf(fid, '%s,%s,%.6f,%.6f\n', ...
        results(i).name, results(i).note, residual_db, met.suppression_db);
end
fclose(fid);

% ---------------- 7. 画图 ----------------
fig = figure('Visible','off', 'Color','w', 'Position',[100 100 1100 760]);

subplot(2,2,1);
supp = arrayfun(@(r) r.metrics.suppression_db, results);
bar(supp);
set(gca, 'XTick', 1:n_methods, 'XTickLabel', method_names, 'XTickLabelRotation', 25);
ylabel('SI suppression (dB)');
title('MIMO RIS-SIC, ZTE 28 GHz config');
grid on;

subplot(2,2,2);
hist_db = 10*log10(max(info_rcg.f_history,eps)/max(info_rcg.f_history(1),eps));
plot(0:numel(hist_db)-1, hist_db, 'LineWidth', 1.5);
xlabel('RCG iteration'); ylabel('objective (dB rel.)');
title('RCG convergence'); grid on;

subplot(2,2,3);
plot(angle(phi_rand), 'o', 'DisplayName','random'); hold on;
plot(angle(phi_rcg), 'x', 'DisplayName','RCG');
xlabel('RIS element index'); ylabel('phase (rad)');
title('RIS phase configuration'); legend('show'); grid on;

subplot(2,2,4);
plot(real(phi_rcg), imag(phi_rcg), '.', 'MarkerSize', 10);
axis equal; grid on;
xlabel('Re(\phi)'); ylabel('Im(\phi)');
title('Unit modulus check');

print(fig, params.save_png, '-dpng', '-r150');
close(fig);

fprintf('\n结果已保存:\n  %s\n  %s\n  %s\n', ...
    params.save_mat, params.save_csv, params.save_png);
fprintf('==============================================================\n');

