# MIMO-OFDM ISAC 自干扰版交付说明

版本：v1.0  
交付日期：2026-09-16  
运行环境：MATLAB R2024a

## 1. 交付范围

本交付包是“加入自干扰后的可独立运行最小工程”，包含：

- Rician 矩阵自干扰信道建模；
- ZF、Nullspace、Lagrange 三种预编码；
- 矩阵自干扰注入；
- 基于导频 LS 信道估计的数字自干扰消除（SIC，可选）；
- 角度、距离、速度三维联合估计；
- 估计误差评估及 MAT 结果保存。

包内不含扫参、绘图、临时诊断、单元测试、日志、历史结果和论文资料。原工程中的 `SIC.m` 是早期独立验证原型，正式 SIC 已集成到 `simulate_radar_channel_3d.m`，因此未重复交付。

## 2. 快速运行

1. 解压后在 MATLAB 中进入本目录。
2. 打开 `main.m`，按需修改顶部“用户配置区”。
3. 运行：

```matlab
main
```

建议在一个独立的 MATLAB 工作目录/会话中运行。原工程根目录有与交付包同名的函数；仅用 `addpath` 而不切换当前目录时，MATLAB 可能优先调用原工程版本。排查时执行 `which build_default_params`，应指向本交付目录。

程序会自动创建 `results/`，结果保存为：

```text
results/ZTE_3D_SI_results.mat
```

MAT 文件仅含一个顶层结构体 `result`，其中包括配置、参数、SI 信道信息、预编码诊断、估计结果、误差和分阶段耗时。

## 3. 关键配置

| 配置项 | 默认值 | 说明 |
|---|---:|---|
| `config.precoder_type` | `nullspace` | 可选 `zf`、`nullspace`、`lagrange` |
| `config.enable_SI` | `true` | 是否注入自干扰 |
| `config.beta_SI` | `100` | SI 幅度系数；相对目标幅度 100 倍对应约 40 dB 功率比 |
| `config.enable_SIC` | `false` | 是否启用基于导频 LS 估计的数字 SIC |
| `config.sic_use_true_channel` | `false` | `true` 为理想信道上界，仅建议算法对照时使用 |
| `config.SIC_pilot_len` | `64` | SIC 导频长度，应不小于发射天线总数 |
| `config.kappa_SI` | `10` | Rician K 因子 |
| `config.d_sep_wl` | `10` | 矩阵 LoS 模型的收发面板间距，单位波长 |
| `config.d_lambda` | `0.5` | 矩阵 LoS 模型的阵元间距，单位波长 |
| `config.SNR_dB` | `10` | 目标回波信噪比 |
| `config.R_max_gate_m` | `600` | 最大感知距离门限，用于排除频率平坦 SI 的边界假峰 |
| `config.rng_seed` | `20260916` | 固定随机种子，保证仿真可复现 |
| `config.param_overrides` | 空结构体 | 目标、阵列、OFDM 等独立参数覆盖；参见第 7 节 |

注意：`beta_SI` 是幅度系数，功率比应按 `20*log10(beta_SI/max(alpha))` 换算，而不是 `10*log10(...)`。

## 4. 核心调用链

```text
main.m
  ├─ build_default_params.m        参数装配
  ├─ generate_HSI.m                Rician 矩阵 SI 信道
  ├─ generate_mimo_ofdm_waveform.m MIMO-OFDM 波形
  │    └─ design_precoder.m        ZF / Nullspace / Lagrange
  ├─ simulate_radar_channel_3d.m   目标回波 + SI 注入 + 可选 SIC + AWGN
  ├─ joint_estimator_fast.m        角度/距离/速度联合估计
  └─ evaluate_estimation.m         真值匹配与误差评估
```

## 5. 文件说明

| 文件 | 用途 |
|---|---|
| `main.m` | 唯一运行入口和交付配置区 |
| `build_default_params.m` | 物理、阵列、OFDM、目标和估计器参数 |
| `generate_HSI.m` | 近场 LoS + 多径 NLoS 的 Rician SI 信道 |
| `generate_mimo_ofdm_waveform.m` | 通信信道、预编码、QAM 符号和发射张量 |
| `design_precoder.m` | 三种预编码核心实现 |
| `simulate_radar_channel_3d.m` | 回波、矩阵 SI、LS-SIC 和噪声仿真 |
| `joint_estimator_fast.m` | RD 粗检测、相邻阵元相位差角度估计及亚 bin 插值 |
| `evaluate_estimation.m` | 多目标匹配和 RMSE 计算 |
| `MANIFEST.md` | 交付边界和文件清单 |
| `CHANGELOG.md` | 本版本整理记录 |

## 6. 依赖与资源

- 必需：MATLAB R2024a。
- 无强制附加工具箱依赖：没有 Communications Toolbox 时，代码会使用内置方形 QAM 回退实现；Hann 窗也在工程内实现。
- 默认全尺寸参数会产生较大的四维复数数据，建议至少 16 GB 内存，并关闭无关 MATLAB 工作区变量。频率平坦信道只求解一次预编码，但仍须生成全部波形与回波。
- Windows、Linux 均可运行，代码不依赖固定绝对路径。

## 7. 修改与维护

入口的 `config` 决定运行模式；`config.param_overrides` 传给 `build_default_params`，用于更换独立的目标、阵列和 OFDM 参数。例如：

```matlab
config.param_overrides = struct( ...
    'K', 64, 'Mx', 4, 'My', 4, ...
    'num_targets', 1, 'theta_true', 30, 'phi_true', 20, ...
    'R_true', 200, 'v_true', 5, 'alpha', 1);
```

要更换 `N` 进行小规模仿真，可同时设置 `N` 与 `B=N*delta_f_Hz`；未指定 `B` 时函数自动计算。`lambda`、`d`、`Ts`、`meta` 等派生字段不能独立覆盖。默认载波聚合使用四个各含 3168 子载波的载波；非整载波长度仅用于缩小仿真，不代表合规配置。所有目标真值向量长度必须等于 `num_targets`。入口会用顶部 `config` 覆盖 `param_overrides` 中同名的 SI、预编码和 SNR 设置。

| 修改目标 | 所有者/检查点 |
|---|---|
| 场景、阵列、OFDM 与派生量 | `build_default_params.m`；检查 `meta.range_resolution`、`meta.R_max` 和向量长度 |
| 矩阵 SI 几何/多径 | `generate_HSI.m`；检查 H_SI 大小为 `(Mx*My) x (Ntx*Nty)` |
| 通信用户和波形维度 | `generate_mimo_ofdm_waveform.m`；检查 `tx.X` 为 `Ntx x Nty x N x K` |
| 预编码约束及正则化 | `design_precoder.m`；检查 `si_leak_avg` 与 `comm_err_avg`，不要比较不同尺度的绝对值 |
| SI 注入、导频 LS 与 SIC | `simulate_radar_channel_3d.m`；分别检查无 SI、SI-ON、LS-SIC 三条路径 |
| 距离门限、角度与插值 | `joint_estimator_fast.m`；检查检出目标数、范围和估计误差 |

`K` 是 OFDM 符号数，`K_stream` 是通信流数；MATLAB 按列主序展平阵列。`H_SI_per_cc` 是保留的旧字段名，实际上第三维是**每个子载波**，不是每个载波聚合分量。默认频率平坦 SI 信道仅设计一次预编码，逐子载波信道仍逐项设计；但当前接收端矩阵 SI 注入只支持频率平坦的 `H_SI_matrix`，不能把逐子载波预编码分支当作完整的频率选择性 SI 仿真。

## 8. SI 与 SIC 行为说明

- `enable_SI=true` 时，接收端加入 `beta_SI * H_SI * X`。
- `enable_SIC=true` 且 `sic_use_true_channel=false` 时，先利用已知导频通过 LS 估计有效 SI 信道，再从接收信号中消除。
- `enable_SI=false` 时 SIC 不做减法；SI-ON 且启用数字 SIC 时必须提供矩阵信道。
- `sic_use_true_channel=true` 会直接使用仿真真值信道，属于理想上界，不代表实际信道估计性能。
- SNR 噪声基准按纯目标回波功率计算，避免 SI 强度改变噪声地板定义。
- 当前 Rician 矩阵的 LoS 项来自两块平行 URA 面板的逐天线对距离，不使用 `theta_SI/phi_SI`；角度仅在备选点散射 SI 模型中生效。`H_NLoS` 是简化虚信道，整体模型不是经过实测校准的射频 SI 信道。
- `result.comparison` 的 RMSE 仅针对检出且匹配的目标；漏检应同时检查 `result.estimator_info.detected_targets`。角度估计采用空间相位差，不是严格的子空间 ESPRIT。
- 有 Communications Toolbox 时导频采用 16-QAM；没有时 LS-SIC 导频采用单位功率复高斯回退。

## 9. 修改后验收

首次验收建议保持默认随机种子不变并运行两次，两次的估计值应一致。修改核心代码后分别测试：

1. `enable_SI=false`：无自干扰基线；
2. `enable_SI=true, enable_SIC=false`：自干扰注入；
3. `enable_SI=true, enable_SIC=true`：LS 数字消除；
4. 切换三种 `precoder_type` 比较 `result.precoder_info.si_leak_avg`。

还应检查结果 MAT 的 `result.config`、`result.params` 与本次输入一致，并对每个交付 `.m` 文件运行 MATLAB `checkcode`。归档目录中的 `SHA256SUMS.txt` 用于接收方校验文件完整性；修改任何文件后必须重新生成它和 ZIP。
