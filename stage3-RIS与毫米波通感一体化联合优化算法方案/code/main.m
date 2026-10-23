clear; close all; clc;
rng('shuffle'); 
% maxNumCompThreads(6);
root = fileparts(mfilename('fullpath'));
addpath(root);
t_total = tic;

% ---- 1. 参数配置 ----
params = build_default_params();
fprintf('RIS辅助MIMO-OFDM通感仿真\n');
fprintf('感知输入SNR：%g dB\n',params.SNR);
fprintf('发射天线%d，接收天线%d，RIS阵元%d，通信用户%d，目标%d\n', ...
    params.Ntx*params.Nty,params.Mx*params.My,params.ris_side^2,params.K_stream,params.Q);
fprintf('载频%.2f GHz，带宽%.2f MHz，子载波%d，每阶段符号%d\n', ...
    params.fc/1e9,params.B/1e6,params.N,params.K);
fprintf('理论距离分辨率%.3f m，最大无模糊距离%.1f m\n',params.resolution,params.Rmax);

% ---- 2. ZF发射、粗估计、RIS联合设计、精估计 ----
result = ris_sensing(params);

% ---- 3. 估计结果与真值比较 ----
coarse = evaluate_estimation(result.coarse,params); % 将粗估计目标排序与真值对应后统计误差。
compare = evaluate_estimation(result.estimate,params); % 相同真值下评估RIS精估计。
fprintf('\n各列：距离(m)、速度(m/s)、俯仰角(deg)、方位角(deg)\n');
for q = 1:params.Q
    fprintf('目标%d\n',q);
    fprintf('  真值：  %14.8f %14.8f %14.8f %14.8f\n',params.truth(q,:));
    fprintf('  无RIS： %14.8f %14.8f %14.8f %14.8f\n',coarse.estimate(q,:));
    fprintf('  RIS辅助：%14.8f %14.8f %14.8f %14.8f\n',compare.estimate(q,:));
end
fprintf('无RIS各参数RMSE：%.6g、%.6g、%.6g、%.6g\n',coarse.rmse);
fprintf('RIS辅助各参数RMSE：%.6g、%.6g、%.6g、%.6g\n',compare.rmse);
fprintf('通信用户SINR (dB)：'); fprintf('%.2f ',10*log10(result.sinr)); fprintf('\n');
fprintf('处理与观测总时长：%.4f s\n',result.latency);

% % ---- 4. 保存结果 ----
% total_runtime = toc(t_total);
% save(fullfile(root,'ZTE_3D_RIS_results.mat'),'params','result','coarse','compare','total_runtime');
% fprintf('结果已保存至ZTE_3D_RIS_results.mat\n');
