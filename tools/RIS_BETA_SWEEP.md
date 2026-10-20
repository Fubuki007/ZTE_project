# RIS/SIC 强自干扰对比：MC=50

本实验比较 betaSI=10、100、1000，SNR=[-25,-20,-15,-10,0,10,20] dB。
每个 beta 输出四条俯仰角 RMSE 曲线：无 RIS/SIC 关闭、连续相位 RIS/SIC 关闭、无 RIS/SIC 开启、连续相位 RIS/SIC 开启。
共 50×7×3×4=4200 个方案结果，四个独立 MATLAB 进程并行。

## 模型和统计

- 延续已完成 betaSI=0.1 实验的全尺寸参数：12672 子载波、256 个 OFDM 符号、16 发射/64 接收阵元、64 单元 RIS，double 精度。
- SIC 使用长度 128 的导频和热噪声下的 LS 信道估计，未使用真实信道消除；RIS 相位按已知目标几何优化，增强目标路径，不改变 SI 信道。
- 每个 MC 使用独立 SI 信道、发射波形与导频。四种方案、三个 beta 共用相同波形/信道/噪声，实现配对比较。
- 噪声功率参照相同 MC 的无 RIS、无 SI 目标回波，不因 RIS 或 beta 改变而重新归一化。
- 主图为标准汇总 RMSE：对全部 MC 和匹配目标的平方角度误差求和，除以匹配目标数量后开方。另存逐次 RMSE 的中位数图，便于与上一轮比较。CSV 同时保留均值、中位数、有效 MC 数和 SIC 抑制量，避免低 SNR 的大误差样本被中位数掩盖。
- 额外保存方位角、距离、速度及匹配数等诊断数据；本轮主要交付角度图。

## 运行与恢复

```powershell
# 上传完整代码快照并后台启动；SSH 断开不影响运行
./tools/ris-beta-server.ps1 run

# 查询已保存数量与四个 worker 日志
./tools/ris-beta-server.ps1 status
./tools/ris-beta-server.ps1 tail -Lines 25

# 停止；等待锁释放后，相同 run 命令即可续跑
./tools/ris-beta-server.ps1 stop

# 完成后下载 MAT、CSV、PNG
./tools/ris-beta-server.ps1 fetch
```

正式任务独立目录为服务器 `/home/jzm123/AAA_ZTEproject/.jobs/experiments/ris_beta_sweep_mc50_20261010_double`。
该目录包含模型函数快照，不覆盖上一轮的函数、样本或结果。

每个 MC 的三维完成掩码为 4×7×3。每算完一个方案立即原子提交 MAT；配置、beta、SNR、MC 数不一致会拒绝恢复。
默认每进程计算 1 个新方案后正常退出，再从断点恢复。长进程在 2026-10-10 验证时再次触发运行库堆损坏；1 个方案/进程此前已完成 2143 次正常退出，采用该保守设置。缓存确定性的 RIS 几何/相位和每个 MC 的参考目标功率，避免每次重启重复准备。
监护沿用已验证的原生错误快速回收、900 秒无进度超时、60 秒退出超时、整个进程组清理和有界重试。
完成全部样本后自动聚合，生成三张单独 beta 图、三联主图、中位数三联图及 MAT/CSV。

## 验证

`test_ris_beta_sweep` 检查三维断点、beta 配置混用拒绝、损坏文件拒绝、保存不改变 RNG 和标准 RMSE 汇总公式。
`validate_ris_beta_equivalence` 在 beta=0.1、MC=1、SNR=-25 dB 下重算四种全尺寸方案，与已完成的 MC=60 数据逐项比较，随后验证聚合和绘图。

预计完成时间以服务器实测吞吐为准；无法仅凭总内存或并行数保证 2026-10-10 21:30 前完成。
