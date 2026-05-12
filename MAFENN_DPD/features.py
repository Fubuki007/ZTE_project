"""输入特征构造。

对应论文式 (1)：
    x_vec(i) = [ Re{x(i)}, Im{x(i)}, |x(i)|, |x(i)|^2, |x(i)|^3 ]

除了把复数拆成实虚两路（避免复数权重），还引入振幅的高阶项，方便神经网络
直接拟合高阶互调项。
"""

from __future__ import annotations

import numpy as np
import torch


def extract_features_np(x: np.ndarray) -> np.ndarray:
    """numpy 版本。输入形状 (L,) 复数，输出形状 (L, 5) 实数。"""
    x = np.asarray(x)
    abs_x = np.abs(x)
    feats = np.stack([
        x.real,
        x.imag,
        abs_x,
        abs_x ** 2,
        abs_x ** 3,
    ], axis=-1).astype(np.float32)
    return feats


def extract_features_torch(x_complex: torch.Tensor) -> torch.Tensor:
    """torch 版本。输入形状 (..., L) 复数，输出形状 (..., L, 5) 实数。

    这里直接接受实/虚两路的拼接张量以避免 complex 算子兼容性问题：
    输入 shape=(..., L, 2)，最后一维 0:real, 1:imag。
    """
    if torch.is_complex(x_complex):
        re = x_complex.real
        im = x_complex.imag
    else:
        assert x_complex.shape[-1] == 2, "应为 (..., L, 2) 实/虚两路"
        re = x_complex[..., 0]
        im = x_complex[..., 1]
    abs_x = torch.sqrt(re * re + im * im + 1e-12)
    feats = torch.stack([re, im, abs_x, abs_x ** 2, abs_x ** 3], dim=-1)
    return feats


def complex_from_two_channel(xy: torch.Tensor) -> torch.Tensor:
    """将 (..., 2) 实/虚两路转成 complex。"""
    return torch.complex(xy[..., 0], xy[..., 1])
