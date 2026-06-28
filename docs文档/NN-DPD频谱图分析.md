# NN-DPD 频谱图分析

## 概述

本文档分析 `NeuralNetworkDigitalPredistortionOfflineTrainingExample.mlx` 中 **Test NN-DPD** 部分生成的频谱图，说明其输入数据来源和信号处理流程。

---

## 频谱图的生成

### 调用位置

`helperPACharPlotSpectrum.m`，内部使用 MATLAB 的 `spectrumAnalyzer` 对象。

### 函数签名

```matlab
function sa = helperPACharPlotSpectrum(x, desc, sampleRate, testSignal, varargin)
```

| 参数 | 含义 |
|------|------|
| `x` | 多列时域信号矩阵 |
| `desc` | 各列信号名称（图例） |
| `sampleRate` | 采样率 |
| `testSignal` | `"Tones"` 或 `"Modulated"` |
| `varargin` | Y 轴范围 |

### 实际调用

```matlab
sa = helperPACharPlotSpectrum([paOutputTest paOutputMP paOutputNN], ...
       {'No DPD','Memory Polynomial DPD','Neural Network DPD'}, ...
       ofdmParams.OversamplingFactor, "Modulated", [-130 -50]);
```

## 信号流程图

```
                        随机整数 [0~15]
                             │
                      qammod(·, 16)           ← 16-QAM 调制
                             │
                       QAM 复数符号
                             │
                      ofdmmod(·)              ← OFDM 调制 + 过采样
                             │
                       txWaveTest             ← "同一 OFDM 信号"
                  __________|__________
                 |         |           |
            (No DPD)  (MP-DPD)    (NN-DPD)
                 |         |           |
            pa(x)    MP_DPD(x)    NN_DPD(x)
                 |      pa(y)        pa(z)
                 |         |           |
            paOutputTest paOutputMP paOutputNN
                 |_________|___________|
                           |
                  spectrumAnalyzer
                           |
                      功率谱对比图
```

---

## 输入数据：`txWaveTest`

### 生成函数

`helperNNDPDGenerateOFDM(ofdmParams, symPerFrame, M)`

### 生成步骤

1. **随机数据生成**
   ```matlab
   x = randi([0 M-1], numDataCarriers, spf);
   ```
   - `M = 16`：每个子载波携带 16-QAM 符号（4 bit/符号）
   - `spf = 6`：每帧 6 个 OFDM 符号
   - 生成 `numDataCarriers × 6` 个 0~15 的随机整数

2. **16-QAM 调制**
   ```matlab
   qamRefSym = qammod(x, M);
   ```
   - 将整数映射为 16-QAM 星座点（复数）

3. **OFDM 调制**
   ```matlab
   txWaveform = ofdmmod(qamRefSym/osf, fftLength, cpLength, nullIdx, ...
       OversamplingFactor=osf);
   ```
   - 添加 guard band（空子载波）
   - 添加循环前缀（CP）
   - 过采样因子 `osf = 5`

### OFDM 参数

| 参数 | 值 |
|------|-----|
| 带宽 | 100 MHz |
| 调制方式 | 16-QAM |
| 每帧符号数 | 6 |
| 过采样因子 | 5 |

---

## 三条路径的 PA 输出

### 路径 1：No DPD

```matlab
paOutputTest = pa(txWaveTest);
```

原始 OFDM 信号**直接通过 PA**，受到非线性失真：

```
txWaveTest → [PA 神经网络模型] → paOutputTest
```

### 路径 2：Memory Polynomial DPD

```matlab
dpdOutMP  = helperNNDPDMemoryPolynomial(txWaveTest, txWaveTrain, paOutputTrain, 5, 5);
paOutputMP = pa(dpdOutMP);
```

先用**记忆多项式**对信号做预失真，再通过 PA：

```
txWaveTest → [MP 预失真器] → dpdOutMP → [PA 模型] → paOutputMP
```

### 路径 3：Neural Network DPD

```matlab
dpdOutNN  = predict(netDPD, inputMtxTest);
paOutputNN = pa(complex(dpdOutNN(:,1), dpdOutNN(:,2)) / scalingFactor);
```

先用**离线训练的神经网络**对信号做预失真，再通过 PA：

```
txWaveTest → [NN 预失真器 (trained netDPD)] → dpdOutNN → [PA 模型] → paOutputNN
```

---

## PA 模型

`helperNNDPDPowerAmplifier`，使用 `"Simulated PA"` 模式：

```matlab
load paModelNN.mat netPA memDepthPA nonlinearDegreePA scalingFactorPA
X = inputProcessor(in * scalingFactor);
Y = predict(netPA, X);
out = complex(Y(:,1), Y(:,2)) / scalingFactor;
```

- **PA 模型本身也是一个神经网络**（`netPA`），用实测 PA 数据训练
- 包含记忆效应（`memDepthPA`）和非线性（`nonlinearDegreePA`）

---

## 频谱图解读

| 曲线 | 含义 | 预期表现 |
|------|------|---------|
| **No DPD** | 未经预失真，直接过 PA | 邻道功率泄露严重（频谱展宽） |
| **MP-DPD** | 记忆多项式预失真后过 PA | 邻道功率明显降低 |
| **NN-DPD** | 神经网络预失真后过 PA | 邻道功率最低，最接近线性放大 |

### 评估指标

- **ACPR**（邻道功率比）：衡量带外频谱再生
- **NMSE**（归一化均方误差）：衡量波形失真
- **EVM**（误差矢量幅度）：衡量调制精度

---

## 相关文件

| 文件 | 作用 |
|------|------|
| `NeuralNetworkDigitalPredistortionOfflineTrainingExample.mlx` | 主示例脚本 |
| `helperPACharPlotSpectrum.m` | 频谱绘图函数 |
| `helperNNDPDGenerateOFDM.m` | OFDM 信号生成 |
| `helperNNDPDPowerAmplifier.m` | PA 模型（含 NN PA） |
| `helperNNDPDMemoryPolynomial.m` | 记忆多项式 DPD |
| `paModelNN.mat` | 预训练的 PA 神经网络模型 |
