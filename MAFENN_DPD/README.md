# MAFENN-DPD 复现

本目录复现论文《使用多智能体反馈神经网络实现的数字预失真器》
(杨旸, 刘畅, 李凯, 等. 信号处理, 2023, 39(3): 450-458)
中提出的 **Multi-Agent Feedback Enabled Neural Network for Digital
Predistortion (MAFENN-DPD)**。

## 目录结构

```
MAFENN_DPD/
├── README.md                本说明文件
├── requirements.txt         依赖清单
├── config.py                全局参数（OFDM / PA / 训练超参数）
├── signal_gen.py            类 5G OFDM 信号生成（64-QAM, 100 MHz, 122.88 MHz 采样）
├── pa_model.py              记忆多项式功率放大器模型
├── features.py              输入特征构造：[Re, Im, |x|, |x|^2, |x|^3]
├── dataset.py               数据集 / 滑窗 / 训练-验证-测试划分
├── model_mafenn.py          MAFENN-DPD 三智能体网络（编码器 / 反馈器 / 处理器）
├── model_feedforward.py     典型前馈网络基线（MAFENN 令 N=0 的退化情形）
├── mp_dpd.py                传统记忆多项式 DPD 基线
├── metrics.py               NMSE / ACPR / PSD 计算
├── train.py                 Stackelberg 式联合训练主脚本
├── evaluate.py              三种方案对比：未预失真 / 前馈网络 / MAFENN / 记忆多项式
└── figures/                 生成的结果图（训练曲线、PSD 对比等）
```

## 快速开始

```bash
# 1. 安装依赖
pip install -r requirements.txt

# 2. 训练 MAFENN-DPD（默认 N=5, K=7, epoch=200）
python -m MAFENN_DPD.train --model mafenn --epochs 200

# 3. 训练前馈网络基线（N=0）
python -m MAFENN_DPD.train --model ff --epochs 200

# 4. 对比评估（PSD / ACPR / NMSE）
python -m MAFENN_DPD.evaluate
```

## 论文关键对应

| 论文描述 | 代码实现 |
| --- | --- |
| 输入特征 `[Re{x}, Im{x}, |x|, |x|^2, |x|^3]` | `features.py::extract_features` |
| 反馈缓冲器 `X_rec(i) = [x_rec(i), ..., x_rec(i-K)]` | `model_mafenn.py::MAFENN.forward` |
| 编码器 (LSTM + FC + ReLU) | `model_mafenn.py::Encoder` |
| 反馈器 (输出 5 维特征向量) | `model_mafenn.py::Feedbacker` |
| 处理器 (输出复数 [Re, Im]) | `model_mafenn.py::Processor` |
| 反馈循环 N 次 | `model_mafenn.py::MAFENN.forward` 中 `for _ in range(N)` |
| Player2 损失 (L1 + L2, 在特征域) | `train.py::loss_player2` |
| Player3 损失 (L1 + L2, 在复数域) | `train.py::loss_player3` |
| Player1 损失 `l1 = l2 + α l3`, α=1 | `train.py::loss_player1` |
| 多次反馈循环损失累积 | `train.py::train_one_step` |
| NMSE (式 6) | `metrics.py::nmse_db` |
| ACPR | `metrics.py::acpr_db` |

## 说明

- 由于原文使用 MATLAB + Simulink 采集 PA 真实数据，本复现改用 Python 侧
  的记忆多项式 PA 模型生成训练 / 测试数据，系数参考 Morgan 等人广义记忆
  多项式 (GMP) 的典型设置，并校准放大倍数为论文给定的 27.3842。
- 仅用于学术复现与教学演示，不代表论文作者原始实现。
