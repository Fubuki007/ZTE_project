=====================================================================
 ZTE 通感一体化仿真包 — 实验2 距离 RMSE vs 子载波数 Ns (四方法对比)
=====================================================================

一、包内容
  task_range_rmse_vs_subcarrier_4methods_beta100_local.m    本地预览版 (MC=4)
  task_range_rmse_vs_subcarrier_4methods_beta100_server.m   服务器全量版 (MC=50)
  design_precoder.m                       预编码器 (zf / nullspace)
  server_run_si_sweep/                    核心仿真函数 (7 个, 最新版)

二、环境要求
  - MATLAB R2021a 或更新版本 (推荐 R2024a)
  - Signal Processing Toolbox (用到 hann 窗)
  - Communications Toolbox 可选 (缺 qammod 时脚本自动用内置回退)
  - 内存: 峰值约 4.5 GB, 16 GB 内存机器足够; 脚本严格串行、无 parfor

三、运行方法
  1) 解压整个 zip 到任意目录
  2) 在命令行进入该目录后执行 (或在 MATLAB 编辑器打开 .m 文件直接点 Run):
       matlab -batch "task_range_rmse_vs_subcarrier_4methods_beta100_local"          % 本地趋势 (约 15 分钟)
       matlab -batch "task_range_rmse_vs_subcarrier_4methods_beta100_local(true)"    % 冒烟测试 (约 3 分钟, 先跑它验证环境)
       matlab -batch "task_range_rmse_vs_subcarrier_4methods_beta100_server"         % 服务器全量 (约 2.5~3 小时)
       matlab -batch "task_range_rmse_vs_subcarrier_4methods_beta100_server(true)"   % 上机冒烟自检
  3) 输出自动生成在解压目录:
       *.mat (逐 MC 原始 RMSE + 中位数) / *.csv (中位数表) / *.log (日志)
       fig/ 下 *.fig + *.png (300dpi) + *.eps

四、实验参数
  曲线: ZF-DFT / Tx-NS-DFT / Rx-SIC-DFT / Dual-Domain-DFT
  横坐标: 等效子载波数 Ns = [512, 1024, 2048, 3168, 6336, 12672] (对数刻度)
  纵坐标: 距离 RMSE (m, 对数轴)
  固定: SNR = 0 dB, beta_SI = 100
  子载波间隔固定 120 kHz, 带宽 B = Ns x 120 kHz, 距离分辨率随 Ns 提高
  (Ns=12672 时 B=1520.64 MHz, 分辨率 0.099 m)
  接收阵列 8x8 (Mrx=64), 发射阵列 4x4 (Nt=16), L = 256, 目标 2 个
  H_SI: 64x16 (ura_rician, kappa=10, seed=20260731)
  门限: R_min_gate = 20 m, R_max_gate = 600 m

五、预期结果 (跑完可与下表核对, 全尺寸同配置历史结果)
  - 健康方法 (Tx-NS / Rx-SIC / Dual): RMSE 随 Ns 增大近似按 1/Ns 下降
    (分辨率越细插值越准), Ns=12672 处 NS 约 0.012 m, SIC 方法约 0.007 m
  - ZF-DFT (无抑制): 全 Ns 范围检测层被 SI 打崩, 保持高位
  - Ns=12672 列的数值应与实验1 SNR 扫描中 SNR=0 dB 行同一量级

六、断点续跑
  每个 MC 完成后自动保存 *_checkpoint.mat; 中断/断电后重跑同一条命令自动续跑,
  不会白跑。想从头重新开始: 删除对应 *_checkpoint.mat 即可。

七、注意事项
  - 请串行执行, 不要同时开多个脚本实例 (每个实例峰值内存约 4.5 GB)
  - 包内自带 server_run_si_sweep 目录, 脚本启动时自动把它置顶到搜索路径
    并做版本自检 (必须含 R_max_gate 距离门限), 请勿混入其他同名旧函数
  - 所有随机种子已固定 (H_SI seed=20260731, MC 种子 20260801 派生),
    任何机器上跑出的结果完全一致、可复现
=====================================================================
