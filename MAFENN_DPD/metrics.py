"""NMSE / ACPR / PSD 指标计算。"""

from __future__ import annotations

import numpy as np
from scipy.signal import welch


def nmse_db(y_true: np.ndarray, y_pred: np.ndarray) -> float:
    """对应论文式 (6) 的 NMSE（单位：dB）。

    NMSE = 10 log10( sum |y_true - y_pred|^2 / sum |y_true|^2 )
    """
    err = y_true - y_pred
    num = float(np.mean(np.abs(err) ** 2))
    den = float(np.mean(np.abs(y_true) ** 2))
    if den <= 0:
        return float("-inf")
    return 10.0 * np.log10(num / den + 1e-20)


def compute_psd(
    x: np.ndarray, fs: float, nfft: int = 4096,
) -> tuple[np.ndarray, np.ndarray]:
    """计算双边功率谱密度（dB / Hz）。"""
    freqs, psd = welch(
        x, fs=fs, nperseg=nfft, nfft=nfft, return_onesided=False, scaling="density"
    )
    # fftshift 使零频居中
    idx = np.argsort(freqs)
    freqs = freqs[idx]
    psd = psd[idx]
    return freqs, 10 * np.log10(psd + 1e-20)


def acpr_db(
    x: np.ndarray,
    fs: float,
    main_bw: float,
    adj_offset: float,
    adj_bw: float | None = None,
    nfft: int = 4096,
) -> tuple[float, float]:
    """计算相邻信道功率比（dBc）。

    ACPR_lower = 10 log10(P_lower_adj / P_main)
    ACPR_upper = 10 log10(P_upper_adj / P_main)
    """
    if adj_bw is None:
        adj_bw = main_bw
    freqs, psd_db = compute_psd(x, fs=fs, nfft=nfft)
    psd_lin = 10 ** (psd_db / 10)

    def band_power(fl: float, fh: float) -> float:
        mask = (freqs >= fl) & (freqs <= fh)
        if not mask.any():
            return 0.0
        df = freqs[1] - freqs[0]
        return float(np.sum(psd_lin[mask]) * df)

    p_main = band_power(-main_bw / 2, main_bw / 2)
    p_lower = band_power(-adj_offset - adj_bw / 2, -adj_offset + adj_bw / 2)
    p_upper = band_power(adj_offset - adj_bw / 2, adj_offset + adj_bw / 2)
    eps = 1e-20
    return (
        10 * np.log10((p_lower + eps) / (p_main + eps)),
        10 * np.log10((p_upper + eps) / (p_main + eps)),
    )
