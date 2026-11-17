# UAV 粗测角修复与配对验证

修改前已推送并核对 GitHub 备份 `codex/pre-uav-angle-fix-20261116`，提交
`84953b5bbaadd920fca7d80b7405ce4252dfb542`。相关代码、脚本、文档与精选小型证据归档；
凭据、本地环境/缓存、未选择的历史产物和大型 MAT 不上传，已有其他文件保留。

代码检查发现：接收阵列响应为负号相位，而原粗测角的空间干扰消除使用正号。
仅改符号是否足够，以及对已经通过距离–多普勒分离的快拍继续消除是否有益，需要配对实验判断。
原相邻阵元相位法在低空间 SNR、接近水平面的方向余弦边界处也可能失稳。

共享粗估入口 `joint_estimator_fast` 改为对已有聚焦空间快拍作全阵列方向匹配：
在物理可行的方向余弦圆盘上，以 128×128 零填充空间 FFT 找起点，再用 `fminsearch`
精化最大空间匹配功率。不再对单独目标快拍投影消除其他目标。两个用户快拍的匹配功率求和，
不增加观测；未知复振幅分别消去，不使用真实角度或位置先验限制搜索。
该实现沿用半波长校准面阵、上半空间和载频阵列响应假设；没有扩展到非均匀接收阵列。
零填充只是计算网格，不增加阵列孔径或物理分辨率；不保证非线性全局最优。

全量复测重放上一轮 `51f541a92e38903ddb593f03d4eeb73f27ae970c` 的 900 个断点：
同一 300 个几何 × RCS=1/10/100，各工况使用完全相同的接收合并采集、距离/速度、
噪声、64 路空间样本和聚焦快拍，对比四种角度处理：

| 方法 | 改动 |
|---|---|
| legacy | 重现原 SVD 主方向＋相邻相位＋正号干扰消除 |
| signed_null | 仅将消除相位改为接收阵列负号 |
| no_null | 保留 SVD＋相邻相位，取消消除 |
| matched_array | 全阵列匹配，取消消除；拟采用的修复 |

每种角度初始化均继续执行同一 NoRIS 波束设计与原精定位算法，噪声/符号种子相同。
角度不同会自然改变后续波束和精测投影，因此精定位比较衡量整个链路的效果。
legacy 粗估与上一轮 `rx_initial`、精定位误差与上一轮方法 12 均重放核对。
所有失败保留：未捕获、通信设计不可行、任一目标 XYZ 误差 >5 m 均计失败。
真值仅用于离线误差、目标对应和局部搜索盒覆盖诊断。

主要对比在正式运行前固定为 RCS=10 的 matched_array 相对 legacy 严格失败率减少量，
按完整几何配对 bootstrap 4,000 次，种子 20261119，95% 区间。
其他 RCS、RMSE、正负号/取消消除对比是次要诊断。未使用独立留出数据，
不能将这批重放结果直接当作泛化或 RIS 增益证据。

全量保持原资源：28 GHz、12,672 子载波、16 Tx/64 Rx、粗/精 CPI 各 256 符号，
粗测空间抽样 384×64，精测 256×64，原 256 单元 2-bit RIS 配置参数保持，
本轮定位对照关闭 RIS；1 W 发射功率、10 dB 通信 SINR、热噪声不变。
接收合并仍假定可访问已有 64 路全带宽相干通道，增加空间搜索计算而非额外导频或射频硬件。

本地仅运行 `test_uav_angles('local_smoke.json')` 冒烟测试，须从本目录启动 MATLAB，
以避开仓库根目录同名 `build_default_params`。服务器 pilot 为 MC0 的三个全尺寸 RCS 工况，
仅验证全量脚本与历史重放，不用于调参；正式结果为全部 900 工况。

```powershell
./tools/uav-foundation-server.ps1 upload -Experiment angle_fix -Release <sha>
./tools/uav-foundation-server.ps1 test -Experiment angle_fix -Release <sha>
./tools/uav-foundation-server.ps1 pilot -Experiment angle_fix -Release <sha>
./tools/uav-foundation-server.ps1 run -Experiment angle_fix -Release <sha> -Workers 8
./tools/uav-foundation-server.ps1 status -Experiment angle_fix -Release <sha>
./tools/uav-foundation-server.ps1 fetch -Experiment angle_fix -Release <sha>
```

服务器逐样本保存参数、种子、输入哈希、聚焦快拍、四种粗估/精估、波束和真实进度，支持断点继续。
汇总核对源码/输入哈希、全部工况、历史重放、相同距离/速度和捕获标志、功率/SINR及失败定义。
大 MAT 与完整日志留在服务器，仅拉取选定 CSV/JSON/PNG。未安装任何新依赖。

正式复测已完成，详见 [2026-11-17 结果与结论](RESULTS_20261117.md)。
