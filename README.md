# MIMO-OFDM 通感一体化（ISAC）三维联合估计 — 全双工自干扰版

> **面向对象**：企业工程师（ZTE / SANECHIPS）
> **编程语言**：MATLAB R2024a
> **最后更新**：2026-07-26
> **版本**：v3.0（SI-ON + 矩阵 SI 模型 + 三种预编码对比）

---

## 目录

1. [项目背景与目标](#1-项目背景与目标)
2. [系统架构总览](#2-系统架构总览)
3. [自干扰（SI）专题](#3-自干扰si专题)
4. [算法原理详解](#4-算法原理详解)
5. [文件地图与职责](#5-文件地图与职责)
6. [快速上手](#6-快速上手)
7. [参数配置指南](#7-参数配置指南)
8. [核心代码详解](#8-核心代码详解)
9. [常见问题 FAQ](#9-常见问题-faq)

---

## 1. 项目背景与目标

### 1.1 什么是通感一体化（ISAC）？

通感一体化（Integrated Sensing and Communication, ISAC）的核心思想是：**一套硬件设备同时完成通信和雷达感知两项任务**。

- **通信任务**：基站向多个手机用户发送数据（16-QAM 符号）
- **感知任务**：利用基站发射的信号回波，检测周围环境中的目标（如车辆、行人），估计其角度、距离、速度

类比：就像一个人一边唱歌（通信），一边用歌声的回音判断房间大小和墙壁位置（感知），用的是同一张嘴和同一首歌。

### 1.2 为什么会有自干扰（SI）？

在**全双工（Full-Duplex）**工作模式下，基站同时发射和接收信号。问题来了：

> 发射天线发出的信号会直接"漏"到旁边的接收天线上——就像你对着麦克风唱歌时，音箱的声音被麦克风重新收进去，产生刺耳的啸叫。

这就是**自干扰（Self-Interference, SI）**。发射功率很大（比如 30 dBm），目标回波很弱（可能只有 -100 dBm），两者功率差可以达到 **130 dB（十万亿倍）**！如果不处理 SI，目标回波会被完全淹没。

**生活类比**：你在 KTV 唱歌（发射），想听自己的回声（感知），但音响（SI）把你的原声直接放出来，回声根本听不到。你需要做两件事：
1. **唱歌时背对音响**——空间域抑制（预编码，让发射波束避开接收天线）
2. **用降噪算法减去原声**——数字域消除（SIC，从接收信号中减掉已知的 SI）

### 1.3 本项目做什么？

本项目在 ISAC 系统的基础上，**完整加入了自干扰的建模、抑制与评估**，实现了：

| 功能 | 说明 |
|------|------|
| **SI 信道建模** | Rician 莱斯模型（LoS 近场 + NLoS 多径），矩阵模型而非简单标量 |
| **三种预编码方案** | ZF（不抑制）/ Nullspace（零空间法）/ Lagrange（拉格朗日法） |
| **SI 注入仿真** | 真实矩阵乘（H_SI × X），精确到每个收发天线对 |
| **数字 SI 消除（SIC）** | 从接收信号中减去已知发射信号经过 H_SI 的产物 |
| **SI 强度扫描** | 不同 beta_SI 下的 RMSE 对比，量化 SI 对估计精度的影响 |

### 1.4 技术指标

| 指标 | 要求 | 本项目实现 |
|------|------|-----------|
| 载波频率 | 28 GHz（毫米波 FR2） | ✅ 28 GHz |
| 带宽 | ≥ 1.5 GHz（0.1 m 分辨率） | ✅ 1520.64 MHz（4×CA） |
| 距离分辨率 | ≤ 0.1 m | ✅ 0.099 m |
| 最大不模糊距离 | ≥ 600 m | ✅ 1250 m |
| 目标数量 | ≥ 2 | ✅ 2（可扩展） |
| 估计刷新率 | < 1 秒 | ✅  < 1 s |
| 自干扰模型 | 全双工 SI | ✅ Rician 矩阵模型 + SIC |
| 3GPP 标准合规 | FR2 参数对齐 | ✅ μ=3, Δf=120kHz, N_RB=264 |

---

## 2. 系统架构总览

### 2.1 整体流程图

```
┌──────────────────────────────────────────────────────────────────┐
│                     build_default_params.m                       │
│                    （所有参数的定义中心）                          │
│            含 SI 参数: enable_SI, beta_SI, theta_SI 等           │
└──────────────────────────────────┬───────────────────────────────┘
                                   │ params
                                   ▼
┌──────────────────────────────────────────────────────────────────┐
│                    generate_HSI.m                                │
│  ① 莱斯模型: H_SI = √(κ/κ+1)·H_LoS + √(1/κ+1)·H_NLoS          │
│  ② LoS: 近场逐天线对距离 + 1/R 路径损耗 (URA版)                  │
│  ③ NLoS: Sayeed 虚信道 (多簇多径)                                │
│  输出: H_SI → (Nr_total × Nt_total) 自干扰信道矩阵              │
└──────────────────────────────────┬───────────────────────────────┘
                                   │ H_SI
                                   ▼
┌──────────────────────────────────────────────────────────────────┐
│                 generate_mimo_ofdm_waveform.m                    │
│  ① 构造通信信道 H (URA 导向矢量)                                  │
│  ② 预编码 W (三种方案, 根据 precoder_type 选择):                  │
│     ├─ 'zf':       传统 ZF, 不抑制 SI                            │
│     ├─ 'nullspace': 公式(17), 在通信零空间压 SI 泄漏              │
│     └─ 'lagrange':  公式(16), 拉格朗日封闭解                      │
│  ③ 生成 16-QAM 通信符号 S                                         │
│  ④ 发射信号 X = W · S  （论文公式 (2)）                           │
│  输出：tx.X → (Ntx, Nty, Ns, K) 四维发射张量                     │
│         + tx.precoder_info.si_leak_avg (SI 泄漏诊断)             │
└──────────────────────────────────┬───────────────────────────────┘
                                   │ tx_signal
                                   ▼
┌──────────────────────────────────────────────────────────────────┐
│                simulate_radar_channel_3d.m                       │
│  ① 对每个目标 q：计算 URA 接收导向矢量 + 发射导向矢量内积          │
│  ② 叠加距离维相位 + 多普勒维相位                                   │
│  ③ ★ 自干扰注入（公式 28）:                                      │
│     ├─ 矩阵模式: H_SI_matrix × X (Nr × Ns, 每符号)               │
│     └─ 点散射模式: 近场 SI 点 β_SI·b_si·a_tx^H·X                 │
│  ④ ★ 数字 SI 消除（公式 50, 可选 SIC）:                          │
│      rx -= β_SI · H_SI × X                                       │
│  ⑤ 叠加 AWGN 噪声（基于纯目标功率计算噪声地板）                    │
│  输出：rx_cube → (Mx, My, Ns, K) 四维接收数据立方体              │
└──────────────────────────────────┬───────────────────────────────┘
                                   │ rx_cube
                                   ▼
┌──────────────────────────────────────────────────────────────────┐
│                  joint_estimator_fast.m                          │
│  ┌─ 1. 信道均衡：rx ⊙ conj(tx)                                   │
│  ├─ 2. 空间求和 + 2D-FFT 粗检测 → RD 功率图                      │
│  ├─ 3. NMS 峰值检测 (含 R_min_gate 排除近距离 SI 假峰)           │
│  ├─ 4. 对每个候选:                                                │
│  │   ├─ 相位补偿聚焦 + 2D-ESPRIT → 角度（俯仰+方位）             │
│  │   ├─ 距离维抛物线插值 → 亚 bin 精度距离                        │
│  │   └─ 多普勒维抛物线插值 → 亚 bin 精度速度                      │
│  └─ 5. 多目标迭代干扰消除（Gram-Schmidt 投影）→ 角度精化          │
│  输出：[θ̂, φ̂, R̂, v̂]                                            │
└──────────────────────────────────┬───────────────────────────────┘
                                   │ 估计值
                                   ▼
┌──────────────────────────────────────────────────────────────────┐
│                  evaluate_estimation.m                           │
│  贪心最近邻匹配 + RMSE 计算                                        │
│  输出：rmse_theta, rmse_phi, rmse_R, rmse_v                      │
└──────────────────────────────────────────────────────────────────┘
```

### 2.2 数据维度命名约定

| 维度符号 | MATLAB 变量名 | 物理含义 | 默认值 | 论文符号 |
|----------|--------------|----------|--------|----------|
| Ntx | `params.Ntx` | 发射 URA x 方向天线数 | 4 | N_tx,x |
| Nty | `params.Nty` | 发射 URA y 方向天线数 | 4 | N_tx,y |
| Nt | `Ntx × Nty` | 总发射天线数 | 16 | N_tx |
| Mx | `params.Mx` | 接收 URA x 方向天线数 | 8 | M_rx,x |
| My | `params.My` | 接收 URA y 方向天线数 | 8 | M_rx,y |
| Mrx | `Mx × My` | 总接收天线数 | 64 | M_rx |
| Ns | `params.N` | 子载波数（聚合后） | 12672 | N_s |
| K | `params.K` | OFDM 符号数 | 256 | L |
| Q | `params.num_targets` | 目标数量 | 2 | Q |

> ⚠️ **注意**：工程代码中 OFDM 符号数用变量名 `K` 存放，对应论文中的符号 `L`。这是历史遗留命名：**代码 K = 论文 L = 256**。

---

## 3. 自干扰（SI）专题

### 3.1 SI 从哪里来？

全双工基站中，发射和接收天线面板通常紧挨着放置（间距可能只有几个波长，约 10 cm）。发射信号到达接收天线的路径有两条：

```
发射天线 ──── 直达路径（LoS，近场）────→ 接收天线    ← 主要 SI
发射天线 ─→ 周围物体反射 ─→ 接收天线               ← 次要 SI（多径）
```

> **近场 vs 远场**：SI 是"近场"问题——发射和接收天线距离很近（~10λ），电磁波还是球面波，不能简化为平面波。所以 SI 信道模型需要逐天线对分别计算距离。

### 3.2 SI 信道模型（Rician 莱斯模型）

`generate_HSI.m` 实现公式 (13) 的莱斯模型：

```
H_SI = √(κ/(κ+1)) · H_LoS  +  √(1/(κ+1)) · H_NLoS
```

- **κ（K 因子）**：LoS 与 NLoS 的功率比。κ=10 表示 LoS 功率是散射功率的 10 倍，默认值
- **H_LoS**：近场 URA 模型，逐天线对计算三维距离 `R = √(d_sep² + Δx² + Δy²)`，相位 `exp(-j2πR/λ)`，幅度 `1/R`
- **H_NLoS**：Sayeed 虚信道模型（多簇多径），4 簇 × 10 径 = 40 条散射路径

**生活类比**：H_LoS 是你和音箱之间的直线距离——你站多远相位就转多少；H_NLoS 是声音经过墙壁、地面反射后到达麦克风的多条路径，每条路径的距离和衰减都不一样。

### 3.3 三种预编码方案对比

全双工系统的关键是：**发射波束既要覆盖通信用户，又要在接收天线方向形成"零陷"（null）——就像激光笔既要照亮目标，又要避开自己眼睛。**

| 方案 | 原理 | SI 抑制 | 通信质量 | 复杂度 |
|------|------|:---:|:---:|:---:|
| **ZF** | 传统迫零，只考虑通信用户，不管 SI | ❌ 无抑制 | ✅ 最优 | 低 |
| **Nullspace** | 在通信的零空间里，找让 SI 最小的方向 | ✅ 中等 | ⚠️ 略降 | 中 |
| **Lagrange** | 拉格朗日对偶：min SI 功率，约束通信 SINR | ✅ 强 | ⚠️ 可调 | 中 |

**Nullspace 原理（公式 17）**：
```
W = W_ZF - Nc · pinv(H_SI·Nc) · H_SI · W_ZF
```
其中 Nc 是通信信道 `H_c^H` 的零空间基。意思是：在 ZF 的基础上，往零空间方向推一推，减少泄漏到 SI 信道的能量，同时不破坏通信约束。

**Lagrange 原理（公式 16）**：
```
W = R⁻¹ H_c (H_c^H R⁻¹ H_c)⁻¹,  R = H_SI^H H_SI
```
本质是加权 ZF：在 SI 信道强的方向少发射，弱的方向多发射。

### 3.4 数字自干扰消除（SIC）

即使做了空间域预编码，仍可能有残余 SI。数字 SIC（公式 50）在接收端直接减：

```
y_SIC = y_rx - Ĝ_SI · x_tx
```

因为我们知道发射信号 `x_tx` 和 SI 信道 `H_SI`，可以把 SI 贡献算出来再减掉。

> ⚠️ **实际限制**：SIC 的效果受 SI 信道估计精度的影响。在仿真中我们假设 SI 信道完美已知（`enable_SIC = true` 时直接减），实际系统中信道估计误差会限制 SIC 的增益。

### 3.5 SI 对估计器的影响机制

SI 信号在 RD（距离-多普勒）功率图中表现为：
- **近距离（~0.1 m）处出现强假峰**——因为 SI 路径非常短
- **噪声地板整体抬高**——因为 SI 功率参与噪声归一化

`joint_estimator_fast.m` 通过 `R_min_gate = 20 m`（距离门限）排除 SI 假峰，防止近距离 SI 峰被误判为目标。

---

## 4. 算法原理详解

### 4.1 基准论文

本项目的理论基础来自：

> **Z. Xiao et al., "A Novel Joint Angle-Range-Velocity Estimation Method for MIMO-OFDM ISAC Systems," IEEE TSP, vol. 72, 2024.**

以及自干扰相关的补充文献：
> Balti et al., Self-Interference Channel Model for Full-Duplex mmWave Systems, 2023.

### 4.2 回波信号模型（含 SI）

论文公式 (7a) + (28) 给出了含 SI 的接收回波完整表达式：

```
y(mx, my, i, l) = Σ_q β_q · a_tx^H(θ_q, φ_q) · x_i[l]          ← 目标回波
                   · exp(j·mx·ω_ax) · exp(j·my·ω_ay)           ← 空间维（角度）
                   · exp(j·i·ω_r)                               ← 快时间维（距离）
                   · exp(j·l·ω_v)                               ← 慢时间维（速度）
                   + β_SI · H_SI · x_i[l]                       ← ★ 自干扰（公式 28）
                   + z(mx, my, i, l)                             ← 噪声
```

四个数字频率与物理参数的关系：

| 频率 | 表达式 | 物理参数 | 方向 |
|------|--------|----------|------|
| ω_ax | `-2πd/λ · sinθ · cosφ` | 俯仰+方位角 | 空间 x |
| ω_ay | `-2πd/λ · sinθ · sinφ` | 俯仰+方位角 | 空间 y |
| ω_r | `-4πΔf · R / c` | 距离 R | 快时间 |
| ω_v | `+4πT · v · fc / c` | 速度 v | 慢时间 |

### 4.3 三步联合估计框架

#### Step 1 — 信道均衡

接收信号先乘以发射信号的共轭（`rx ⊙ conj(tx)`），消除 16-QAM 随机符号带来的随机相位，让目标回波在子载波和符号维度上相干叠加。

#### Step 2 — 空间压缩 + RD 粗检测

取单根接收天线做一次全分辨率 2D-FFT → 距离-多普勒功率图 → NMS 峰值检测。

> **为什么用单天线**：不做波束成形，保留全向性，保证所有方向的目标峰值都在 RD 图中出现。SI 的假峰通过 `R_min_gate=20m` 排除。

#### Step 3 — 逐目标精化

对每个候选目标：
1. **角度**：局部相位补偿聚焦 → 2D-ESPRIT 估计 `(θ, φ)`
2. **距离**：RD 功率图距离维三点抛物线插值 → 亚 bin 精度
3. **速度**：RD 功率图多普勒维三点抛物线插值 → 亚 bin 精度

**多目标干扰消除**：迭代 Gram-Schmidt 投影消除强目标对弱目标的角度估计污染。

---

## 5. 文件地图与职责

### 5.1 核心文件（必须）

| 文件 | 类型 | 职责 | 被谁调用 |
|------|------|------|----------|
| `build_default_params.m` | 函数 | 所有仿真参数的唯一定义点。**含 SI 的全部参数（enable_SI, beta_SI, theta_SI 等）。** | 所有脚本 |
| `generate_HSI.m` | 函数 | **SI 信道生成**：Rician 模型 + 近场 URA LoS + Sayeed NLoS | main.m, SI 仿真脚本 |
| `generate_mimo_ofdm_waveform.m` | 函数 | MIMO-OFDM 发射波形生成。**含三种预编码（ZF/Nullspace/Lagrange），输出 SI 泄漏诊断。** | main.m, 仿真脚本 |
| `design_precoder.m` | 函数 | **预编码核心**：Nullspace（公式 17）和 Lagrange（公式 16）的完整实现 | generate_mimo_ofdm_waveform.m |
| `simulate_radar_channel_3d.m` | 函数 | 雷达回波仿真。**含矩阵 SI 注入（公式 28）和数字 SIC（公式 50）。** | main.m, 仿真脚本 |
| `joint_estimator_fast.m` | 函数 | **核心算法**：两阶段快速联合估计器。含 SI 距离门限排除假峰。 | main.m, 仿真脚本 |
| `evaluate_estimation.m` | 函数 | 估计结果评估：贪心最近邻匹配 + RMSE | main.m, 仿真脚本 |

### 5.2 SI 相关仿真脚本

| 文件 | 职责 | 关键参数 | 预计耗时 |
|------|------|----------|:--------:|
| `main.m` | **SI-ON 基线**：单次估计，默认 `precoder_type='nullspace'`, `beta_SI=1.0` | SI-ON, SNR=10dB | ~60 s |
| `run_si_comparison.m` | **预编码对比**：ZF vs Nullspace vs Lagrange，不同 beta_SI | SI-ON, 3 预编码 × 5 SI 强度 | 可变 |
| `run_si_mse_analysis.m` | **SI MSE 分析**：SI 对 RMSE 的定量影响 | SI-ON | 可变 |
| `task5_rmse_vs_snr_si.m` | **RMSE vs SNR（SI-ON）**：蒙特卡洛扫描 | MC=30, SNR=-30:5:10 | ~3 h |
| `task_mrx_si_sweep.m` | **Mrx+SI 联合扫描**：不同接收天线数 × SI 强度 | Mrx=4/16/64, SI 多档 | 较长 |
| `diag_si_zf_quick.m` | **SI ZF 快速诊断**：ZF 预编码下 SI 效果快速验证 | ZF only, SI-ON | ~2 min |

### 5.3 辅助与可视化文件

| 文件 | 类型 | 职责 |
|------|------|------|
| `apply_nature_axes.m` | 函数 | Nature 期刊风格的坐标轴格式化 |
| `visualize_results.m` | 函数 | 集成版结果可视化 |
| `plot_beamforming.m` | 脚本 | 发射/接收波束方向图（含 SI 方向标注） |
| `tx_beamforming_robust.m` | 函数 | 鲁棒零空间投影发射波束形成 |

### 5.4 诊断与验证脚本

| 文件 | 职责 |
|------|------|
| `diag_guard.m` | 估计器保护逻辑诊断 |
| `diag_candidates.m` | 候选目标检测诊断 |
| `diag_tx_equalization.m` | 发射端均衡诊断 |
| `diag_angle_accuracy.m` | 角度估计精度诊断 |
| `diag_velocity_rootcause.m` | 速度估计根因分析 |
| `test_interp.m` | 抛物线插值 1000 MC 基准测试 |

### 5.5 参考论文代码

| 文件 | 说明 |
|------|------|
| `bf.m` | 师兄波束形成参考脚本（SI 信道 bf.m 风格） |
| `SelfInterferenceChannel_LoS_NLoS_PlotPrep.m` | SI 信道可视化准备 |
| `Low-Complexity-Hybrid-Beamforming-For-MmWave-Full-Duplex-.../` | Balti 2023 全双工混合波束形成参考实现 |

---

## 6. 快速上手

### 6.1 环境要求

- **MATLAB**: R2024a 或更高版本
- **必需工具箱**: Signal Processing Toolbox, Communications Toolbox（`qammod` 函数）
  - 如无 Communications Toolbox，`generate_mimo_ofdm_waveform.m` 会自动降级为手写方形 QAM
- **内存**: 建议 ≥ 16 GB（高精度模式 Ns=12672 时峰值约 5-7 GB）

### 6.2 三步跑通 SI-ON 基线

**第一步：打开 MATLAB，切换到项目根目录**

```matlab
cd('D:\AA 学习项目\AAA 智能反射面辅助通信感知\AAA ZTE_project')
```

**第二步：运行 SI-ON 主流程**

```matlab
main
```

预期输出（约 60 秒后）：

```
=================================================
  MIMO-OFDM ISAC 三维联合估计主流程
=================================================
参数: 阵列=4x4, 单载波子载波=3168, 聚合后等效子载波=12672, 符号=256, 目标数=2
距离分辨率=0.099m, 最大不模糊距离=1250.0m
载波频率=28.00GHz, 子载波间隔=120.000kHz, OFDM符号周期=8.933us

预编码: nullspace, si_leak=1.23e-04, comm_err=2.45e-06

自干扰设置: enable_SI=true, beta_SI=1.000, H_SI 矩阵 64x16
....
```

****



### 6.3 如何修改 SI 参数

```matlab
% 方法 1：在 main.m 中直接修改
params.enable_SI = true;
params.beta_SI   = 10.0;     % SI 比目标强 10 倍
params.precoder_type = 'lagrange';  % 换用拉格朗日预编码

% 方法 2：使用 overrides
overrides = struct();
overrides.enable_SI  = true;
overrides.beta_SI    = 5.0;
overrides.precoder_type = 'nullspace';
overrides.theta_SI   = 30;   % 改 SI 到达角
overrides.phi_SI     = 45;
overrides.kappa_SI   = 20;   % 更强的 LoS 分量
params = build_default_params(overrides);
```

### 6.4 运行 SI 强度扫描

```matlab
% SI 强度对比（ZF vs Nullspace vs Lagrange）
run_si_comparison

% RMSE vs SNR（SI-ON, MC=30）
task5_rmse_vs_snr_si

% 不同接收天线 + 不同 SI 强度的联合扫描
task_mrx_si_sweep
```

---

## 7. 参数配置指南

### 7.1 SI 参数速查表

| 参数路径 | 默认值 | 单位 | 物理含义 | 修改建议 |
|----------|--------|------|----------|----------|
| `params.enable_SI` | true | - | 是否注入自干扰 | SI-ON 实验设 true |
| `params.beta_SI` | 0.001 | - | SI 相对强度（相对最强目标幅度） | **对比实验设为 1~100** |
| `params.theta_SI` | 10.5 | 度 | SI 到达俯仰角 | 点散射模式用 |
| `params.phi_SI` | 10.5 | 度 | SI 到达方位角 | 点散射模式用 |
| `params.R_SI` | ~0.107 m | m | SI 路径距离（= 10λ） | 近场 ≈ 10 cm |
| `params.v_SI` | 0 | m/s | SI 多普勒速度 | 一般是 0（收发静止） |
| `params.kappa_SI` | 10 | - | Rician K 因子 | 越大 LoS 越强 |
| `params.H_SI_matrix` | auto | - | SI 信道矩阵 (Nr × Nt) | 自动生成，也可手动注入 |
| `params.enable_SIC` | false | - | 是否启用数字 SI 消除 | 需要 H_SI_matrix |
| `params.precoder_type` | 'nullspace' | - | 预编码方案 | 'zf' / 'nullspace' / 'lagrange' |
| `params.beta_SI_scale_list` | [1,10,100,1000,10000] | - | SI 强度扫描列表 | run_si_comparison 使用 |

### 7.2 3GPP FR2 OFDM 参数

| 参数 | 3GPP 标准值 | 本项目值 | 说明 |
|------|:----------:|:--------:|------|
| 子载波间隔 Δf | 120 kHz (μ=3) | 120 kHz | TS 38.211 |
| 资源块数 N_RB | 264 | 264 | 单 CC 最大 264 RB @ 120kHz |
| 单载波子载波数 | 264×12 = 3168 | 3168 | - |
| 循环前缀 CP | 0.59 μs | 0.6 μs | 差异 1.7% |
| 单载波带宽 | 380.16 MHz | 380.16 MHz | ≤ FR2 最大 400 MHz |
| 载波聚合数 | ≤ 16 | 4 | 满足 1.5 GHz 总带宽需求 |

### 7.3 估计器参数调优（SI 相关）

| 参数 | 默认值 | SI-ON 推荐 | 作用 |
|------|:------:|:----------:|------|
| `R_min_gate` | 20 m | 20 m | 排除近距离 SI 假峰的距离门限 |
| `num_candidates` | 64 | 64 | SI-ON 时增加候选数防漏检 |
| `n_samp_r` | 256 | 384 | SI 抬高噪声地板，需更大窗口 |
| `enable_hann` | true | true | 降旁瓣，SI 假峰更窄 |

---

## 8. 核心代码详解

### 8.1 `generate_HSI.m` — SI 信道生成

**输入**：`cfg` 结构体
- `model`: `'ura_rician'`（推荐）或 `'ula_simple'`（兼容师兄 bf.m）
- `kappa_SI`: Rician K 因子（默认 10）
- `Nt_total, Nr_total`: 收发天线总数

**输出**：
- `H_SI`: (Nr_total × Nt_total) 复矩阵
- `info`: 含 `H_LoS`, `H_NLoS`, Frobenius 范数等诊断

**内部流程**：

```
① 生成 H_LoS（近场 URA 模型）
   ┌─ 计算 TX/RX 面板上每个阵元的物理坐标（单位：波长）
   ├─ 逐天线对计算三维距离: R = √(d_sep² + Δx² + Δy²)
   ├─ 相位: exp(-j·2π·R)
   ├─ 幅度: 1/R（近场球面波衰减）
   └─ 归一化: ||H_LoS||_F² = Nt·Nr

② 生成 H_NLoS（Sayeed 虚信道）
   ┌─ 随机生成 Ncl=4 个簇，每簇 Nray=10 条径
   ├─ 角度扩展: std_phi=0.1, std_theta=0.1
   └─ 归一化: ||H_NLoS||_F² = Nt·Nr

③ 公式 (13) 合成
   H_SI = √(κ/(κ+1)) × H_LoS + √(1/(κ+1)) × H_NLoS

④ 后续不再归一化 → 保持 κ 的物理含义
```

**生活类比**：H_LoS 是你和音箱之间的距离决定的（距离越远信号越弱），H_NLoS 是房间墙壁反射的混响（随机但符合统计规律），κ 控制直达声和混响的比例。

### 8.2 `design_precoder.m` — 预编码设计

**输入**：
- `H_c` (Nt × K)：通信信道
- `H_SI` (Nr × Nt)：SI 信道
- `method`：`'zf'` / `'nullspace'` / `'lagrange'`

**Nullspace 核心逻辑**（公式 17）：

```matlab
W0 = H_c / (H_c' * H_c);           % 传统 ZF
Nc = null(H_c');                    % 通信的零空间基
H_SI_Nc = H_SI * Nc;               % SI 在零空间上的投影
c = pinv(H_SI_Nc) * (H_SI * W0);   % 最小化 SI 泄漏的修正系数
W = W0 - Nc * c;                   % ZF + 零空间修正
```

> **关键**：修正项 `Nc * c` 完全在通信的零空间内 → 不破坏通信约束 `H_c^H W = I`，同时尽可能压低 `||H_SI W||`。

**Lagrange 核心逻辑**（公式 16）：

```matlab
R = H_SI' * H_SI;                  % SI 协方差矩阵
W = R\H_c / (H_c' * (R\H_c));     % 加权 ZF
```

> **本质**：在 SI 信道特征方向上的功率分配。H_SI 强特征值对应方向 → R 的特征值大 → `R\H_c` 在该方向上的分量被压低 → 发射能量自动避开 SI 强方向。

### 8.3 `generate_mimo_ofdm_waveform.m` — 预编码选择与 SI 泄漏诊断

在预编码循环中，每个子载波独立计算并累积诊断量：

```matlab
for i = 1:Ns
    H_i = H(:, :, i);
    switch precoder_type
        case 'zf'
            W_i = H_i / (H_i' * H_i);
            W_i = W_i / norm(W_i, 'fro');       % 功率归一化
            si_leak_all(i) = norm(H_SI_i * W_i, 'fro')^2;  % SI 泄漏诊断
        case {'nullspace', 'lagrange'}
            [W_i, d_i] = design_precoder(H_i, H_SI_i, precoder_type);
            si_leak_all(i) = d_i.si_leak;
    end
end
precoder_info.si_leak_avg = mean(si_leak_all);   % 平均 SI 泄漏
```

> **si_leak 解读**：这个值越小，说明发射信号经过 SI 信道后到达接收天线的能量越少，预编码的 SI 抑制效果越好。

### 8.4 `simulate_radar_channel_3d.m` — SI 注入与 SIC

#### 矩阵 SI 注入（公式 28）

```matlab
for l_idx = 1:L                         % 256 个 OFDM 符号
    x_l = reshape(tx_signal(:,:,:,l_idx), Nt_total, Ns);  % (16, 12672)
    y_si_l = beta_SI * H_SI_mat * x_l;  % (64, 12672) — 真实矩阵乘
    rx_cube(:,:,:,l_idx) += reshape(y_si_l, Mx, My, Ns);
end
```

> **为什么是矩阵乘而不是标量乘**：每个收发天线对的 SI 信道都不同（近场距离不同），不能简化成一个标量。要做 `(64×16) × (16×12672) = (64×12672)` 的矩阵乘。

#### 数字 SIC（公式 50）

```matlab
if enable_SIC
    for l_idx = 1:L
        x_l = reshape(tx_signal(:,:,:,l_idx), Nt_total, Ns);
        y_sic_l = beta_SI * H_SI_mat * x_l;  % 重建 SI
        rx_cube(:,:,:,l_idx) -= reshape(y_sic_l, Mx, My, Ns);  % 减去
    end
end
```

> **SIC 效果**：如果 H_SI 完美已知，理论上可以完全消除 SI。实际中信道估计误差会限制 SIC 增益。

#### 噪声地板计算

```
target_sig_pow = mean(|rx_cube|²)      ← 基于纯目标回波（SI 注入前）
noise_pow = target_sig_pow / SNR       ← 按目标功率算噪声
rx_cube += noise                        ← 叠加噪声（SI 注入后）
```

> ⚠️ **与旧版的区别**：v2.0 的噪声在 SI 之后加，导致噪声地板被 SI 抬高。v3.0 改为基于纯目标功率计算噪声，保证 SNR 的物理含义准确。

### 8.5 `joint_estimator_fast.m` — SI 感知的估计器

估计器中与 SI 直接相关的处理：

```matlab
% RD 峰值检测后，用距离门限排除 SI 假峰
for k = 1:num_peaks
    R_bin = peak_distance_estimates(k);
    if R_bin < cfg.R_min_gate   % 默认 20 m
        continue;                % SI 假峰在 0.1 m 附近，直接跳过
    end
    % 正常处理...
end
```

> **为什么 SI 峰在 0.1 m**：SI 路径 ≈ 10λ ≈ 10 cm，在距离上表现为极近的峰值。真实目标通常在 200 m+ 量级，设置 20 m 的门限不会误杀真实目标。

---

## 9. 常见问题 FAQ

**Q1：为什么 SI-ON 时 RMSE 全都很大甚至 NaN？**

A：可能原因：
- `beta_SI` 太大（> 100），SI 完全淹没了目标回波 → 减小 `beta_SI` 或启用 `enable_SIC`
- 预编码类型不对：ZF 不抑制 SI → 换用 `'nullspace'` 或 `'lagrange'`
- `R_min_gate` 太小，SI 假峰被当成目标 → 增大到 20 m 以上

**Q2：Nullspace 和 Lagrange 哪个更好？**

A：取决于场景：
- **SI 很强（β > 10）**：Lagrange 更好，直接优化 SI 功率
- **SI 适中（β < 1）**：Nullspace 更好，通信质量损失更小
- **只用 ZF**：不推荐 SI-ON 场景，SI 泄漏无抑制

**Q3：SIC 为什么没有完全消除 SI？**

A：代码中 SIC 用已知的 H_SI 重建 SI，理论上完美。但：
- 实际系统中 H_SI 有估计误差
- 发射机非线性失真（PA 非线性）无法用线性模型消除
- 可以通过添加 `params.sic_error_db`（信道估计误差）模拟实际限制

**Q4：如何手动构造不同的 H_SI 来测试？**

```matlab
% 方法：手动覆盖 H_SI_matrix
custom_HSI = randn(64, 16) + 1j*randn(64, 16);  % 纯瑞利 SI
custom_HSI = custom_HSI / norm(custom_HSI, 'fro') * sqrt(64*16);
params.H_SI_matrix = custom_HSI;
```

**Q5：运行 `task5_rmse_vs_snr_si` 时 MATLAB 崩溃？**

A：内存不足。这个脚本每轮 MC 都做：矩阵 SI(64×16×12672×256) + 4D FFT。
- 设 `enable_carrier_aggregation = false`（Ns=3168，内存降 4×）
- 或减少 `MC` 到 10
- 或用 `task5_rmse_vs_snr_si_fast.m`（低精度快速版）

**Q6：点散射 SI vs 矩阵 SI，什么时候用哪个？**

A：
- **矩阵 SI（推荐）**：用 `H_SI_matrix`，精确建模每个天线对的 SI 信道，适合系统级仿真
- **点散射 SI**：用 `theta_SI/phi_SI/R_SI`，简化为一个 SI 点源，适合快速验证和早期调试

---

## 附录 A：代码修改指南

### A.1 修改 SI 信道参数

编辑 `generate_HSI` 的调用处（通常在 `main.m` 第 46-57 行）：

```matlab
hsi_cfg = struct( ...
    'model',    'ura_rician', ...
    'kappa_SI', 20, ...        % 改 K 因子
    'd_sep_wl', 5, ...         % 改面板间距（波长）
    ...);
```

### A.2 添加新的预编码方案

1. 在 `design_precoder.m` 的 `switch method` 中添加新分支
2. 在 `generate_mimo_ofdm_waveform.m` 的 `switch precoder_type` 中引入新选项
3. 在 `build_default_params.m` 中可加入新方案的专用参数

### A.3 导出 SI 分析数据

```matlab
% 运行 SI 比较后，保存数据供 Python/Excel 分析
run_si_comparison
% 结果在 workspace 中
save('si_analysis.mat', 'si_results', '-v7.3');
```

---

> **文档维护者**：Hermes Agent（自动生成）
> **审阅者**：蒋老师（邓紫涵）
> **项目验收方**：ZTE / SANECHIPS
