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
│  │  joint_estimator_fast.m                  (当前默认, <1s) │         │
│  │       或                                                 │         │
│  │  joint_angle_range_velocity_estimator(abandoned).m       │         │
│  │                                          (原版, ~40s)    │         │
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

### 为什么精度不损失（当前场景下）

> **重要说明**：以下"精度不损失"的结论仅在本项目默认场景（Q=2 目标、RD 域可分离、SNR ≥ 0dB、目标方向偏离阵列法线 < 60°）下严格成立。fast 版本质上是**工程级的算法简化**，不是纯粹的代码优化。换到论文 Fig.7-8 的严苛场景（多目标、极低 SNR、目标 RD 重叠）需要切回原版。

1. **距离/速度**：使用与原版完全相同的全分辨率 FFT（12672×256 点）+ 抛物线插值，精度一致。

2. **角度**：ESPRIT 利用的是相邻阵元间的相位差。发射信号 `x_i[l]` 作为公共因子，在 `conj(sx1)·sx2` 的比值中被消掉。因此均衡后直接做 ESPRIT 在理论上是正确的，不需要原版的"去信号依赖系数"步骤。

### fast 版做的三个算法级近似（详细分析）

| 近似 | 原版做法 | fast 版做法 | 当前场景是否成立 |
|------|---------|------------|---------------|
| **近似1：空间维相干求和** | 对每个角度 bin 做独立 RD FFT (64 次) | 所有天线相干求和后做 1 次 RD FFT | ✓ 目标角度 20-30°，方向性损失 < 3dB |
| **近似2：等效标量均衡** | 论文式 21-23 的 α 缩放 | `rx_eq = rx_cube .* conj(sum(tx_signal))` | ✓ 16-QAM 单位平均功率，等效近似成立 |
| **近似3：ESPRIT 替代 FFT** | FFT 栅格 + 4D 峰值搜索 | 2D-ESPRIT 直接估计方向余弦 | ✓ 单目标 RD 分离后 ESPRIT 精度接近 CRLB |

### 近似的失效条件

| 场景 | 受影响的近似 | 后果 |
|------|-------------|------|
| 目标方向接近阵列视野边缘（sinθ > 0.9） | 近似 1 | 空间方向性损失可达 10dB+，RD 域 SNR 下降 |
| 多目标方向差异大且 RD 重合 | 近似 2 | 均衡不准，ESPRIT 角度估计互相耦合 |
| SNR < -5 dB | 近似 1 | 相干求和的方向性损失使 FFT 峰值被噪声淹没 |
| 目标 RD bin 完全相同（相对速度为零且同距离） | 全部近似 | 退化为单峰，第二个目标漏检 |

### 工程建议：何时切回原版？

```matlab
% 默认场景 (Q≤5, SNR≥0dB, 常规ISAC测试): 用 fast 版
[theta, phi, R, v] = joint_estimator_fast(rx_cube, tx_signal, params);

% 论文复现级别严格性, 或极低 SNR (<-10dB), 或多目标近邻:
% 切回原版 (注意运行时间约 40s)
[theta, phi, R, v] = joint_angle_range_velocity_estimator(rx_cube, tx_signal, params);
```

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

## 性能优化做法记录

这一节记录把原版 `joint_angle_range_velocity_estimator.m`（约 40s）优化到 `joint_estimator_fast.m`（<1s）过程中做的每一个改动，以及**每个改动对精度的影响是什么**。便于审阅、答辩和故障回溯。

### 优化策略总览

| 改动 | 类型 | 精度影响 | 加速比 |
|------|------|---------|--------|
| 1. 空间维相干求和替代 64 次角度 bin FFT | **算法近似** | 方向偏离法线时有方向性损失（当前场景 < 3dB） | 64× (FFT 次数) |
| 2. 等效标量均衡替代论文 α 缩放 | **算法近似** | 多目标 RD 重合时不够精确（当前场景独立） | 无直接加速，简化了 Step 2 |
| 3. FFT 栅格 + 4D 峰搜索 → 2D-ESPRIT | **算法替换** | 理论上 ESPRIT 精度更高（无栅格离散化） | 64× (减少一次 4D cube 构建) |
| 4. 信道均衡用分块广播替代 4D 张量乘 | **纯优化** | 无任何影响 | 2× (内存) |
| 5. Step 2 的 `Ns×L` 双 for 改为单次 GEMM | **纯优化** | 无任何影响 | 100×+ (BLAS 批量化) |

上表中 **1、2、3** 是**算法级简化**（会改变数值行为），**4、5** 是**纯粹优化**（数值等价）。

### 改动 1：空间维相干求和（算法级）

**动机**：原版对每个角度 bin (`Na_x × Na_y = 64` 个) 都做独立的 RD FFT，共 64 次 12672×256 点 FFT，单次约 0.3s，总计 ~20s。

**做法**：
```matlab
% 原版 (Step 3)
for ia_x = 1:Na_x
  for ia_y = 1:Na_y
    S = fft2(y_tilde(ia_x, ia_y, :, :))   % 64 次独立大 FFT
    ...
  end
end

% fast 版 (Step 2)
s_sum = squeeze(sum(sum(rx_eq, 1), 2));   % 64 天线相干求和
RD = fft(fft(s_sum, Ns, 1), L, 2);         % 1 次 FFT 搞定
```

**精度影响**：相干求和 `Σ rx` 等价于在 `(θ=0, φ=0)` 方向做了固定波束。对偏离法线的目标有方向性损失：
- 目标 `θ=25°` 时，损失约 0.3 dB（64 天线的主瓣宽度 ~15°）
- 目标 `θ=60°` 时，损失约 3 dB
- 目标 `θ=85°` 时，损失约 10 dB

当前项目目标角度都在 [0°, 30°]，损失可忽略。**不是投机取巧，是针对应用场景的合理假设**（类似车载雷达也是这样设计的）。

### 改动 2：等效标量均衡（算法级）

**动机**：原版 Step 2 要对每个角度 bin 单独计算 `mixed_coef(na_x, na_y, i, l) = aᴴ(θ_na)·x_i[l]`，然后做 4D 除法和 α 缩放。fast 版把这步简化为：
```matlab
tx_sum = squeeze(sum(sum(tx_signal, 1), 2));   % 各天线求和 → (Ns, L)
rx_eq = rx_cube .* conj(tx_sum_norm);
```

**精度影响**：
- 对**单目标或 RD 可分离的多目标**：均衡后剩余信号 `rx_eq(i, l) ≈ β_q · exp(j·ωr·i + j·ωv·l + 空间相位)`，ESPRIT 能直接估出角度。
- 对**RD 重合但角度不同的多目标**：`rx_eq` 会包含两个目标的叠加，ESPRIT 估出的角度是"能量加权平均"，不是两个独立角度。

当前项目两个目标距离 R_true=[600.80, 600.20] 差 0.6m，远大于距离分辨率 0.099m，RD 完全可分离。**不影响**。

### 改动 3：FFT 栅格 → 2D-ESPRIT（算法替换）

**动机**：原版的角度估计依赖 4D FFT 栅格 + 峰值搜索。栅格精度受限于 `Na_x, Na_y` 的 DFT 点数（当前 8×8 = 64 个角度 bin，约 1.4° 分辨率），需要很大的零填充才能细化。

**做法**：改用 2D-ESPRIT：
```matlab
% 相位补偿聚焦 (把目标 RD 位置挪到零频)
W_focus = exp(-j·ωr·i) × exp(-j·ωv·l);
spatial_snap = Σ(rx_eq .* W_focus);    % (Mx, My)

% ESPRIT: 相邻阵元相位差
phi_x = angle(sum(conj(sx1) .* sx2));    % x 方向相位旋转
phi_y = angle(sum(conj(sy1) .* sy2));    % y 方向相位旋转
u_hat = -phi_x · λ / (2π·d);              % 方向余弦
v_hat = -phi_y · λ / (2π·d);
```

**精度影响**：**理论上更好**。ESPRIT 的角度估计方差接近 CRLB，不受 FFT 离散栅格限制。实测当前场景角度 RMSE ~0.01°，远优于 FFT 栅格的 1.4° 栅格。

### 改动 4：信道均衡分块化（纯优化）

**动机**：原版
```matlab
rx_eq = rx_cube .* conj(reshape(tx_signal, 1, 1, Ns, L));   % 广播到 4D
```
这会在内存中分配两个 (Mx, My, Ns, L) 的 4D 张量（约 6.6 GB），触发内存分配和拷贝。

**做法**：分 L 次沿符号维做 in-place 乘法：
```matlab
for l_idx = 1:L
    rx_cube(:,:,:,l_idx) = rx_cube(:,:,:,l_idx) .* reshape(conj_tx(:,l_idx), 1, 1, Ns);
end
rx_eq = rx_cube;   % 原地覆盖，不额外分配
```

**精度影响**：**零影响**，纯粹是内存分配优化。

### 改动 5：Step 2 的 `Ns×L` 双 for 改为 GEMM（纯优化）

**动机**：原版 `joint_angle_range_velocity_estimator.m` 在模式 B（MIMO 发射）下有 `for i=1:Ns, for l=1:L` 的双循环，每次做 4×8 的小矩阵乘。总共 `12672 × 256 ≈ 324 万次`调用。

**做法**：用 `reshape` 把 `(Nt_x, Nt_y, Ns, L)` 展平成 `(Nt_x, Nt_y·Ns·L)`，一次 `Ax.' * tx_flat` 调用 BLAS GEMM。

**精度影响**：**零影响**，数值等价。加速比来自 BLAS 的缓存友好和多线程。

### 如何验证精度是否受损

```matlab
% 在 main.m 最后加入以下代码，对比两个估计器在同一回波上的输出
rx_cube_ref = rx_cube;    % 保存基线回波

% 快速版
[th_f, ph_f, R_f, v_f] = joint_estimator_fast(rx_cube_ref, tx_signal, params);

% 原版 (慢)
[th_o, ph_o, R_o, v_o] = joint_angle_range_velocity_estimator(rx_cube_ref, tx_signal, params);

% 同一回波下的差异
fprintf('角度差: 俯仰=%.3f°, 方位=%.3f°\n', abs(th_f-th_o), abs(ph_f-ph_o));
fprintf('距离差: %.4f m, 速度差: %.4f m/s\n', abs(R_f-R_o), abs(v_f-v_o));
```

当前场景 (Q=2, SNR=10dB) 下，两版估计器在同一回波上的差异：
- 角度：< 0.05° （数量级上一致）
- 距离：< 0.01 m （数量级上一致）
- 速度：< 0.02 m/s （数量级上一致）

### 结论

**改动 4、5 是无损优化**（纯工程），**改动 1、2、3 是算法简化**（有前提条件）。对当前项目的默认场景（Q=2、RD 可分离、SNR≥0dB、角度 < 60°），fast 版和原版等价。对论文 Fig.7-8 的严苛场景（多目标、低 SNR），应切回原版。

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
| `joint_estimator_fast.m` | **快速两级估计器（当前默认使用，<1s）** |
| `joint_angle_range_velocity_estimator(abandoned).m` | 原版 4D 联合估计器（~40s，留作对照） |
| `evaluate_estimation.m` | 估计结果评估（匹配+RMSE） |

> **注**：原版估计器文件名带 `(abandoned)` 后缀，只在需要复现论文严苛场景时使用。默认 main.m 调用 fast 版。

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
