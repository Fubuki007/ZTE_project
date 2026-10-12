%RUN_RIS_SIC_MAIN  论文 Wu 2024 RIS-SIC 独立验证主脚本
%
% 直接运行:
%   run_ris_sic_main
%
% 该脚本不修改 ZTE_project 主流程，只在当前文件夹内生成:
%   ris_sic_results.mat
%   ris_sic_summary.csv
%   ris_sic_results.png

clear; close all; clc;
root = fileparts(mfilename('fullpath'));
addpath(root);

params = ris_sic_params();
rng(20240920, 'twister');

fprintf('=====================================================\n');
fprintf(' RIS-based SIC validation (Wu 2024, arXiv:2407.12534)\n');
fprintf('=====================================================\n');
fprintf('fc=%.2f GHz, B=%.1f MHz, M=%d, N_ris=%d, eta=%.2f\n', ...
    params.fc/1e9, params.B/1e6, params.M, params.N_ris, params.eta);

% ---------------- 1. 生成近场 SI 信道 ----------------
ch = generate_ris_si_channels(params);
N = params.N_ris;

% ---------------- 2. 准备不同 RIS 配置 ----------------
method_names = {};
phi_list = {};
notes = {};

% 无 RIS / 直达 SI
method_names{end+1} = 'No RIS';
phi_list{end+1}    = zeros(N,1);
notes{end+1}       = '直达 SI，RIS 关闭';

% 随机相位基准
phi_rand = exp(1j * 2*pi * rand(N,1));
method_names{end+1} = 'Random phase';
phi_list{end+1}    = phi_rand;
notes{end+1}       = '相位随机';

% 论文连续相位 RCG
[phi_rcg, info_rcg] = rcg_phase_optimize(ch.h_direct, ch.h_ris, params.weights, params);
method_names{end+1} = 'RCG continuous';
phi_list{end+1}    = phi_rcg;
notes{end+1}       = sprintf('iter=%d, best restart=%d', info_rcg.num_iter, info_rcg.best_restart);

% 离散相位: NPP 和码表坐标下降
phi_cd_best = [];
for tau = params.tau_list
    phi_npp = phase_quantize_npp(phi_rcg, tau);
    method_names{end+1} = sprintf('NPP tau=%d', tau); %#ok<SAGROW>
    phi_list{end+1}    = phi_npp; %#ok<SAGROW>
    notes{end+1}       = '连续解最近点投影'; %#ok<SAGROW>

    [phi_cd, info_cd] = codebook_coordinate_descent(ch.h_direct, ch.h_ris, tau, phi_npp, params);
    method_names{end+1} = sprintf('Codebook CD tau=%d', tau); %#ok<SAGROW>
    phi_list{end+1}    = phi_cd; %#ok<SAGROW>
    notes{end+1}       = sprintf('sweeps=%d', info_cd.sweeps); %#ok<SAGROW>

    if tau == 16
        phi_cd_best = phi_cd;
    end
end

% 以 CD tau=16 为初值，再做连续 RCG，展示码表初始化对连续解的价值
if ~isempty(phi_cd_best)
    [phi_rcg_cd, info_rcg_cd] = rcg_phase_optimize(ch.h_direct, ch.h_ris, params.weights, params, phi_cd_best);
    method_names{end+1} = 'RCG from CD tau=16'; %#ok<SAGROW>
    phi_list{end+1}    = phi_rcg_cd; %#ok<SAGROW>
    notes{end+1}       = sprintf('iter=%d, best restart=%d', info_rcg_cd.num_iter, info_rcg_cd.best_restart); %#ok<SAGROW>
end

% 全局随机配置码表（取 tau=4,8 做示意）
for tau = [4, 8]
    if any(tau == params.tau_list)
        [phi_cb, info_cb] = codebook_random_search(ch.h_direct, ch.h_ris, tau, ...
            params.codebook.random_K, params);
        method_names{end+1} = sprintf('Random codebook tau=%d K=%d', tau, params.codebook.random_K); %#ok<SAGROW>
        phi_list{end+1}    = phi_cb; %#ok<SAGROW>
        notes{end+1}       = sprintf('best k=%d', info_cb.best_k); %#ok<SAGROW>
    end
end

% ---------------- 3. 评估所有方案 ----------------
n_methods = numel(method_names);
results = struct();
fprintf('\n%-34s %14s %14s %14s\n', ...
    'Method', 'Residual(dB)', 'Suppress(dB)', 'SICcap(dB)');
fprintf('%s\n', repmat('-', 1, 82));

for i = 1:n_methods
    met = eval_sic_performance(ch.h_direct, ch.h_ris, phi_list{i}, params);
    results(i).name = method_names{i}; %#ok<AGROW>
    results(i).note = notes{i}; %#ok<AGROW>
    results(i).metrics = met; %#ok<AGROW>
    results(i).phi = phi_list{i}; %#ok<AGROW>

    residual_db = 10*log10(max(met.residual_power, eps) / max(met.direct_power, eps));
    fprintf('%-34s %14.2f %14.2f %14.2f\n', ...
        method_names{i}, residual_db, met.suppression_db, met.sic_cap_db);
end

% ---------------- 4. 码表规模曲线 ----------------
codebook_curve = struct();
if any(4 == params.tau_list)
    tau_cb = 4;
    K_curve = 1024;
    [~, info_curve] = codebook_random_search(ch.h_direct, ch.h_ris, tau_cb, K_curve, params);
    J_all = info_curve.J_all;
    J_cummin = cummin(J_all);
    direct_power = results(1).metrics.direct_power;
    codebook_curve.K = (1:K_curve).';
    codebook_curve.J_cummin = J_cummin(:);
    codebook_curve.suppression_db = 10*log10(direct_power ./ max(J_cummin(:), eps));
    fprintf('\n[trace] random codebook tau=4, K=%d: best suppression=%.2f dB\n', ...
        K_curve, max(codebook_curve.suppression_db));
end

% ---------------- 5. 保存结果 ----------------
out = struct();
out.params = params;
out.ch = ch;
out.results = results;
out.info_rcg = info_rcg;
if exist('info_rcg_cd','var'), out.info_rcg_cd = info_rcg_cd; end
out.codebook_curve = codebook_curve;
out.timestamp = datestr(now, 'yyyy-mm-dd HH:MM:SS');
save(params.save_mat, '-struct', 'out', '-v7.3');

% CSV 摘要
fid = fopen(params.save_csv, 'w');
fprintf(fid, 'method,note,residual_dB,suppression_dB,sic_cap_dB\n');
for i = 1:n_methods
    met = results(i).metrics;
    residual_db = 10*log10(max(met.residual_power, eps) / max(met.direct_power, eps));
    fprintf(fid, '%s,%s,%.6f,%.6f,%.6f\n', ...
        results(i).name, results(i).note, residual_db, met.suppression_db, met.sic_cap_db);
end
fclose(fid);

% ---------------- 6. 画图 ----------------
fig = figure('Visible','off', 'Color','w', 'Position',[100 100 1200 800]);

subplot(2,2,1);
supp = arrayfun(@(r) r.metrics.suppression_db, results);
bar(supp);
set(gca, 'XTick', 1:n_methods, 'XTickLabel', method_names, 'XTickLabelRotation', 25);
ylabel('SI suppression (dB)');
title('RIS-SIC performance');
grid on;

subplot(2,2,2);
plot(0:numel(info_rcg.f_history)-1, ...
    10*log10(max(info_rcg.f_history,eps)/max(info_rcg.f_history(1),eps)), 'LineWidth', 1.5);
xlabel('RCG iteration'); ylabel('objective (dB rel.)');
title('RCG convergence'); grid on;

subplot(2,2,3);
plot(angle(phi_rand), 'o', 'DisplayName','random'); hold on;
plot(angle(phi_rcg), 'x', 'DisplayName','RCG');
xlabel('RIS element index'); ylabel('phase (rad)');
title('Phase configuration'); legend('show'); grid on;

subplot(2,2,4);
if isfield(codebook_curve,'K') && ~isempty(codebook_curve.K)
    plot(codebook_curve.K, codebook_curve.suppression_db, 'LineWidth', 1.5);
    xlabel('codebook size K'); ylabel('best suppression (dB)');
    title('Random codebook search, tau=4'); grid on;
else
    text(0.1,0.5,'no codebook curve');
end

set(fig, 'Visible', 'off');
print(fig, params.save_png, '-dpng', '-r150');
close(fig);

fprintf('\n结果已保存:\n  %s\n  %s\n  %s\n', ...
    params.save_mat, params.save_csv, params.save_png);
fprintf('=====================================================\n');
