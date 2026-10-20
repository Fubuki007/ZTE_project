# Stage 3：RIS 联合设计与四路径参数精估计

用户约定：**正式脚本全量、服务器运行；本机只跑冒烟。** 新代码独立放在此目录，未覆盖旧 MATLAB 主链。

## 旧代码备份

新代码编写前，现有代码已提交并推送：

- 仓库：`https://github.com/Fubuki007/ZTE_project`
- 分支：`codex/pre-stage3-backup-20261012`
- 提交：`6971f35091b97c4ab6156e61c027acd5edeb0634`
- 内容：已跟踪文件的当前状态、新增源代码和 README。未上传本机缓存、证书和未跟踪的大型仿真结果。

## 正式配置

| 项目 | 值 |
|---|---|
| 载频 / 子载波间隔 | 28 GHz / 120 kHz |
| 子载波数 / 带宽 | 12,672 / 1.52064 GHz |
| 发射 / 接收阵列 | 4×4 / 8×8，半波长间距 |
| 总观测时长 | 256 个 OFDM 符号，128 粗估计 + 128 精估计 |
| OFDM 符号时长 | 1/120 kHz + 0.6 μs |
| 双目标 | 沿用 `build_default_params.m` 的距离、角度、速度与 DD 幅度 |
| SNR | −30:5:20 dB，共 11 点 |
| 蒙特卡洛 | 每点 100 次，共 1,100 个样本，每样本 4 种方法 |
| RIS | 8×8，半波长间距，2 bit 离散相位，全子载波共用同一相位向量 |
| 流数 | 1；与当前项目默认 `K_stream=1` 一致 |
| 数值精度 | complex128；不删减子载波、阵元、OFDM 符号 |
| 并发 | 默认 2 个 worker，每个 BLAS 4 线程 |

## 曲线与公平性

1. DD FFT：无 RIS，利用完整 256 符号进行距离/多普勒 FFT 与空间相位差测角。
2. DD joint refinement：无 RIS、同一 ZF 发射波束，完整 256 符号做联合精估计。
3. Random RIS + joint refinement：随机离散 RIS，相同 ZF 波束，四路径联合精估计。
4. Stage-3 optimized RIS：关闭 RIS 粗估计，再按式 (48)–(59) 联合设计预编码和 RIS，按式 (69)–(76) 精估计。

四方法使用相同总符号数、总发射功率与噪声方差。RIS 方法的前 128 符号用于 DD 粗估计，后 128 符号开启 RIS；粗估计数据也纳入最终似然。DD 路径系数跨两段保持不变，其余三条路径仅在 RIS 开启段出现。未知路径系数每次迭代重新最小二乘拟合，不把真值提供给设计器或估计器。

SNR 定义为 **无 RIS、ZF、完整 CPI 的 DD 回波平均功率 / 接收噪声方差**；不同方法不重新按各自回波功率归一化噪声。同一 MC/SNR 的方法共用完全相同的噪声实现。SNR 点间使用不同随机种子。

主图纵轴：`sqrt(mean(error_theta^2 + error_phi^2)/2)`，平均覆盖全部 MC 与两个目标，单位为度。方位角误差绕回 [-180,180)，按三维方向的最小总角误差完成目标匹配。CSV 另存 theta、phi、三维夹角 RMSE、>5°离群率。95% 区间按 MC 样本重采样，不把两个目标视为独立样本。不删掉失检/大误差样本，不平滑曲线。

距离、速度曲线由 `collect_rmse.py` 读取上述全量联合估计检查点生成：距离为 BS–目标距离 `R`（m），速度为相对 BS 的有符号径向速度 `v_B`（m/s）。分别计算 `sqrt(mean((R_est-R_true)^2))` 与 `sqrt(mean((v_B_est-v_B_true)^2))`，均平均覆盖 MC 和两个目标。三项指标共用原角度曲线的三维方向匹配，不为距离或速度另选有利匹配，不对误差取模、截断或丢弃样本。95% 区间采用 2,000 次 MC bootstrap（种子 20261015），同次重采样保留目标与方法配对；另存逐目标偏差、RMSE，以及超过一个完整 CPI 原生 FFT 栅格宽度的离群率。

这些统计复用原正式实验保存的全部 `R,v_B,theta,phi` 估计，不会重新生成噪声或运行一次新的蒙特卡洛。源实验参数、种子、检查点与代码身份保持可追溯；新增统计器单独记录 SHA256。

DD FFT 为新模型下的参考算法实现，沿用旧项目的 RD FFT + 空间相位差思路，但不是直接调用旧 `joint_estimator_fast.m`。为避免宽带阵列与 broadside 空间求和的零点问题，RD 检测采用逐阵元功率求和，角度初始化按中心频率修正。精估计保留逐子载波导向矢量。这里比较的是新 RIS 方案与同模型下的无 RIS 参考，**不是旧 SI/SIC 曲线的直接延续**。

## PDF 未给定的参数与限制

来源：用户提供的 `ZTE_project__stage_3.pdf`，10 页。该文件作为算法资料使用。

- RIS 中心取 `(12,-10,8) m`，基站在原点，阵列位于 xy 平面。
- 通信用户方向 `(theta,phi)=(35°,20°)`，距离 160 m；归一化用户噪声方差 0.02，SINR 下限 2（约 3.01 dB）。
- BS–RIS 使用归一化远场 rank-one LoS 模型。RIS 耦合 `C` 含 `1/N_R`，单程路径相对幅度取 0.7，双程取 0.49；随机固定相位分别为 0.4、−0.7、0.9 rad。通信 RIS 分量幅度取 0.15。
- 这些是明确指定的**归一化级联链路场景**，不是经过 Friis、器件面积、RCS、遮挡和实测校准的绝对链路预算。不能由此声称任意部署或被动 RIS 都有同等收益。
- PDF 只给标量径向速度，程序采用速度向量沿 BS–目标径向的闭合假设：`v_R=v_B*(u_B dot u_R)`。CPI 内位置冻结，多普勒相位使用真实时刻连续演进。
- PDF 未包含 SI 项，本实验不加自干扰，不宣称验证 SI 抑制。
- 使用已知单位模 QPSK，并在存储前去除符号；这是精确的酉变换，保持白噪声统计与所有样本。与旧工程 16-QAM 有区别，显式记录在 manifest 中。
- 两目标数量已知，几何固定，MC 随机性来自热噪声及随机 RIS 对照，不包含随机部署、运动方向或衰落场景。
- 当前精确的 SCA 子问题求解器适用于 **单通信用户、双目标**。需要多用户时应扩展为一般 SOCP，不能直接复用此求解器。
- RIS 相位设计和预编码属于非凸交替优化，只保证接受步骤的目标不下降，不保证全局最优。
- 精估计范围和角度邻域由粗估计确定，粗估计失败会导致大误差，保存为真实结果。
- 已知用户信道；没有模拟用户信道估计误差。运行时优化耗时不计入 256 个符号的无线采样预算，未验证实时跟踪能力。

## 代码对应

| 文件 | 内容 |
|---|---|
| `stage3_model.py` | 几何、四路径、公共 RIS 相位、发射预编码 SCA、相位坐标搜索 |
| `streaming.py` | 完整数据生成、FFT 粗估计、分块充分统计量与变投影精估计 |
| `run_stage3.py` | 100 MC、11 SNR、逐样本原子检查点、聚合与出图 |
| `collect_rmse.py` | 全量检查点验证、统一目标匹配、距离/径向速度 RMSE、置信区间与逐样本审计 |
| `test_stage3.py` | 独立数学一致性检查 |
| `test_collect_rmse.py` | 目标匹配、有符号速度、RMSE 定义、数据完整性检查 |
| `run_server.sh` | 锁、后台 worker、日志、完成状态与自动汇总 |
| `../tools/ris-stage3-server.ps1` | 上传、启动、查看状态、取回曲线 |

单用户时式 (56) 化为期望信道响应为实非负且不小于门限。式 (57) 的双目标 epigraph 问题用目标权重的一维凸对偶求解，每次支撑函数的总功率乘子用二分法求解；保存对偶间隙，并检查功率、SINR 与单调性。数学测试使用独立 SLSQP 解交叉核对。

分块估计计算 `DᴴD, Dᴴy, DᴴJ, JᴴJ, Jᴴy`，利用时域与阵列因子分离得到完全相同的正规方程，再按式 (74) 投影去除未知路径幅度的影响。数据以磁盘 memmap 保存，每个 worker 同时保留粗、精两段，约 3.1 GiB；样本结束删除临时观测数据，保留 seed、参数、估计、波束和 RIS 相位以重现。

## 运行

本机：

```powershell
uv pip install --python .venv-stage3/Scripts/python.exe -r RIS_stage3/requirements.txt
.venv-stage3/Scripts/python.exe RIS_stage3/test_stage3.py
.venv-stage3/Scripts/python.exe RIS_stage3/run_stage3.py --smoke --mc 1 --snr=-30,-5,20 --output RIS_stage3/results_smoke_v2
```

正式服务器（默认全量参数，不需要修改代码）：

```powershell
tools/ris-stage3-server.ps1 upload
tools/ris-stage3-server.ps1 run -RunName results_full_mc100 -Mc 100 -Workers 2
tools/ris-stage3-server.ps1 status -RunName results_full_mc100
tools/ris-stage3-server.ps1 fetch -RunName results_full_mc100
tools/ris-stage3-server.ps1 fetch-metrics -RunName results_full_mc100
```

新启动的 `run_server.sh` 在全部样本完成后自动生成角度、距离和速度曲线。对已有正式检查点补算距离与速度，只需在服务器运行统计器，无需重跑仿真：

```powershell
tools/ris-stage3-server.ps1 metrics -RunName results_full_mc100
tools/ris-stage3-server.ps1 metrics-status -RunName results_full_mc100
tools/ris-stage3-server.ps1 fetch-metrics -RunName results_full_mc100
```

Linux 统计命令为 `.venv311/bin/python collect_rmse.py --source results_full_mc100`。默认要求全部样本完整；只有显式指定 `--partial` 才输出不完整统计，并标记为 `PARTIAL` / `INCOMPLETE`。本地统计冒烟可使用 `--source RIS_stage3/results_smoke_v2`；本地校验使用 `.venv-stage3/Scripts/python.exe -m unittest discover -s RIS_stage3 -p test_collect_rmse.py -v`。

Linux 直接运行：

```bash
cd /home/jzm123/AAA_ZTEproject/RIS_stage3
STAGE3_MC=100 STAGE3_WORKERS=2 bash run_server.sh
```

依赖装在项目专用 `.venv311`，无需修改系统 Python。环境缺少 venv 的 pip 时可由已有 conda Python 的 pip `--python` 选项安装。

重复启动同一命令从已完成样本续跑；参数或算法文件 SHA256 变化则拒绝混用旧样本，需使用新结果目录。`state=COMPLETE` 且 `progress.json` 的 `complete=true` 才表示全实验完成。运行中取回的图明确标记 INCOMPLETE，不代表最终曲线。

每个样本 `.json` 保存所有方法的误差和诊断，`.npz` 保存优化波束与 RIS 相位。最终输出 PNG、SVG、CSV、manifest 和进度 JSON。正式结果目录与本地 smoke 目录始终分开。

距离/速度结果位于实验目录的 `range_velocity_metrics/`：`range_rmse_vs_snr.*`、`velocity_rmse_vs_snr.*`（PNG/SVG/CSV）、`per_sample_range_velocity_errors.csv`、`metrics_progress.json` 与 `state`。统计日志保存在实验目录的 `range_velocity_metrics.log`（补算）或 `logs/range_velocity_metrics.log`（完整启动器）。只有 `state=COMPLETE` 且 `metrics_progress.json` 中 `complete=true`、样本数与源 manifest 相符，才表示全量统计完成。

2026-10-15 已在服务器对正式 1,100 个样本完成补算；相对 DD joint refinement，距离 RMSE 在 11 个 SNR 点降低 15.7%–20.0%，速度 RMSE 降低 13.6%–17.7%。具体数值与曲线解释见 `RUN_STATUS.md`。随机 RIS 的距离/速度曲线与无 RIS 联合精估计几乎重合；角度指标的收益不能直接套用到距离和速度。优化方案同时改变发射预编码与 RIS 相位，收益属于这套联合方案。
