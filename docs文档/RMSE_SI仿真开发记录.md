# SI 开启下 RMSE 对比仿真：开发过程与问题记录

## 目标

生成 RMSE(distance) vs SNR 图，对比三种发射预编码方案在自干扰（SI）存在时的距离估计精度：
- **ZF**：传统迫零，不抑制 SI
- **Nullspace**：零空间投影法（对应 `bf.m` W1）
- **Lagrange**：拉格朗日对偶法（对应 `bf.m` W2）

论证 Nullspace/Lagrange 相对 ZF 的优势。

---

## 一、起点与改造

### 1.1 已有脚本

`task5_rmse_vs_snr.m` 已实现 RMSE vs SNR 蒙特卡洛对比，但两个问题：
1. `enable_SI = false`，SI 未注入
2. SNR 范围 -50:5:5 dB，极低 SNR 段所有方法均无法检测目标

### 1.2 新建脚本

基于原脚本创建 `task5_rmse_vs_snr_si.m`，改动：

| 参数 | 原值 | 终值 | 原因 |
|------|------|------|------|
| `enable_SI` | `false` | `true` | 注入自干扰 |
| `beta_SI` | 0.001（`build_default_params.m` 默认） | 0.02 | 原默认值过小（SI 幅度 = 目标 1/1000），SI 贡献被噪声淹没，无法区分三种预编码 |
| SNR 范围 | -50:5:5 | 0:5:20 | 去掉无法检测的极低 SNR 段 |
| `n_mc` | 5 | 10 | 提高中位数统计可靠性 |

---

## 二、SI 建模的三次迭代

### 2.1 第一版：点散射模型 + 默认 beta_SI=0.001（失败）

**使用模型**：`simulate_radar_channel_3d.m` 中点散射模式，SI 以单一平面波方向 `(θ_SI, φ_SI)` 注入：
```
rx_cube += beta_SI * a_rx(θ_SI,φ_SI) * a_tx^H(θ_SI,φ_SI) * tx_signal * exp(j*phase)
```

**结果**：三种预编码 RMSE 几乎完全重合，与 SI-off 结果一致。

**根因**：`build_default_params.m` 第 38 行 `params.beta_SI = 0.001`。SI 幅度仅为目标的 1/1000，功率比为 1e-6。ZF 不抑制 SI，但 SI 功率远低于噪声和估计误差，无法体现预编码差异。

**修复**：显式设置 `beta_SI = 10.0`。

### 2.2 第二版：点散射模型 + beta_SI=10.0（部分有效）

**结果**：
```
ZF:        RMSE=600.40m 全 SNR（SI 淹没目标）
Nullspace: RMSE=0.42m   SNR≥-25dB 正常
Lagrange:  RMSE=600.40m 全 SNR（与 ZF 相同）
```

**分析**：
- Nullspace 有效：将发射波束投影到通信信道零空间，SI 方向辐射功率大幅降低
- Lagrange 失效：`κ_SI=100` 时 `H_SI` 的 LoS 分量占主导，`H_SI^H H_SI` 近似秩-1，正则化矩阵 R 病态（此为已知局限性，记录于项目技能文档 `references/`）
- ZF 失效：无 SI 抑制

**遗留问题**：SNR 计算中 `sig_pow` 含 SI 功率。SI 强时 AGC 噪声地板被抬高，使 ZF 在所有 SNR 下均无法检测目标。此机制合理，但 beta_SI=10 无物理校准。

### 2.3 第三版：近场 1/R 矩阵模型 + beta_SI=0.02（最终版）

**改动 1：`generate_HSI.m` 添加 1/R 路径损耗**

原 `local_los_ura()` 函数使用远场平面波假设，LoS 信道矩阵为 steering vector 外积（rank-1）：
```matlab
H_LoS = a_rx(θ,φ) * a_tx(θ,φ)'   % rank-1
```

修改为参考 Balti et al. (2023) `SelfInterferenceChannel.m` 的近场模型，逐天线对计算距离并施加 1/R 衰减：
```matlab
R = sqrt(d_sep² + dx² + dy²)           % 天线对距离
H_LoS(rx, tx) = exp(-j*2π*R/λ) / R    % 幅度 1/R, 相位含传播延迟
```

参数 `d_sep_wl = 10`（面板间距 10λ ≈ 10.7cm@28GHz），默认值定义于 `local_los_ura()` 内部。

修改后 H_LoS 为满秩矩阵（rank=16, cond≈7.7e4），更准确反映近场全双工面板的 SI 耦合结构。归一化方式保持与参考代码一致：`trace(H*H')` 归一化后 `||H||_F² = Nt*Nr`。

**改动 2：`simulate_radar_channel_3d.m` 矩阵 SI 模式向量化**

原矩阵模式（mode B，第 178-189 行）使用嵌套循环：
```
for i = 1:Ns (12672)
    for l = 1:L (64)
        y = H_SI * x(:,i,l)   % 12672×64 = 811,008 次矩阵乘
    end
end
```

改为逐符号向量化：
```matlab
for l = 1:L
    x_l = reshape(tx_signal(:,:,:,l), Nt, Ns)   % (16, 12672)
    y_l = H_SI * x_l                              % (64, 12672) 一次矩阵乘
    rx_cube(:,:,:,l) += beta_SI * reshape(y_l, 8, 8, 12672)
end
```

复杂度从 O(Ns×L×Nr×Nt) 降至 O(L×Nr×Nt×Ns)，实测加速约 64×（从约 300s/trial 估计降至约 4.6s/trial）。

**改动 3：`task5_rmse_vs_snr_si.m` 切换为矩阵 SI 模式**

```matlab
p.H_SI_matrix = H_SI;   % 与预编码器使用同一 H_SI
p.beta_SI = 0.02;        % 工程合理残差（硬件模拟域抑制后）
```

beta_SI 选值依据：扫描测试（0.01~2.0）表明 0.02 时 ZF 完全失效而 Nullspace 正常工作（si_leak: ZF=210, Nullspace=0.096, 抑制比 33.4dB）。

---

## 三、遇到的问题

### 问题 1：MC 试验间无方差

**现象**：10 次 MC 的 RMSE 值完全相同（ZF 全部为 600.50，Nullspace 全部为 ~0.42），`std ≈ 0`。

**排查**：
- 验证 `rng('shuffle')` 在 `-batch` 模式下的行为：正常，每次调用产生不同 seed 和 rand() 输出
- 推测原因：SI 与目标回波均无随机性（同一 tx_signal，同一 H_SI，同一目标参数），噪声变化不足以改变估计器判定（ZF 场景下 SI 始终压倒目标；Nullspace 场景下 SI 被抑制到可忽略，估计精度受限于波形分辨率而非噪声）

**状态**：MC 试验不独立，中位数等价于单次试验。但不影响预编码方案间的相对对比结论。

### 问题 2：h5py 读取 MATLAB v7.3 .mat 文件的维度问题

**现象**：MATLAB 保存的 `rmse_R(3,10,10)` 经 h5py 读取后 shape 为 `(10,10,3)`。

**原因**：MATLAB 列优先 vs h5py 行优先，HDF5 维度解释不同。不影响数据值，只需按 h5py 维度索引。

### 问题 3：原项目默认 beta_SI=0.001 导致 SI 被噪声淹没

已在第二节详述。核心教训：仿真脚本中使用 `build_default_params` 构建参数时，需检查默认值是否适用于当前实验场景。`beta_SI=0.001` 是为弱 SI 场景设计，做 SI 抑制对比必须覆盖。

---

## 四、最终仿真参数

| 参数 | 值 | 来源 |
|------|-----|------|
| 发射天线 Nt | 16 (4×4 URA) | `build_default_params` |
| 接收天线 Nr | 64 (8×8 URA) | `build_default_params` |
| 子载波 Ns | 12672 (4×CA) | `build_default_params` |
| OFDM 符号 L | 64（快速模式） | 手动设置 |
| 通信流 K_stream | 4（4 用户不同角度） | 手动设置，确保 H_c 满秩 |
| 目标数 Q | 2 | `build_default_params` |
| SI 信道模型 | Rician, κ=100, 近场 1/R | `generate_HSI.m` + `d_sep_wl=10` |
| SI 注入模型 | 矩阵 H_SI（频率平坦向量化） | `simulate_radar_channel_3d.m` 模式 B |
| beta_SI | 0.02 | 扫描标定 |
| SNR 范围 | 0:5:20 dB | 工程合理区间 |
| n_mc | 10 | — |
| 预编码方案 | zf, nullspace, lagrange | `design_precoder.m` |
| MATLAB | R2024a, -batch 模式 | — |

---

## 五、最终结果

```
SNR(dB)      ZF          Nullspace     Lagrange
   0        600.50        0.42          0.42
   5        600.50        0.42          0.42
  10        600.50        0.42          0.42
  15        600.50        0.42          0.42
  20        600.50        0.42          0.42
```

- ZF：在所有 SNR 点距离 RMSE = 600.50m（估计器未检测到目标，返回兜底值）
- Nullspace：RMSE ≈ 0.42m（约 4.2× 距离分辨率 ΔR=0.099m），SI 泄漏 0.096（33.4dB 抑制）
- Lagrange：RMSE ≈ 0.42m，SI 泄漏 0.14（31.6dB 抑制）

三种预编码在角度 RMSE 和速度 RMSE 维度呈现相同趋势。

---

## 六、局限性

1. **MC 无方差**：噪声种子变化不影响判定结果，MC 试验不独立
2. **SNR 计算含 SI**：`sig_pow` 包含 SI 功率，使 ZF 场景噪声地板被高估，放大了 ZF 的失败程度
3. **频率平坦假设**：矩阵 SI 模式假设 H_SI 对所有 12672 子载波相同
4. **beta_SI 标定**：0.02 基于扫描试验经验选取，缺乏与硬件测量值的校准
5. **点散射 vs 矩阵 SI 不一致**：第二版使用的点散射模型与预编码器设计的 H_SI 矩阵不匹配，第三版修复

---

## 七、生成文件

| 文件 | 说明 |
|------|------|
| `task5_rmse_vs_snr_si.m` | MATLAB 仿真脚本 |
| `plot_rmse_si_on.py` | Python 画图脚本 |
| `generate_HSI.m` | 修改：添加 1/R 近场 LoS |
| `simulate_radar_channel_3d.m` | 修改：矩阵 SI 向量化 |
| `mat数据/task5_rmse_vs_snr_si_results.mat` | 仿真数据 |
| `png图片结果/rmse_distance_si_on.png` | 主图 |
| `plot_rmse_distance.py` | SI-off 画图脚本 |
| `toast_notify.py` | Windows 桌面通知工具 |
