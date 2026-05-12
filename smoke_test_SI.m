% 快速冒烟测试：小规模跑一遍，检查无报错且 MSE 随 rho 变化
cfg = struct();
cfg.rho_dB_range = -20:10:50;
cfg.snr_dB_list  = [0 10];
cfg.numMC        = 30;
cfg.plotFlag     = false;
cfg.showWaitbar  = false;
cfg.seed         = 42;

t0 = tic;
r = SelfInterferenceChannel_LoS_NLoS_PlotPrep(cfg);
fprintf('用时: %.2f s\n', toc(t0));
fprintf('rho (dB): %s\n', mat2str(r.rho_dB_range));
for is = 1:numel(r.snr_dB_list)
    fprintf('SNR=%g dB  MSE_dB = %s\n', r.snr_dB_list(is), ...
        mat2str(round(r.mse_avg_dB(is,:), 2)));
    fprintf('           rho_th = %g dB\n', r.threshold_rho_dB(is));
end
