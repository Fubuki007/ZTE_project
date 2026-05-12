"""MAFENN-DPD 复现的全局配置。

所有参数尽量对齐论文 4.1 / 4.2 / 4.3 节：

* 射频发射机：类 5G OFDM，主频 3.7 GHz，带宽 100 MHz，64-QAM
* 采样率 122.88 MHz，采样周期 8.138e-9 s
* PA 放大倍数 27.3842，使用记忆多项式建模
* 训练集 20000 / 验证集 10000 / 测试集 剩余（总数 61377）
* MAFENN：特征维 n=5，反馈循环 N=5，缓冲器长度 K=7
* 训练 200 epoch，LSTM 隐层大小为 2n=10，优化器 Adam
"""

from dataclasses import dataclass, field


# ---------------------------------------------------------------------------
# OFDM / 系统参数
# ---------------------------------------------------------------------------
@dataclass
class OFDMConfig:
    fc_hz: float = 3.7e9            # 载波频率
    bandwidth_hz: float = 100e6     # 信号带宽
    sample_rate_hz: float = 122.88e6  # 采样率
    scs_hz: float = 30e3            # 子载波间隔，NR numerology μ=1
    # 每个 OFDM 符号采样点数：fs / scs
    fft_size: int = 4096
    cp_len: int = 288               # 约 2.34 μs 的常规 CP
    # 有效子载波范围（近似 273 RB × 12 = 3276 子载波）
    num_subcarriers: int = 3276
    mod_order: int = 64             # 64-QAM
    num_symbols: int = 16           # 单次生成多少个 OFDM 符号
    seed: int = 2023                # 固定随机种子，便于对比


# ---------------------------------------------------------------------------
# 功放（PA）参数：记忆多项式 (Volterra 简化) 模型
# ---------------------------------------------------------------------------
@dataclass
class PAConfig:
    gain_linear: float = 27.3842    # 论文给定的放大倍数
    memory_depth: int = 4           # 记忆深度 M
    nonlinear_order: int = 5        # 非线性阶数 K
    # 记忆多项式系数随机种子（固定，确保不同方案针对同一 PA）
    coef_seed: int = 42


# ---------------------------------------------------------------------------
# 数据集划分：对齐论文 20000 / 10000 / 剩余
# ---------------------------------------------------------------------------
@dataclass
class DataConfig:
    total_samples: int = 61377
    train_samples: int = 20000
    val_samples: int = 10000
    # 测试样本数 = total - train - val
    normalize: bool = True          # 输入归一化（按训练集最大 |x|）


# ---------------------------------------------------------------------------
# MAFENN-DPD 网络超参数
# ---------------------------------------------------------------------------
@dataclass
class ModelConfig:
    feature_dim: int = 5            # 特征维度 n
    buffer_len: int = 7             # 缓冲器长度 K
    feedback_iters: int = 5         # 反馈循环次数 N
    lstm_hidden: int = 10           # 2 * feature_dim
    lstm_layers: int = 2            # 论文中 LSTM 两个子层
    fc_hidden: int = 32             # 全连接层维度
    # α：Player1 损失中 Player3 损失的权重
    alpha: float = 1.0


# ---------------------------------------------------------------------------
# 训练配置
# ---------------------------------------------------------------------------
@dataclass
class TrainConfig:
    epochs: int = 200
    batch_size: int = 256
    lr: float = 1e-3
    weight_decay: float = 0.0
    grad_clip: float = 1.0
    device: str = "auto"            # "cpu" / "cuda" / "auto"
    log_every: int = 1
    save_dir: str = "MAFENN_DPD/checkpoints"
    figure_dir: str = "MAFENN_DPD/figures"


@dataclass
class Config:
    ofdm: OFDMConfig = field(default_factory=OFDMConfig)
    pa: PAConfig = field(default_factory=PAConfig)
    data: DataConfig = field(default_factory=DataConfig)
    model: ModelConfig = field(default_factory=ModelConfig)
    train: TrainConfig = field(default_factory=TrainConfig)


DEFAULT_CONFIG = Config()
