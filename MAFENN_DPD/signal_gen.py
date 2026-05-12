"""类 5G OFDM 信号生成。

参照论文 4.1 节仿真系统设置：
  主频 3.7 GHz，带宽 100 MHz，64-QAM，采样率 122.88 MHz。
这里只在基带生成复基带 I/Q 样本，不做载波上变频。
"""

from __future__ import annotations

import numpy as np

from .config import OFDMConfig


def _qam_constellation(mod_order: int) -> np.ndarray:
    """生成方形 QAM 星座（功率归一化）。"""
    m = int(np.sqrt(mod_order))
    if m * m != mod_order:
        raise ValueError("仅支持方形 QAM")
    levels = 2 * np.arange(m) - (m - 1)
    re, im = np.meshgrid(levels, levels)
    constellation = (re + 1j * im).astype(np.complex64).ravel()
    constellation /= np.sqrt((np.abs(constellation) ** 2).mean())
    return constellation


def generate_ofdm_baseband(
    cfg: OFDMConfig,
    num_samples: int,
    rng: np.random.Generator | None = None,
) -> np.ndarray:
    """生成基带 OFDM 复数样本序列，长度 `num_samples`。

    步骤：
    1. 随机生成 64-QAM 符号，填充到 `num_subcarriers` 个有效子载波上
    2. IFFT + 添加 CP，得到时域 OFDM 符号
    3. 逐符号串联，截取前 `num_samples` 个样本
    4. 输出单位能量归一化的复数序列
    """
    if rng is None:
        rng = np.random.default_rng(cfg.seed)

    const = _qam_constellation(cfg.mod_order)
    symbol_len = cfg.fft_size + cfg.cp_len
    # 多生成几个符号，确保长度足够
    num_symbols = int(np.ceil(num_samples / symbol_len)) + 1

    # 有效子载波在 FFT bin 中的位置（居中放置，跳过 DC）
    half = cfg.num_subcarriers // 2
    bins = np.concatenate([
        np.arange(cfg.fft_size - half, cfg.fft_size),  # 负频率
        np.arange(1, half + 1),                        # 正频率（跳过 DC）
    ])

    signal = np.empty(num_symbols * symbol_len, dtype=np.complex64)
    for sym_idx in range(num_symbols):
        freq = np.zeros(cfg.fft_size, dtype=np.complex64)
        bits = rng.integers(0, cfg.mod_order, size=cfg.num_subcarriers)
        freq[bins] = const[bits]
        # 使用 ifft 并乘以 sqrt(N) 使时域信号保持单位平均功率
        time = np.fft.ifft(freq) * np.sqrt(cfg.fft_size)
        # 加循环前缀
        with_cp = np.concatenate([time[-cfg.cp_len:], time])
        signal[sym_idx * symbol_len:(sym_idx + 1) * symbol_len] = with_cp

    out = signal[:num_samples].astype(np.complex64)
    # 归一化到 RMS=1，便于后续 PA 模型工作在典型动态范围
    rms = np.sqrt(np.mean(np.abs(out) ** 2))
    if rms > 0:
        out = out / rms
    return out


if __name__ == "__main__":
    cfg = OFDMConfig()
    x = generate_ofdm_baseband(cfg, num_samples=61377)
    print("OFDM 基带样本数:", x.shape[0])
    print("RMS:", np.sqrt(np.mean(np.abs(x) ** 2)))
    print("PAPR (dB):", 10 * np.log10(np.max(np.abs(x) ** 2) / np.mean(np.abs(x) ** 2)))
