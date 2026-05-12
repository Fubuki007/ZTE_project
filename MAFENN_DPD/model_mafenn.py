"""MAFENN-DPD 网络实现。

对应论文图 2 与算法 1：

* Encoder (Player 1)：输入当前特征 x_vec(i) 和反馈缓冲器 X_rec(i)
  → LSTM(2 子层) + Linear + ReLU → 输出隐变量 z(i)
* Feedbacker (Player 2)：输入 z(i) → 输出 x_rec(i)（5 维特征向量）
* Processor (Player 3)：接收经 N 次反馈后的 z(i) → 输出 [Re, Im]

反馈循环 N 次后，把 x_rec(i) 写入缓冲器，继续处理下一时刻 i+1。
"""

from __future__ import annotations

from dataclasses import dataclass

import torch
import torch.nn as nn

from .config import ModelConfig


class Encoder(nn.Module):
    """编码器：LSTM + Linear + ReLU。"""

    def __init__(self, cfg: ModelConfig) -> None:
        super().__init__()
        # 输入 = 当前特征 + 缓冲器 (K+1) 个历史反馈向量
        in_dim = cfg.feature_dim * (cfg.buffer_len + 2)  # 当前 + (K+1) 个反馈
        self.in_dim = in_dim
        self.lstm = nn.LSTM(
            input_size=in_dim,
            hidden_size=cfg.lstm_hidden,
            num_layers=cfg.lstm_layers,
            batch_first=True,
        )
        self.fc = nn.Linear(cfg.lstm_hidden, cfg.fc_hidden)
        self.act = nn.ReLU()

    def forward(
        self,
        x_cat: torch.Tensor,
        hx: tuple[torch.Tensor, torch.Tensor] | None = None,
    ) -> tuple[torch.Tensor, tuple[torch.Tensor, torch.Tensor]]:
        """输入 x_cat: (B, T, in_dim)，输出隐变量 z: (B, T, fc_hidden)。"""
        out, hx = self.lstm(x_cat, hx)
        z = self.act(self.fc(out))
        return z, hx


class Feedbacker(nn.Module):
    """反馈器：从 z(i) 解码出 5 维特征（作为下一次反馈输入）。"""

    def __init__(self, cfg: ModelConfig) -> None:
        super().__init__()
        self.net = nn.Sequential(
            nn.Linear(cfg.fc_hidden, cfg.fc_hidden),
            nn.ReLU(),
            nn.Linear(cfg.fc_hidden, cfg.feature_dim),
        )

    def forward(self, z: torch.Tensor) -> torch.Tensor:
        return self.net(z)


class Processor(nn.Module):
    """处理器：从 z(i) 输出最终复数 [Re, Im]。"""

    def __init__(self, cfg: ModelConfig) -> None:
        super().__init__()
        self.net = nn.Sequential(
            nn.Linear(cfg.fc_hidden, cfg.fc_hidden),
            nn.ReLU(),
            nn.Linear(cfg.fc_hidden, 2),
        )

    def forward(self, z: torch.Tensor) -> torch.Tensor:
        return self.net(z)


@dataclass
class MAFENNState:
    """MAFENN 的持续状态，便于在多个 batch / 窗口间保持。"""

    buffer: torch.Tensor          # (B, K+1, feature_dim)
    lstm_hx: tuple[torch.Tensor, torch.Tensor] | None = None


class MAFENN(nn.Module):
    """组装编码器 / 反馈器 / 处理器，并实现 N 次反馈循环。"""

    def __init__(self, cfg: ModelConfig) -> None:
        super().__init__()
        self.cfg = cfg
        self.encoder = Encoder(cfg)
        self.feedbacker = Feedbacker(cfg)
        self.processor = Processor(cfg)

    def init_state(self, batch_size: int, device: torch.device) -> MAFENNState:
        buf = torch.zeros(
            batch_size,
            self.cfg.buffer_len + 1,
            self.cfg.feature_dim,
            device=device,
        )
        return MAFENNState(buffer=buf, lstm_hx=None)

    def forward(
        self,
        feats: torch.Tensor,
        state: MAFENNState,
        feedback_iters: int | None = None,
    ) -> tuple[torch.Tensor, torch.Tensor, MAFENNState]:
        """前向传递。

        参数：
            feats: (B, T, feature_dim) 当前时刻的输入特征序列
            state: MAFENN 的持续状态
            feedback_iters: 反馈循环次数 N，默认取 cfg.feedback_iters

        返回：
            y_out: (B, T, 2) 处理器输出的复数 [Re, Im]
            x_rec_last: (B, T, feature_dim) 反馈器最后一次输出，供特征域 loss
            new_state: 更新后的状态
        """
        N = self.cfg.feedback_iters if feedback_iters is None else feedback_iters
        B, T, _ = feats.shape
        K = self.cfg.buffer_len

        # 预分配输出
        y_outs = torch.empty(B, T, 2, device=feats.device)
        x_rec_outs = torch.empty(B, T, self.cfg.feature_dim, device=feats.device)

        buffer = state.buffer
        lstm_hx = state.lstm_hx

        # 为避免反复重建 LSTM 的序列输入结构，按时间步逐个处理
        for t in range(T):
            cur = feats[:, t, :]                        # (B, F)
            inner_buffer = buffer.clone()
            z = None
            x_rec = None
            # N 次反馈：只调用 encoder 的 LSTM-cell 部分，不推进外层时间状态。
            # 这里通过在循环内传入同一 lstm_hx，循环结束后再用 final 输入让 lstm_hx 推进一次。
            for it in range(N + 1):
                buf_flat_i = inner_buffer.reshape(B, -1)
                x_cat_i = torch.cat([cur, buf_flat_i], dim=-1).unsqueeze(1)
                # 反馈内部循环不更新外层 lstm_hx，只取输出
                z_seq, _tmp_hx = self.encoder(x_cat_i, lstm_hx)
                z = z_seq[:, -1, :]
                x_rec = self.feedbacker(z)
                inner_buffer = torch.cat([
                    inner_buffer[:, 1:, :],
                    x_rec.unsqueeze(1),
                ], dim=1)
                # 最后一次：把 LSTM 状态推进到下一时刻
                if it == N:
                    lstm_hx = _tmp_hx

            # 处理器输出当前时刻复数
            y_out = self.processor(z)                               # (B, 2)
            y_outs[:, t, :] = y_out
            x_rec_outs[:, t, :] = x_rec

            # 把最后一次反馈结果写入外部缓冲器
            buffer = inner_buffer

        new_state = MAFENNState(buffer=buffer.detach(),
                                lstm_hx=None if lstm_hx is None else (lstm_hx[0].detach(), lstm_hx[1].detach()))
        return y_outs, x_rec_outs, new_state
