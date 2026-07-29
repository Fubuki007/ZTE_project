# MIMO-OFDM ISAC 速度 RMSE 修复完整报告

> ZTE 项目 — 2026-06-28 诊断, 2026-06-29 验证  
> 文件: `joint_estimator_fast.m`, `build_default_params.m`

---

## 1. 摘要

MIMO-OFDM 通感一体化系统中，Nullspace/Lagrange 预编码在双目标场景下的速度 RMSE 从 **3.97 m/s 降至 0.20 m/s**（改善 20 倍），与单目标抛物线插值理论极限（~0.21 m/s）一致。根因为五层串扰，经四步剥洋葱式诊断定位，通过五处代码修改修复。

---

## 2. 问题现象

### 修复前（2026-06-28 早）

| 指标 | Nullspace | Lagrange |
|------|:---------:|:---------:|
| 距离 RMSE | 0.007 m ✅ | 0.007 m ✅ |
| 角度 RMSE | 0.03° ✅ | 0.01° ✅ |
| **速度 RMSE** | **3.97 m/s ❌** | **3.97 m/s ❌** |

诡异之处：距离和角度精度极高（远超 ΔR=0.099m），唯独速度差了近 20 倍。而且 3.97 m/s 几乎不随 SNR 变化——说明不是噪声问题，是系统性错误。

### 修复后（2026-06-29，MC=30，SI-ON）

| 指标 | Nullspace | Lagrange |
|------|:---------:|:---------:|
| 距离 RMSE | 0.006 m ✅ | 0.006 m ✅ |
| 角度 RMSE | 0.018° ✅ | 0.007° ✅ |
| **速度 RMSE** | **0.21 m/s ✅** | **0.20 m/s ✅** |

---

## 3. 诊断过程：四层剥洋葱

核心原则：**不要直接看最终 RMSE，要逐层剥离，从单目标→双目标→峰排名→守卫检查，直到定位到具体代码行。**

### 第一层：单目标 vs 双目标对比

运行 `diag_velocity_rootcause.m`：关闭一个目标，只留一个。

| 场景 | 目标速度真值 | 估计速度 | 误差 |
|------|:----------:|:-------:|:---:|
| 单目标 | 15.1 m/s | 15.26 m/s | **0.16 m/s** ✅ |
| 单目标 | -5.4 m/s | -5.67 m/s | **0.27 m/s** ✅ |
| 双目标 | -5.4 + 15.1 | ... | **3.87 m/s** ❌ |

**结论**：插值精度本身没问题（单目标 0.2 m/s = 0.09 bin），问题出在双目标场景下的**检测/匹配/混淆**。

### 第二层：RD 峰排名扫描

运行 `diag_v3.m`（200 候选峰）：

```
排名  距离      速度      功率
 #1   600.8m   +15.13    134.2 dB  ← 目标1 ✓
 #2     3.2m     0.00    132.7 dB  ← SI 假峰
 #3     6.7m     0.00    132.4 dB  ← SI 假峰
 #4   600.2m    -5.20    132.2 dB  ← 目标2，排第5！
 #5   600.7m    -2.34    130.1 dB
 ...
```

发现：目标 2 的峰排在第 5 位（功率仅比目标 1 低 2 dB），被多个 SI 假峰（R≈0, v≈0）挤到后面。

**结论**：需要距离门限过滤 SI 假峰，且需要更多候选名额（num_candidates 32→64）。

### 第三层：逐次修改验证

运行 `verify_fix.m`，每次加一个修复，打印匹配详情：

| 迭代 | 修改 | 目标1 速度 | 目标2 速度 | 问题 |
|:----:|------|:---------:|:---------:|------|
| v1 | +R_min_gate=20m | +15.13 | **未检测** | 目标2被漏检 |
| v2 | +ESPRIT 局部窗口 | +15.08 | -5.13 | 两个检测都在 R=600.8m |
| v3 | +MIMO 搜索窗缩小 | **0.064** | -5.13 | 目标1速度错误！ |

v3 的重大发现：目标 1 的速度变成了 **0.064 m/s**——这个数字恰好等于 `sin(25.83°) × sin(28.51°)`（方向余弦 v 分量）。

### 第四层：变量名冲突定位

在 MIMO 精化块插入 `[GUARD]` fprintf：

```matlab
[GUARD] ir=10639 ir_ref=10639 dev=0 | iv_raw=135 iv_ref=135 dev=0
```

**峰值位置完全正确（dev=0）**，但输出 v=0.064 m/s。说明问题不在峰值定位，而在**插值或输出阶段**。

搜索全部 `v_est` 出现位置，发现 `joint_estimator_fast.m` 第 250 行：

```matlab
v_est = sind(theta_val) * sind(phi_val);   % ← 这里！
```

这是方向余弦的 v 分量计算，但变量名是 `v_est`——与函数输出数组 `v_est`（1×Q 速度估计向量）**完全同名**。MATLAB 不报错，静默覆盖。

---

## 4. 五处代码修复

### 修复 1：变量名冲突（最致命）

**文件**: `joint_estimator_fast.m` 第 249-253 行

修复前：
```matlab
u_est = sind(theta_val) * cosd(phi_val);
v_est = sind(theta_val) * sind(phi_val);   % ← 输出数组被静默覆盖！
a_tx_x = exp(1j * kw_tx * (0:Ntx-1).' * u_est);
a_tx_y = exp(1j * kw_tx * (0:Nty-1).' * v_est);
```

修复后：
```matlab
u_dir = sind(theta_val) * cosd(phi_val);   % dir = direction cosine
v_dir = sind(theta_val) * sind(phi_val);
a_tx_x = exp(1j * kw_tx * (0:Ntx-1).' * u_dir);
a_tx_y = exp(1j * kw_tx * (0:Nty-1).' * v_dir);
```

**影响**：每次进入 MIMO 方向感知精化块时，速度输出被替换为方向余弦值（0.064~0.208），导致速度 RMSE 被人为压制到 0.2 m/s 级别——但这是**假数据**。真正的速度误差（3.97 m/s）被掩盖了。

### 修复 2：距离门限 R_min_gate

**文件**: `build_default_params.m` 第 95 行 + `joint_estimator_fast.m` 第 181-185 行

```matlab
% build_default_params.m
params.fast_estimator.R_min_gate = 20;  % 过滤 20m 以内的假峰

% joint_estimator_fast.m（NMS 循环内）
R_check = params.c * (Ns - nr) / (2 * Ns * delta_f);
if R_check < cfg.R_min_gate
    continue;  % 跳过 SI 残余假峰
end
```

**影响**：SI 自干扰在 R≈0 处产生高功率假峰，抢占检测名额。加门限后 SI 峰被排除，目标 2 的峰从第 5 名进入候选列表。

### 修复 3：ESPRIT 局部距离窗口

**文件**: `joint_estimator_fast.m` 第 188-193 行

修复前：ESPRIT 在全部 1250m 距离范围均匀采样 → 两目标回波在空间快拍中混合 → 参数混淆。

修复后：
```matlab
r_win = max(128, round(Ns / 40));        % ~317 bins ≈ 31m
n_start = max(1, ir - r_win);            % 以检测 bin 为中心
n_end   = min(Ns, ir + r_win);
esprit_n_idx = round(linspace(n_start, n_end, n_samp_r));
```

**影响**：ESPRIT 仅在目标周围 ±31m 范围内采样（n_samp_r=1024 高密度），两个目标的空间快照被隔离。

### 修复 4：MIMO 精化使用 P 替代 P_ref

**文件**: `joint_estimator_fast.m` 第 337-367 行

修复前：距离和速度精化插值使用 `P_ref`（方向感知加权的 RD 图）。

```matlab
% 修复前（第 340 行原为 P_ref(ir_ref-1, iv_ref) 等）
Pl_r = P_ref(ir_ref-1, iv_ref);
```

修复后：
```matlab
% 距离精化
Pl_r = P(ir_ref-1, iv_ref);   % 用原始 P，不是 P_ref
Pc_r = P(ir_ref, iv_ref);
Pr_r = P(ir_ref+1, iv_ref);

% 速度精化（同理）
Pl_v = P(ir_ref, iv_ref-1);
Pc_v = P(ir_ref, iv_ref);
Pr_v = P(ir_ref, iv_ref+1);
```

**影响**：P_ref 被方向感知加权（`tx_eff_ref`）扭曲了峰值对称性。虽然峰值整数 bin 位置正确，但 3 点抛物线插值需要局部对称性——非对称峰导致拟合偏差可达 1.7 bin（~4 m/s）。

### 修复 5：合理性守卫 + 参数调整

**文件**: `joint_estimator_fast.m` 第 331-335 行 + `build_default_params.m` 第 92 行

```matlab
% 守卫：MIMO 精化结果不能偏离粗检测太远
ir_dev = abs(ir_ref - ir);
iv_dev = abs(iv_ref - iv_raw);
if ir_dev > 5 || iv_dev > 3     % >0.5m 或 >7m/s → 拒绝
    % 回退到非 MIMO 标准路径
end
```

```matlab
% 参数调整
params.fast_estimator.num_candidates = 64;   % 32→64，捕获弱目标
params.fast_estimator.n_samp_r = 1024;       % ESPRIT 局部窗口高密度采样
```

---

## 5. 修复效果（实测数据对比）

### 速度 RMSE（m/s）

| SNR | 修复前 NS/LG | 修复后 NS | 修复后 LG | 改善 |
|-----|:-----------:|:---------:|:---------:|:----:|
| -30 dB | - | 0.41 | **0.24** | - |
| -20 dB | - | 0.21 | 0.21 | - |
| 0 dB | 3.97 | 0.21 | 0.20 | **19×** |
| +10 dB | 3.97 | 0.21 | 0.20 | **19×** |

### 距离 RMSE（m）

| SNR | 修复前 NS/LG | 修复后 NS/LG |
|-----|:-----------:|:-----------:|
| -30 dB | - | 0.005~0.009 |
| 0 dB | 0.007 | 0.006 |
| +10 dB | 0.007 | 0.006 |

距离和角度 RMSE 修复前后均保持优秀（< 0.1×ΔR），说明速度问题是孤立的。

### Lagrange 略优于 Nullspace

在 -30 dB 极低 SNR 下，Lagrange 的速度 RMSE（0.24 m/s）好于 Nullspace（0.41 m/s），角度 RMSE（0.29° vs 3.1°）也是。这印证了 Lagrange 在极端 SNR 下的鲁棒性优势——其正则化框架对噪声有更好的数值稳定性。

---

## 6. 关键教训

### 6.1 MATLAB 变量名冲突：最隐蔽的 Bug

> MATLAB 不报错、不警告、运行时一切正常。症状是"数据在中间步骤正确，返回给调用者时错误"。

**防备方法**：
1. 方向余弦变量统一命名为 `u_dir` / `v_dir`（dir = direction cosine），永不使用 `v_est`
2. 任何与输出数组同名的局部变量都是 bug
3. 调试时在函数截断阶段（`v_est = v_est(1:detected)` 前）fprintf 输出
4. 代码审查时搜索输出变量名在函数体内的所有出现，排查非输出赋值

### 6.2 插值方法选择：域匹配是关键

| 插值方法 | 适用域 | 功率谱上表现 |
|---------|--------|:-----------:|
| Parabolic | 功率谱 `|X|²` | **最优（0.09 bin）** |
| Jacobsen | 复数 DFT `X` | 差 10×（0.95 bin） |
| Candan | 复数 DFT `X` | 差 7.8×（0.70 bin） |

**教训**：Jacobsen/Candan 是为复数 DFT 系数设计的，用在功率谱上会严重退化。**切忌盲目换插值方法**——先确认信号域。

### 6.3 诊断方法论：逐层剥离

不要直接跑完整 RMSE 看结果——那样你只能得到"有问题"而找不到"哪里有问题"。

正确顺序：
1. **单目标** → 排除插值精度问题
2. **峰排名** → 确认检测阶段
3. **逐次修改 + fprintf** → 定位到具体代码行
4. **变量搜索** → 发现命名冲突

### 6.4 MC 次数与 rng 种子

- `rng('shuffle')` 在 `-batch` 模式下失效（同秒种子碰撞）→ 所有 MC 迭代噪声完全相同
- 修复：`rng(sum(100*clock) + mc_i*1000 + snr_i*100 + prec_i)` 显式绑定迭代索引
- MC=3 时一个坏迭代就能拖高中位数；MC=30 才能得到可靠的统计量

### 6.5 速度 RMSE 的 SI 独立性

NS/LG 的速度 RMSE 在 SI-ON 和 SI-OFF 下完全一致（~0.20 m/s）。原因是：
- SI 在 RD 平面上位于 (R=0, v=0)，真实目标在 (R≈600m, v≠0)
- R_min_gate=20m 过滤后 SI 在检测阶段就被排除
- 多普勒估计用的是跨 256 符号的相位差，SI（直达路径）相位变化为 0

**含义**：只要预编码器将 SI 压制到"能正确检测目标"的程度（距离 RMSE 从 ZF 的 140m 降到 0.006m），速度估计就和无 SI 一样好。SI 影响的是"找不找得到"，不是"找到后测得准不准"。

---

## 7. 附录：插值基准测试

`test_interp.m` — N=256, true_bin=6.446, MC=1000, SNR≈20 dB（FFT gain 后）

| 方法 | RMSE (bin) | RMSE (m/s) | 备注 |
|------|:---------:|:---------:|------|
| 抛物线（当前） | **0.09** | **0.21** | 功率谱上最优 |
| Jacobsen | 0.95 | 2.23 | 复数域方法，勿用于功率谱 |
| Candan | 0.70 | 1.64 | 同上 |
| 仅量化（不插值） | 0.45 | 1.05 | 基准 |

---

## 8. 修复文件清单

| 文件 | 修改内容 | 行号 |
|------|---------|:----:|
| `joint_estimator_fast.m` | v_est→v_dir 变量重命名 | 249-253 |
| `joint_estimator_fast.m` | R_min_gate 距离门限检查 | 181-185 |
| `joint_estimator_fast.m` | ESPRIT 局部距离窗口 | 188-193 |
| `joint_estimator_fast.m` | MIMO 搜索窗缩小（Ns/160） | 317 |
| `joint_estimator_fast.m` | MIMO 插值用 P 替代 P_ref | 340-369 |
| `joint_estimator_fast.m` | 合理性守卫 ir_dev/iv_dev | 331-335 |
| `build_default_params.m` | R_min_gate=20, num_candidates=64 | 92-95 |

---

*报告生成: 2026-06-29 | 数据来源: task5_rmse_vs_snr_si.m, MC=30, SNR=-30:5:10, K=256, SI-ON, beta=0.02*
