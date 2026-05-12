"""MAFENN-DPD / 前馈网络基线的训练脚本。

训练对齐论文：
* 特征维 n=5, 反馈循环 N=5, 缓冲器长度 K=7, epoch=200, Adam
* Player2 loss: L1 + L2（特征域）
* Player3 loss: L1 + L2（复数域，实虚两路分别计算再求和）
* Player1 loss: l2 + alpha * l3
* 多次反馈循环过程中的损失累积后反向传播

训练过程中我们直接对三个智能体做同步（联合）优化，与论文 5.1 节结论一致：
  "同步训练可以带来 4.5 dB 的性能提升"。
"""

from __future__ import annotations

import argparse
import os
from dataclasses import asdict
from pathlib import Path

import numpy as np
import torch
import torch.nn as nn
from torch.utils.data import DataLoader
from tqdm import tqdm

from .config import Config, DEFAULT_CONFIG
from .dataset import SequenceDataset, build_raw_dataset, split_raw
from .metrics import nmse_db
from .model_feedforward import FeedforwardDPD
from .model_mafenn import MAFENN


# ---------------------------------------------------------------------------
# 损失函数：L1 + L2 联合
# ---------------------------------------------------------------------------
def _l1_l2(pred: torch.Tensor, target: torch.Tensor) -> torch.Tensor:
    return torch.mean(torch.abs(pred - target)) + torch.mean((pred - target) ** 2)


def loss_player2_feature(x_rec: torch.Tensor, y_feat: torch.Tensor) -> torch.Tensor:
    """特征域 Player2 损失（式 3）。"""
    return _l1_l2(x_rec, y_feat)


def loss_player3_complex(y_pred: torch.Tensor, y_target: torch.Tensor) -> torch.Tensor:
    """复数域 Player3 损失（式 4）。y_*: (..., 2) 实/虚两路。"""
    # 实虚部分别 L1 + L2
    diff = y_pred - y_target
    l1 = 0.5 * (torch.mean(torch.abs(diff[..., 0])) + torch.mean(torch.abs(diff[..., 1])))
    l2 = 0.5 * (torch.mean(diff[..., 0] ** 2) + torch.mean(diff[..., 1] ** 2))
    return l1 + l2


# ---------------------------------------------------------------------------
# 训练主函数
# ---------------------------------------------------------------------------
def _target_feature(y_two: torch.Tensor) -> torch.Tensor:
    """从复数目标 (B,T,2) 构造 5 维特征，与 x_rec 对齐。"""
    re = y_two[..., 0]
    im = y_two[..., 1]
    abs_y = torch.sqrt(re * re + im * im + 1e-12)
    return torch.stack([re, im, abs_y, abs_y ** 2, abs_y ** 3], dim=-1)


def resolve_device(name: str) -> torch.device:
    if name == "auto":
        return torch.device("cuda" if torch.cuda.is_available() else "cpu")
    return torch.device(name)


def make_model(name: str, cfg: Config) -> nn.Module:
    if name == "mafenn":
        return MAFENN(cfg.model)
    if name == "ff":
        return FeedforwardDPD(cfg.model)
    raise ValueError(f"未知模型 {name}")


def evaluate(model: nn.Module, loader: DataLoader, cfg: Config, device: torch.device, model_name: str) -> float:
    model.eval()
    preds = []
    targets = []
    with torch.no_grad():
        for feats, y_two in loader:
            feats = feats.to(device)
            y_two = y_two.to(device)
            if model_name == "mafenn":
                state = model.init_state(feats.size(0), device)
                y_pred, _, _ = model(feats, state)
            else:
                y_pred = model(feats)
            preds.append(y_pred.cpu().numpy().reshape(-1, 2))
            targets.append(y_two.cpu().numpy().reshape(-1, 2))
    preds = np.concatenate(preds, axis=0)
    targets = np.concatenate(targets, axis=0)
    pred_c = preds[..., 0] + 1j * preds[..., 1]
    tgt_c = targets[..., 0] + 1j * targets[..., 1]
    return nmse_db(tgt_c, pred_c)


def train_one_epoch_mafenn(
    model: MAFENN,
    loader: DataLoader,
    optim: torch.optim.Optimizer,
    cfg: Config,
    device: torch.device,
) -> float:
    model.train()
    total = 0.0
    count = 0
    for feats, y_two in loader:
        feats = feats.to(device)
        y_two = y_two.to(device)
        y_feat_target = _target_feature(y_two)

        state = model.init_state(feats.size(0), device)
        y_pred, x_rec, _ = model(feats, state)

        l2 = loss_player2_feature(x_rec, y_feat_target)
        l3 = loss_player3_complex(y_pred, y_two)
        l1 = l2 + cfg.model.alpha * l3

        optim.zero_grad()
        l1.backward()
        torch.nn.utils.clip_grad_norm_(model.parameters(), cfg.train.grad_clip)
        optim.step()
        total += float(l1.detach())
        count += 1
    return total / max(count, 1)


def train_one_epoch_ff(
    model: FeedforwardDPD,
    loader: DataLoader,
    optim: torch.optim.Optimizer,
    cfg: Config,
    device: torch.device,
) -> float:
    model.train()
    total = 0.0
    count = 0
    for feats, y_two in loader:
        feats = feats.to(device)
        y_two = y_two.to(device)
        y_pred = model(feats)
        loss = loss_player3_complex(y_pred, y_two)
        optim.zero_grad()
        loss.backward()
        torch.nn.utils.clip_grad_norm_(model.parameters(), cfg.train.grad_clip)
        optim.step()
        total += float(loss.detach())
        count += 1
    return total / max(count, 1)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--model", choices=["mafenn", "ff"], default="mafenn")
    parser.add_argument("--epochs", type=int, default=DEFAULT_CONFIG.train.epochs)
    parser.add_argument("--batch_size", type=int, default=DEFAULT_CONFIG.train.batch_size)
    parser.add_argument("--lr", type=float, default=DEFAULT_CONFIG.train.lr)
    parser.add_argument("--seq_len", type=int, default=512, help="每个训练样本的时间步长度")
    parser.add_argument("--device", default=DEFAULT_CONFIG.train.device)
    parser.add_argument("--tag", default="run", help="保存文件的额外标识")
    args = parser.parse_args()

    cfg = DEFAULT_CONFIG
    cfg.train.epochs = args.epochs
    cfg.train.batch_size = args.batch_size
    cfg.train.lr = args.lr
    cfg.train.device = args.device

    device = resolve_device(cfg.train.device)
    print(f"[MAFENN-DPD] 使用设备 {device}")

    print("[1/3] 生成 OFDM + PA 数据...")
    raw = build_raw_dataset(cfg)
    train_raw, val_raw, test_raw = split_raw(raw, cfg)

    train_ds = SequenceDataset(train_raw.x, train_raw.y, seq_len=args.seq_len)
    val_ds = SequenceDataset(val_raw.x, val_raw.y, seq_len=args.seq_len)
    train_loader = DataLoader(train_ds, batch_size=cfg.train.batch_size, shuffle=True, drop_last=False)
    val_loader = DataLoader(val_ds, batch_size=cfg.train.batch_size, shuffle=False)

    print("[2/3] 构建模型...")
    model = make_model(args.model, cfg).to(device)
    num_params = sum(p.numel() for p in model.parameters())
    print(f"参数量：{num_params}")
    optim = torch.optim.Adam(model.parameters(), lr=cfg.train.lr, weight_decay=cfg.train.weight_decay)

    print("[3/3] 开始训练...")
    save_dir = Path(cfg.train.save_dir)
    save_dir.mkdir(parents=True, exist_ok=True)
    log_path = save_dir / f"log_{args.model}_{args.tag}.csv"
    log_path.write_text("epoch,train_loss,val_nmse_db\n", encoding="utf-8")

    best_nmse = float("inf")
    with tqdm(total=args.epochs, desc="训练") as bar:
        for epoch in range(1, args.epochs + 1):
            if args.model == "mafenn":
                loss = train_one_epoch_mafenn(model, train_loader, optim, cfg, device)
            else:
                loss = train_one_epoch_ff(model, train_loader, optim, cfg, device)

            val_nmse = evaluate(model, val_loader, cfg, device, args.model)
            with log_path.open("a", encoding="utf-8") as f:
                f.write(f"{epoch},{loss:.6f},{val_nmse:.4f}\n")
            bar.set_postfix(loss=f"{loss:.4f}", nmse=f"{val_nmse:.2f} dB")
            bar.update(1)

            if val_nmse < best_nmse:
                best_nmse = val_nmse
                torch.save({
                    "model_state": model.state_dict(),
                    "config": asdict(cfg),
                    "val_nmse_db": val_nmse,
                    "epoch": epoch,
                }, save_dir / f"best_{args.model}_{args.tag}.pt")

    print(f"训练完成，最佳验证 NMSE = {best_nmse:.2f} dB")
    print(f"日志：{log_path}")


if __name__ == "__main__":
    main()
