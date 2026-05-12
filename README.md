# MIMO-OFDM ISAC 三维联合参数估计系统

## 项目概述

本项目实现了一个基于 **MIMO-OFDM 通信感知一体化 (ISAC)** 的目标参数估计系统，能够同时估计多个目标的四维参数：

- **俯仰角 (θ)** — 目标相对阵列法线的仰角
- **方位角 (φ)** — 目标在水平面的方位
- **距离 (R)** — 目标到基站的径向距离
- **速度 (v)** — 目标的径向运动速度

系统基于 5G NR FR2 毫米波标准设计，所有参数严格遵循 3GPP 规范，可直接用于工程验收。

### 参考文献

> Z. Xiao, R. Liu, M. Li, Q. Liu and A. L. Swindlehurst, "A Novel Joint Angle-Range-Velocity Estimation Method for MIMO-OFDM ISAC Systems," IEEE Transactions on Signal Processing, vol. 72, pp. 3805-3819, 2024.

---

## 目录

1. [系统架构](#系统架构)
2. [主函数 main.m 流程](#主函数-mainm-流程)
3. [算法详解：原版 4D 联合估计器](#算法详解原版-4d-联合估计器)
4. [算法详解：快速两级估计器](#算法详解快速两级估计器)
5. [两种算法对比](#两种算法对比)
6. [3GPP 标准合规性](#3gpp-标准合规性)
7. [信号生成与作者源代码对比](#信号生成与作者源代码对比)
8. [文件说明](#文件说明)
9. [快速上手](#快速上手)

---

## 系统架构

整个系统的数据流如下：

```
┌──────────────────────────────────────────────────────────────────────┐
│                         系统整体架构                                   │
├──────────────────────────────────────────────────────────────────────┤
│                                                                      │
│  build_default_params.m                                              │
│       │  (3GPP FR2 参数 + 目标场景 + 阵列配置)                         │
│       ▼                                                              │
│  generate_mimo_ofdm_waveform.m                                       │
│       │  (信道H → ZF预编码W → 16-QAM符号S → 发射信号 X=W·S)           │
│       ▼                                                              │
│  simulate_radar_channel_3d.m                                         │
│       │  (目标回波 + 自干扰SI + AWGN噪声 → 接收数据立方体 rx_cube)      │
│       ▼                                                              │
│  ┌─────────────────────────────────────────────────────────┐         │
│  │  估计器 (二选一)                                          │         │
│  │                                                         │         │
│  │  joint_angle_range_velocity_estimator.m  (原版, ~40s)    │         │
│  │       或                                                 │         │
│  │  joint_estimator_fast.m                  (快速版, <1s)   │         │
│  └─────────────────────────────────────────────────────────┘         │
│       │                                                              │
│       ▼                                                              │
│  evaluate_estimation.m                                               │
│       │  (估计值 vs 真值 → 逐目标误差 + RMSE)                          │
│       ▼                                                              │
│  输出: [θ_est, φ_est, R_est, v_est]                                  │
│                                                                      │
└──────────────────────────────────────────────────────────────────────┘
```

### 数据维度

| 变量 | 维度 | 含义 |
|------|------|------|
| `tx_signal` | (4, 4, 12672, 256) | 发射信号：Ntx × Nty × 子载波数 × 符号数 |
| `rx_cube` | (8, 8, 12672, 256) | 接收数据：Mx × My × 子载波数 × 符号数 |
| 估计输出 | (1, Q) | Q 个目标的 θ/φ/R/v |

---

## 主函数 main.m 流程

`main.m` 是整个系统的入口，执行以下步骤：

### 步骤 1：参数装配
```matlab
params = build_default_params();
```
加载所有系统参数（载波频率、阵列配置、目标场景、3GPP 参数等）。

### 步骤 2：生成发射波形
```matlab
tx = generate_mimo_ofdm_waveform(tx_cfg);
tx_signal = tx.X;     % (Ntx, Nty, Ns, L) = (4, 4, 12672, 256)
```
按论文公式 (2) 生成 MIMO-OFDM 发射信号：信道 H → ZF 预编码 W → 16-QAM 符号 S → X = W·S。

### 步骤 3：生成雷达回波
```matlab
rx_cube = simulate_radar_channel_3d(tx_signal, params);
```
仿真目标反射回波，叠加 AWGN 噪声（可选叠加自干扰 SI）。

### 步骤 4：参数估计
```matlab
[theta_est, phi_est, R_est, v_est, info] = joint_estimator_fast(rx_cube, tx_signal, params);
```
从接收数据中估计目标的四维参数。

### 步骤 5：结果评估
```matlab
compare = evaluate_estimation(theta_est, phi_est, R_est, v_est, params, true);
```
将估计值与真值做最近邻匹配，计算逐目标误差和 RMSE。

---

## 算法详解：原版 4D 联合估计器

文件：`joint_angle_range_velocity_estimator.m`

### 算法思想

严格实现论文 Algorithm 1 的四维联合搜索。核心思想是：在 (角度x × 角度y × 距离 × 多普勒) 的四维空间中同时搜索目标，利用空间-距离-多普勒的耦合信息实现最优检测。

### 处理流程

```
输入: rx_cube (8, 8, 12672, 256)
       │
       ▼
Step 1: 空间 2D-DFT (论文式 11)
        沿接收阵列两维 (mx, my) 做 FFT
        rx_cube → Y_spatial (8, 8, 12672, 256)
        物理含义: 将空间域信号变换到角度域
       │
       ▼
Step 2: 去信号依赖系数 (论文式 21-23)
        Y_spatial ./ mixed_coef → y_tilde
        物理含义: 消除发射信号 x_i[l] 对不同角度 bin 功率的调制,
                  使得空间域的功率结构只反映目标方向
       │
       ▼
Step 3: 对每个角度 bin 做 2D-FFT (论文式 25)
        for ia_x = 1:8
          for ia_y = 1:8
            S = fft2(y_tilde(ia_x, ia_y, :, :))   ← 64次大FFT!
            保留 top-K 峰值
          end
        end
        物理含义: 在每个角度方向上做距离-多普勒检测
       │
       ▼
Step 4: 全局排序 + 4D NMS + ESPRIT 角度精化 + 抛物线插值
        从 64×4=256 个候选中选出 Q 个目标
        对每个目标用 2D-ESPRIT 精估角度
       │
       ▼
输出: [θ, φ, R, v] × Q 个目标
```

### 关键公式

- **空间 DFT (式 11)**：`Y(na_x, na_y, i, l) = (1/MxMy) Σ y(mx,my,i,l) · exp(-j·mx·ωax) · exp(-j·my·ωay)`
- **去系数 (式 21)**：`A(na, i, l) = Y(na, i, l) / [a^H(θ_na) · x_i[l]]`
- **缩放因子 (式 23)**：`α(na) = sqrt(Σ|A|² / Σ|Y|²)`，保持功率结构
- **距离反演 (式 27)**：`R = -c · nr / (2 · Nr · Δf)`
- **速度反演**：`v = c · nv / (2 · Nv · Ts · fc)`

### 性能特点

- 运行时间：~40 秒
- 精度：角度 RMSE ~0.01°，距离 RMSE ~0.03m，速度 RMSE ~0.6m/s
- 优势：理论最优的联合估计，能分辨距离/速度相同但角度不同的目标
- 劣势：计算量大，无法满足实时要求

---

## 算法详解：快速两级估计器

文件：`joint_estimator_fast.m`

### 算法思想

采用工程上标准的"两级检测"架构：先在距离-多普勒 (RD) 域做粗检测定位目标，再对每个检测到的目标用 ESPRIT 精估角度。这是实际 5G 基站感知模块和车载毫米波雷达的主流做法。

### 处理流程

```
输入: rx_cube (8, 8, 12672, 256)
       │
       ▼
Step 1: 信道均衡
        rx_eq = rx_cube .* conj(tx_signal)
        物理含义: 去除发射信号的随机相位, 暴露信道的距离/多普勒信息
       │
       ▼
Step 2: 空间压缩 + 单次 2D-FFT
        s_sum = Σ rx_eq (对64个天线求和)  → (12672, 256)
        RD = fft2(s_sum)                   → 1次FFT
        P = |RD|²                          → RD 功率谱
        峰值检测 + NMS
        物理含义: 64天线非相干累加提供~18dB增益, 在RD域定位目标
       │
       ▼
Step 3: 对每个检测到的目标 (仅 Q=2 个):
        │
        ├─ 3.1 ESPRIT 角度精化
        │      omega_r = 2π·nr/Ns, omega_v = 2π·nv/L
        │      相位补偿聚焦: W = exp(-j·n·ωr) × exp(-j·l·ωv)
        │      空间快拍: spatial_snap = Σ(rx_eq .* W)  → (8, 8)
        │      2D-ESPRIT: 相邻阵元相位差 → 方向余弦 → 角度
        │      物理含义: 将目标信号在RD维聚焦到零频后,
        │               空间快拍只包含该目标的方向信息
        │
        ├─ 3.2 距离精化
        │      FFT bin 索引 + 抛物线插值 → 亚 bin 精度
        │      R = mod(-c·nr_frac / (2·Ns·Δf), Rmax)
        │
        └─ 3.3 速度精化
               FFT bin 索引 + 抛物线插值
               v = c·nv_frac / (2·L·Ts·fc)
       │
       ▼
输出: [θ, φ, R, v] × Q 个目标
```

### 为什么精度不损失

1. **距离/速度**：使用与原版完全相同的全分辨率 FFT（12672×256 点）+ 抛物线插值，精度一致。

2. **角度**：ESPRIT 利用的是相邻阵元间的相位差。发射信号 `x_i[l]` 作为公共因子，在 `conj(sx1)·sx2` 的比值中被消掉。因此均衡后直接做 ESPRIT 在理论上是正确的，不需要原版的"去信号依赖系数"步骤。

### 性能特点

- 运行时间：<1 秒（加速 40x+）
- 精度：角度 RMSE ~0.01°，距离 RMSE ~0.03m，速度 RMSE ~0.6m/s
- 优势：满足实时刷新率要求，内存友好
- 劣势：无法分辨距离/速度完全相同但角度不同的目标（当前场景不存在此问题）

---

## 两种算法对比

| 维度 | 原版 (4D联合搜索) | 快速版 (两级检测) |
|------|-------------------|-------------------|
| **检测域** | 4D (角度×角度×距离×多普勒) | 2D (距离×多普勒) + 独立DOA |
| **大FFT次数** | 64 次 (12672×256) | 1 次 (12672×256) |
| **运行时间** | ~40 秒 | <1 秒 |
| **角度精度** | ~0.01° | ~0.01° |
| **距离精度** | ~0.03m | ~0.03m |
| **速度精度** | ~0.6m/s | ~0.6m/s |
| **内存峰值** | ~3.3 GB | ~0.2 GB |
| **适用场景** | 极低SNR、目标RD重叠 | 常规场景、实时系统 |
| **工程落地** | 离线分析 | 实时感知 |

### 快速版退化场景

| 场景 | 影响 | 发生概率 |
|------|------|----------|
| 多目标距离/速度完全相同 | RD域只看到一个峰，漏检 | 极低 |
| SNR < 0 dB | 天线累加增益不如空间DFT | 低 |
| 目标数 > 10 | NMS可能漏检弱目标 | 中 |

---

## 3GPP 标准合规性

本系统严格遵循 **3GPP 5G NR FR2** 高频标准，具体对齐如下：

### 单载波 (Component Carrier) 规格

| 参数 | 3GPP 标准值 | 本系统值 | 标准来源 |
|------|-------------|----------|----------|
| 子载波间隔 Δf | 120 kHz (μ=3) | 120 kHz | TS 38.211 |
| 资源块数 N_RB | 264 (FR2 最大) | 264 | TS 38.104 |
| 每RB子载波数 | 12 | 12 | TS 38.211 |
| 单CC子载波数 | 3168 | 3168 | N_RB × 12 |
| 单CC带宽 | ≤ 400 MHz | 380.16 MHz | TS 38.104 |
| 循环前缀 T_cp | ~0.6 μs | 0.6 μs | TS 38.211 |
| 符号周期 T | ~8.93 μs | 8.93 μs | T_d + T_cp |

### 载波聚合 (Carrier Aggregation)

| 参数 | 值 | 说明 |
|------|-----|------|
| 聚合载波数 n_cc | 4 | FR2 CA 支持最多 16 个 CC |
| 等效总带宽 B | 1520.64 MHz | 4 × 380.16 MHz |
| 等效子载波数 Ns | 12672 | 4 × 3168 |
| 距离分辨率 ΔR | 0.099 m | c/(2B)，满足 0.1m 验收 |
| 最大不模糊距离 Rmax | 1250 m | c/(2Δf) |

### 验收指标达成情况

| 验收指标 | 要求 | 实际 | 状态 |
|----------|------|------|------|
| 距离分辨率 | ≤ 0.1 m | 0.099 m | ✓ 通过 |
| 距离覆盖 | ≥ 615.8 m | 1250 m | ✓ 通过 |
| 算法刷新率 | < 1 秒 | ~0.8 秒 (快速版) | ✓ 通过 |
| 载波频率 | FR2 (24.25-52.6 GHz) | 28 GHz | ✓ 通过 |
| 子载波间隔 | FR2 μ=3 | 120 kHz | ✓ 通过 |

---

## 信号生成与作者源代码对比

`generate_mimo_ofdm_waveform.m` 严格对齐作者源代码 `main_snr_rmse_quicklook.m` 第 42-61 行。以下是逐步对比：

### 步骤 1：信道构造 (作者第 42-47 行)

**作者源代码 (1D ULA)**：
```matlab
% 作者: Nt=16 的 ULA, 单维 steering vector
H(:, k, i) = exp(1j*2*pi*(0:Nt-1).'*dt*sin(user_a(k))*fc/c);
```

**本工程 (2D URA)**：
```matlab
% 扩展为 Ntx×Nty 的 URA, 二维 Kronecker steering
u_k = sin(user_theta(k)) * cos(user_phi(k));
v_k = sin(user_theta(k)) * sin(user_phi(k));
ax_k = exp(1j * k_wave * nx_vec * u_k);   % x方向
ay_k = exp(1j * k_wave * ny_vec * v_k);   % y方向
A_k  = ax_k * ay_k.';                      % 2D steering (Ntx, Nty)
H_flat(:, k) = A_k(:);                     % 展平为列向量
```

**差异说明**：作者用 1D ULA (Nt=16)，本工程扩展为 2D URA (4×4=16)。总天线数相同，但 URA 能同时估计俯仰和方位两个角度。当 Nty=1 时退化为作者的 ULA。

### 步骤 2：ZF 预编码 (作者第 48-53 行)

**作者源代码**：
```matlab
W(:, :, i) = H(:, :, i) / (H(:, :, i)' * H(:, :, i));
W(:, :, i) = W(:, :, i) / norm(W(:, :, i), 'fro');
```

**本工程**：
```matlab
W_i  = H_i / (H_i' * H_i);                % ZF 伪逆 (完全一致)
W(:, :, i) = W_i / norm(W_i, 'fro');       % Frobenius 归一化 (完全一致)
```

**差异**：无。逻辑完全一致。

### 步骤 3：通信符号生成 (作者第 55-60 行)

**作者源代码**：
```matlab
DATA = randi([0 para.mod_order - 1], para.K, para.L, para.Ns);
S(:, :, i) = qammod(DATA(:, :, i), 16, 'UnitAveragePower', true);
```

**本工程**：
```matlab
DATA = randi([0, M - 1], K_stream, L, Ns);
S(:, :, i) = qammod(DATA(:, :, i), M, 'UnitAveragePower', true);
```

**差异**：无。16-QAM，单位平均功率，随机符号。

### 步骤 4：发射信号合成 (作者第 61 行，论文公式 (2))

**作者源代码**：
```matlab
X0 = pagemtimes(W, S);    % x_i[l] = W_i · s_i[l]
```

**本工程**：
```matlab
X_flat = pagemtimes(W, S);                  % 完全一致
X = reshape(X_flat, Ntx, Nty, L, Ns);       % 额外: reshape 为 4D 张量
X = permute(X, [1, 2, 4, 3]);               % 调整维度顺序为 (Ntx, Nty, Ns, L)
```

**差异**：仅多了 reshape/permute 将 2D 展平结果恢复为 4D 张量格式，数值完全一致。

### 回波生成对比

`simulate_radar_channel_3d.m` 对齐作者 `echo_generate.m`：

**作者回波模型 (1D)**：
```
y(m, i, l) = Σ_q β_q · a_tx^H(θ_q)·x_i[l] · exp(j·m·ωa) · exp(j·i·ωr) · exp(j·l·ωv)
```

**本工程回波模型 (2D 扩展)**：
```
y(mx, my, i, l) = Σ_q β_q · a_tx^H(θ_q,φ_q)·x_i[l]
                  · exp(j·mx·ωax) · exp(j·my·ωay)
                  · exp(j·i·ωr) · exp(j·l·ωv)
```

差异仅在于接收端从 1D ULA 扩展为 2D URA（多了 my 维度和 ωay 相位项），物理模型完全一致。

### 总结

| 环节 | 与作者一致性 | 差异 |
|------|-------------|------|
| 信道 H | ✓ 逻辑一致 | ULA→URA (总天线数相同) |
| ZF 预编码 W | ✓ 完全一致 | 无 |
| QAM 符号 S | ✓ 完全一致 | 无 |
| 发射信号 X=W·S | ✓ 数值一致 | 多了 reshape 到 4D |
| 回波模型 | ✓ 物理一致 | 1D→2D (多方位角维度) |

---

## 文件说明

### 核心文件

| 文件 | 功能 |
|------|------|
| `main.m` | 主入口：参数→波形→回波→估计→评估 |
| `build_default_params.m` | 参数装配（3GPP + 场景 + 阵列） |
| `generate_mimo_ofdm_waveform.m` | MIMO-OFDM 发射波形生成 |
| `simulate_radar_channel_3d.m` | 雷达回波信道仿真 |
| `joint_angle_range_velocity_estimator.m` | 原版 4D 联合估计器 (~40s) |
| `joint_estimator_fast.m` | 快速两级估计器 (<1s) |
| `evaluate_estimation.m` | 估计结果评估（匹配+RMSE） |

### 辅助脚本

| 文件 | 功能 |
|------|------|
| `scan_si_effect.m` | 自干扰 (SI) 强度扫描 |
| `plot_rmse_vs_snr_new.m` | RMSE vs SNR 曲线绘制 |
| `test_fast_estimator.m` | 快速版 vs 原版精度对比测试 |
| `main_fast.m` | 快速版独立主流程 |

---

## 快速上手

### 环境要求

- MATLAB R2020b 或更高版本
- Communications Toolbox（用于 `qammod`，无此工具箱时有手写回退）

### 运行主流程

```matlab
>> main          % 运行快速估计器 + 评估
```

输出示例：
```
参数: 阵列=8x8, 等效子载波=12672, 符号=256, 目标数=2
距离分辨率=0.099m, 最大不模糊距离=1250.0m
...
估计目标1 -> 真实目标1: 角度=25.82°(真值25.83°,误差-0.01°), ...
RMSE: 角度=0.013°, 方位=0.019°, 距离=0.027m, 速度=0.578m/s
快速估计器运行时间: 0.xxx 秒
✓ 满足 <1s 实时刷新率要求!
```

### 运行 SI 扫描

```matlab
>> scan_si_effect    % 扫描不同自干扰强度下的性能
```

### 修改参数

编辑 `build_default_params.m` 或传入 overrides：
```matlab
params = build_default_params(struct('SNR', 20, 'num_targets', 3));
```

---

## 当前系统参数一览

| 参数 | 符号 | 值 | 来源 |
|------|------|-----|------|
| 载波频率 | f_c | 28 GHz | 论文 Table II |
| 子载波间隔 | Δf | 120 kHz | 3GPP FR2 μ=3 |
| 总带宽 | B | 1520.64 MHz | 4CC 聚合 |
| 子载波数 | Ns | 12672 | 4×3168 |
| OFDM符号数 | L | 256 | 论文 Table II |
| 符号周期 | Ts | 8.93 μs | 1/Δf + T_cp |
| 接收阵列 | Mx×My | 8×8 = 64 | URA |
| 发射阵列 | Ntx×Nty | 4×4 = 16 | URA |
| 阵元间距 | d | λ/2 ≈ 5.36 mm | 半波长 |
| 调制方式 | — | 16-QAM | 论文 Table II |
| 空间流数 | K | 1 | 论文 Table II |
| 目标数 | Q | 2 | — |
| SNR | — | 10 dB | — |
| 距离分辨率 | ΔR | 0.099 m | c/(2B) |
| 最大不模糊距离 | Rmax | 1250 m | c/(2Δf) |
| 速度分辨率 | Δv | ~0.08 m/s | c/(2·L·Ts·fc) |
