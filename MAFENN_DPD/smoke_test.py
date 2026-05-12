"""极小规模的端到端冒烟测试，用于验证代码链路是否能跑通。

* 只生成 2048 个样本
* MAFENN 用 N=2、K=3、seq_len=128
* 训练 3 个 epoch
* 再跑一次前馈网络
* 最后画一张 PSD 图，打印 ACPR
"""

from __future__ import annotations

from pathlib import Path

import numpy as np
import torch
from torch.utils.data import DataLoader

from .config import DEFAULT_CONFIG
from .dataset import SequenceDataset, build_raw_dataset, split_raw
from .features import extract_features_np
from .metrics import acpr_db, compute_psd, nmse_db
from .model_feedforward import FeedforwardDPD
from .model_mafenn import MAFENN
from .mp_dpd import MemoryPolynomialDPD
from .pa_model import MemoryPolynomialPA
from .signal_gen import generate_ofdm_baseband
from .train import (
    loss_player2_feature,
    loss_player3_complex,
    _target_feature,
)


def run() -> None:
    cfg = DEFAULT_CONFIG
    # 冒烟测试参数
    cfg.data.total_samples = 4096
    cfg.data.train_samples = 2048
    cfg.data.val_samples = 1024
    cfg.model.feedback_iters = 2
    cfg.model.buffer_len = 3
    cfg.model.lstm_hidden = 10
    cfg.model.fc_hidden = 16
    cfg.train.batch_size = 8
    cfg.train.epochs = 3

    device = torch.device("cpu")
    torch.manual_seed(0)
    np.random.seed(0)

    raw = build_raw_dataset(cfg)
    train_raw, val_raw, test_raw = split_raw(raw, cfg)

    train_ds = SequenceDataset(train_raw.x, train_raw.y, seq_len=128)
    loader = DataLoader(train_ds, batch_size=cfg.train.batch_size, shuffle=True)

    # --- MAFENN -----------------------------------------------------------
    mafenn = MAFENN(cfg.model).to(device)
    optim = torch.optim.Adam(mafenn.parameters(), lr=1e-3)
    for epoch in range(cfg.train.epochs):
        total = 0.0
        count = 0
        for feats, y_two in loader:
            feats, y_two = feats.to(device), y_two.to(device)
            y_feat_target = _target_feature(y_two)
            state = mafenn.init_state(feats.size(0), device)
            y_pred, x_rec, _ = mafenn(feats, state)
            l2 = loss_player2_feature(x_rec, y_feat_target)
            l3 = loss_player3_complex(y_pred, y_two)
            loss = l2 + cfg.model.alpha * l3
            optim.zero_grad()
            loss.backward()
            optim.step()
            total += float(loss.detach())
            count += 1
        print(f"[MAFENN] epoch {epoch + 1}/{cfg.train.epochs} loss={total / count:.4f}")

    # --- 前馈基线 ---------------------------------------------------------
    ff = FeedforwardDPD(cfg.model).to(device)
    optim_ff = torch.optim.Adam(ff.parameters(), lr=1e-3)
    for epoch in range(cfg.train.epochs):
        total = 0.0
        count = 0
        for feats, y_two in loader:
            feats, y_two = feats.to(device), y_two.to(device)
            y_pred = ff(feats)
            loss = loss_player3_complex(y_pred, y_two)
            optim_ff.zero_grad()
            loss.backward()
            optim_ff.step()
            total += float(loss.detach())
            count += 1
        print(f"[FF]     epoch {epoch + 1}/{cfg.train.epochs} loss={total / count:.4f}")

    # --- 推理对比 ---------------------------------------------------------
    x = generate_ofdm_baseband(cfg.ofdm, num_samples=4096)
    pa = MemoryPolynomialPA(cfg.pa)

    # MP-DPD
    mp = MemoryPolynomialDPD(nonlinear_order=cfg.pa.nonlinear_order,
                             memory_depth=cfg.pa.memory_depth)
    mp.fit(pa_in=raw.y[:cfg.data.train_samples],
           pa_out_over_gain=raw.x[:cfg.data.train_samples])
    y_mp = pa(mp.apply(x))

    # Networks
    def run_net(net, kind: str) -> np.ndarray:
        feats = extract_features_np(x)
        feats_t = torch.from_numpy(feats).unsqueeze(0)
        with torch.no_grad():
            if kind == "mafenn":
                state = net.init_state(1, device)
                y_pred, _, _ = net(feats_t, state)
            else:
                y_pred = net(feats_t)
        y = y_pred.squeeze(0).numpy()
        return (y[:, 0] + 1j * y[:, 1]).astype(np.complex64)

    y_ff = pa(run_net(ff, "ff"))
    y_ma = pa(run_net(mafenn, "mafenn"))
    y_raw = pa(x)

    fs = cfg.ofdm.sample_rate_hz
    for name, y in [("No DPD", y_raw), ("FF-NN DPD", y_ff),
                    ("MAFENN-DPD", y_ma), ("MP-DPD", y_mp)]:
        lo, hi = acpr_db(y, fs=fs, main_bw=100e6, adj_offset=100e6)
        ideal = x * cfg.pa.gain_linear
        nm = nmse_db(ideal, y)
        print(f"{name:14s} ACPR={lo:6.2f}/{hi:6.2f}  NMSE={nm:6.2f} dB")

    print("[smoke_test] 成功跑完 ✓")


if __name__ == "__main__":
    run()
