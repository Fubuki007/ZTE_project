"""典型前馈网络基线：MAFENN 的 N=0 退化情形。

为做公平对比，保留了同样的过去 K 个时刻信息（只是不再有反馈循环），
结构与编码器 + 处理器一致：LSTM + FC + ReLU + Linear(2)。
"""

from __future__ import annotations

import torch
import torch.nn as nn

from .config import ModelConfig


class FeedforwardDPD(nn.Module):
    def __init__(self, cfg: ModelConfig) -> None:
        super().__init__()
        self.cfg = cfg
        in_dim = cfg.feature_dim * (cfg.buffer_len + 1)  # 当前 + K 个历史特征
        self.lstm = nn.LSTM(
            input_size=in_dim,
            hidden_size=cfg.lstm_hidden,
            num_layers=cfg.lstm_layers,
            batch_first=True,
        )
        self.fc = nn.Sequential(
            nn.Linear(cfg.lstm_hidden, cfg.fc_hidden),
            nn.ReLU(),
            nn.Linear(cfg.fc_hidden, 2),
        )

    def forward(self, feats: torch.Tensor) -> torch.Tensor:
        """feats: (B, T, F) -> (B, T, 2)。

        将过去 K 个时刻的特征拼接到当前时刻作为输入。
        """
        B, T, F = feats.shape
        K = self.cfg.buffer_len

        # 构造滑窗：在时间维上前面补零
        pad = torch.zeros(B, K, F, device=feats.device, dtype=feats.dtype)
        padded = torch.cat([pad, feats], dim=1)                     # (B, T+K, F)
        # 取 K+1 个窗口拼接
        windows = [padded[:, i:i + T, :] for i in range(K + 1)]
        x_cat = torch.cat(windows, dim=-1)                          # (B, T, (K+1)*F)

        out, _ = self.lstm(x_cat)
        return self.fc(out)
