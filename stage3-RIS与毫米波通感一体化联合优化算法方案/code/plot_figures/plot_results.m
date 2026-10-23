clear
clc
close all
addpath(fileparts(mfilename('fullpath')));
plot_rx;       % 4张RMSE、1张SNR、1张运行时间。
plot_cpi;      % 4张RMSE、1张SNR。
plot_tx;       % 发射天线数与运行时间。
plot_ris;      % RIS阵元数与运行时间。
