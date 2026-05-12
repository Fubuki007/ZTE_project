"""传统记忆多项式 DPD 基线。

参考 Morgan et al. 2006 与论文 4.1 节所述的记忆多项式建模。训练阶段用最
小二乘闭式解拟合 PA 的后逆，随后当作预失真器前置到 PA 之前即可。
"""

from __future__ import annotations

import numpy as np


class MemoryPolynomialDPD:
    """记忆多项式 DPD：用 LS 拟合 PA 后逆。"""

    def __init__(self, nonlinear_order: int = 5, memory_depth: int = 4) -> None:
        self.K = nonlinear_order
        self.M = memory_depth
        self.coef: np.ndarray | None = None

    # ------------------------------------------------------------------
    # 构造基函数矩阵 Φ：列为 x(n-m) * |x(n-m)|^k
    # ------------------------------------------------------------------
    def _phi(self, x: np.ndarray) -> np.ndarray:
        x = np.asarray(x, dtype=np.complex128)
        N = len(x)
        cols = []
        abs_x = np.abs(x)
        for m in range(self.M):
            if m == 0:
                xm = x
                abs_xm = abs_x
            else:
                xm = np.concatenate([np.zeros(m, dtype=x.dtype), x[:-m]])
                abs_xm = np.concatenate([np.zeros(m), abs_x[:-m]])
            for k in range(self.K):
                cols.append(xm * (abs_xm ** k))
        return np.stack(cols, axis=-1)  # (N, K*M)

    # ------------------------------------------------------------------
    # 训练 / 应用
    # ------------------------------------------------------------------
    def fit(self, pa_in: np.ndarray, pa_out_over_gain: np.ndarray) -> None:
        """用 PA 的 (输入, 归一化输出) 数据拟合后逆：输入 pa_out_over_gain，
        目标 pa_in。
        """
        phi = self._phi(pa_out_over_gain)
        # LS: argmin || phi @ coef - pa_in ||
        self.coef, *_ = np.linalg.lstsq(phi, pa_in.astype(np.complex128), rcond=None)

    def apply(self, x: np.ndarray) -> np.ndarray:
        """对待发送信号 x 进行预失真，得到 x'。"""
        if self.coef is None:
            raise RuntimeError("请先调用 fit")
        phi = self._phi(x)
        return (phi @ self.coef).astype(np.complex64)
