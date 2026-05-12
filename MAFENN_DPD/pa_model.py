"""功率放大器（PA）记忆多项式模型。

对应论文 4.1 节："功率放大器模块采用一个双端口的 PA 模型，使用一个从
Volterra 方程简化得来的记忆多项式对输入和输出信号之间的非线性关系进行
建模，放大倍数为 27.3842。"

记忆多项式（Morgan et al. 2006）：
    y(n) = sum_{k=0}^{K-1} sum_{m=0}^{M-1} a_{k,m} * x(n-m) * |x(n-m)|^k

本文件提供：
1. 随机但可复现的 PA 系数（固定种子），可确保不同 DPD 方案使用同一 PA
2. 放大倍数校准，使小信号线性增益等于 cfg.gain_linear
"""

from __future__ import annotations

import numpy as np

from .config import PAConfig


class MemoryPolynomialPA:
    """记忆多项式 PA。"""

    def __init__(self, cfg: PAConfig) -> None:
        self.cfg = cfg
        self.K = cfg.nonlinear_order
        self.M = cfg.memory_depth
        self._init_coefficients()

    # ------------------------------------------------------------------
    # 系数初始化
    # ------------------------------------------------------------------
    def _init_coefficients(self) -> None:
        """初始化一个"典型"的弱非线性 + 轻度记忆效应 PA。

        设计原则：
        * a_{0,0} 设为 1（稍后整体乘以 gain 得到放大倍数）
        * 高阶项（k 增大）系数衰减，保证大信号时才出现明显压缩
        * 记忆项（m 增大）系数衰减，模拟真实 PA 的记忆效应长度
        """
        rng = np.random.default_rng(self.cfg.coef_seed)
        K, M = self.K, self.M
        coef = np.zeros((K, M), dtype=np.complex64)

        # 基本响应：k=0, m=0 为主
        coef[0, 0] = 1.0 + 0j

        # 低阶记忆项，幅度 ~0.05 逐步衰减
        for m in range(1, M):
            coef[0, m] = (rng.normal(0.0, 0.05) + 1j * rng.normal(0.0, 0.05)) * (0.8 ** m)

        # 非线性项（主要 3 阶、5 阶），模拟压缩特性 → 负的实部为主
        if K > 2:
            coef[2, 0] = -0.25 + 0.03j
            for m in range(1, M):
                coef[2, m] = (rng.normal(-0.05, 0.03) + 1j * rng.normal(0.0, 0.02)) * (0.6 ** m)
        if K > 4:
            coef[4, 0] = 0.08 - 0.02j
            for m in range(1, M):
                coef[4, m] = (rng.normal(0.02, 0.02) + 1j * rng.normal(0.0, 0.01)) * (0.5 ** m)

        # 偶数阶（k=1,3,...）对通带信号影响较弱，这里也给一点小值
        for k in range(1, K, 2):
            for m in range(M):
                coef[k, m] = (rng.normal(0.0, 0.02) + 1j * rng.normal(0.0, 0.02)) * (0.5 ** (k + m))

        # 放大倍数：让小信号近似有 gain_linear 的线性增益
        coef = coef * self.cfg.gain_linear
        self.coef = coef

    # ------------------------------------------------------------------
    # 前向传递
    # ------------------------------------------------------------------
    def __call__(self, x: np.ndarray) -> np.ndarray:
        """输入复数时间序列 x，输出经 PA 的复数时间序列 y（与 x 等长）。"""
        x = np.asarray(x, dtype=np.complex64)
        y = np.zeros_like(x)
        abs_x = np.abs(x)
        for m in range(self.M):
            if m == 0:
                xm = x
                abs_xm = abs_x
            else:
                xm = np.concatenate([np.zeros(m, dtype=x.dtype), x[:-m]])
                abs_xm = np.concatenate([np.zeros(m), abs_x[:-m]])
            # 对各阶非线性累加
            term = np.zeros_like(x)
            for k in range(self.K):
                term += self.coef[k, m] * xm * (abs_xm ** k)
            y += term
        return y.astype(np.complex64)


if __name__ == "__main__":
    from .signal_gen import generate_ofdm_baseband
    from .config import OFDMConfig

    pa = MemoryPolynomialPA(PAConfig())
    x = generate_ofdm_baseband(OFDMConfig(), num_samples=4096)
    y = pa(x)
    print("输入 RMS:", np.sqrt(np.mean(np.abs(x) ** 2)))
    print("输出 RMS:", np.sqrt(np.mean(np.abs(y) ** 2)))
    print("实际平均增益:", np.mean(np.abs(y) / np.maximum(np.abs(x), 1e-12)))
