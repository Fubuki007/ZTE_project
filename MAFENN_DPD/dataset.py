"""构建用于 MAFENN-DPD 训练的数据集。

流程：
1. 用 OFDM 信号生成器产生 x(i)（待预失真的理想信号）
2. 经 PA 得到 y(i) = PA(x(i))
3. 论文用"后逆"近似"前逆"：以 x(i) 作为输入、y(i)/gain 作为目标训练 PA
   的后逆网络，再在仿真时放到 PA 前作为预失真器
   —— 但更直接的做法是：DPD 的目标就是构造 x'(i)，使 PA(x'(i)) ≈ gain*x(i)
   这里的网络输入为 y(i)/gain，目标为 x(i)，学到的是 PA 的逆，
   推理时把待发送信号 x(i) 输入网络，得到 x'(i)，再喂给 PA。
4. 对齐论文的 20000 / 10000 / 剩余 划分比例。
"""

from __future__ import annotations

from dataclasses import dataclass

import numpy as np
import torch
from torch.utils.data import Dataset

from .config import Config
from .features import extract_features_np
from .pa_model import MemoryPolynomialPA
from .signal_gen import generate_ofdm_baseband


@dataclass
class RawData:
    """原始复数序列。"""

    x: np.ndarray  # 输入 DPD 网络的信号（PA 输出经理想增益归一化后的信号）
    y: np.ndarray  # DPD 目标信号（原始基带输入）


def build_raw_dataset(cfg: Config) -> RawData:
    """生成一次完整的 61377 样本长度的 (x, y) 序列。"""
    ofdm_samples = generate_ofdm_baseband(cfg.ofdm, num_samples=cfg.data.total_samples)
    pa = MemoryPolynomialPA(cfg.pa)
    pa_out = pa(ofdm_samples)

    # 网络的目标是学习 PA 的逆：
    # 输入 = PA 输出经理想线性增益归一化 (y/gain)
    # 期望输出 = 原始基带 x
    inv_gain = 1.0 / cfg.pa.gain_linear
    net_input = (pa_out * inv_gain).astype(np.complex64)
    net_target = ofdm_samples.astype(np.complex64)
    return RawData(x=net_input, y=net_target)


class SequenceDataset(Dataset):
    """按样本迭代的数据集，返回 (特征, 目标复数两路)。

    注意：MAFENN 网络需要缓冲器保持跨时刻的反馈状态，所以在训练脚本中我们
    仍然按时间顺序喂入小批量（truncated BPTT 风格）。这里的 Dataset 只负责
    产生 按 mini-batch 切片后的连续子序列。
    """

    def __init__(self, x_complex: np.ndarray, y_complex: np.ndarray, seq_len: int) -> None:
        assert x_complex.shape == y_complex.shape
        self.seq_len = seq_len
        self.feats = extract_features_np(x_complex)  # (L, 5)
        self.target_two = np.stack([y_complex.real, y_complex.imag], axis=-1).astype(np.float32)  # (L, 2)
        # 可采样起点：保证窗口不越界
        self.num_windows = max(1, (len(x_complex) - seq_len) // seq_len + 1)

    def __len__(self) -> int:
        return self.num_windows

    def __getitem__(self, idx: int):
        start = idx * self.seq_len
        end = start + self.seq_len
        if end > len(self.feats):
            # 最后一个窗口：向前对齐
            end = len(self.feats)
            start = end - self.seq_len
        feats = self.feats[start:end]          # (seq_len, 5)
        target = self.target_two[start:end]    # (seq_len, 2)
        return torch.from_numpy(feats), torch.from_numpy(target)


def split_raw(raw: RawData, cfg: Config) -> tuple[RawData, RawData, RawData]:
    """按论文比例切分训练 / 验证 / 测试。"""
    n_tr = cfg.data.train_samples
    n_va = cfg.data.val_samples
    train = RawData(x=raw.x[:n_tr], y=raw.y[:n_tr])
    val = RawData(x=raw.x[n_tr:n_tr + n_va], y=raw.y[n_tr:n_tr + n_va])
    test = RawData(x=raw.x[n_tr + n_va:], y=raw.y[n_tr + n_va:])
    return train, val, test
