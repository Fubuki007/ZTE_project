"""对比评估 MAFENN-DPD / 前馈网络 / 记忆多项式 / 未预失真 四种方案。

流程（对齐论文 5.3 节）：
1. 重新生成一段 OFDM 信号 x(i)
2. 分别走四种方案得到 PA 输入 x'(i)，再通过相同 PA 得到输出 y(i)
   * 未预失真：x'(i) = x(i)
   * 前馈网络：x'(i) = FF(x(i))
   * MAFENN：  x'(i) = MAFENN(x(i))
   * 记忆多项式：x'(i) = MP(x(i))
3. 计算 PSD、ACPR（以主信道 100 MHz、邻信道偏移 100 MHz 为默认）
4. 画图保存到 figures/ 并打印 ACPR 表格
"""

from __future__ import annotations

import argparse
import os
from pathlib import Path

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np
import torch

from .config import DEFAULT_CONFIG, Config
from .dataset import build_raw_dataset
from .features import extract_features_np
from .metrics import acpr_db, compute_psd, nmse_db
from .model_feedforward import FeedforwardDPD
from .model_mafenn import MAFENN
from .mp_dpd import MemoryPolynomialDPD
from .pa_model import MemoryPolynomialPA
from .signal_gen import generate_ofdm_baseband


# ---------------------------------------------------------------------------
# 载入训练好的神经网络 DPD
# ---------------------------------------------------------------------------
def load_net(ckpt_path: str, model_type: str, cfg: Config, device: torch.device):
    state = torch.load(ckpt_path, map_location=device, weights_only=False)
    if model_type == "mafenn":
        net = MAFENN(cfg.model)
    else:
        net = FeedforwardDPD(cfg.model)
    net.load_state_dict(state["model_state"])
    net.to(device).eval()
    return net


def apply_net_dpd(net, x_complex: np.ndarray, model_type: str, cfg: Config,
                  device: torch.device, chunk: int = 4096) -> np.ndarray:
    """用训练好的神经网络对 x_complex 做预失真，返回复数序列。"""
    feats = extract_features_np(x_complex)  # (L, 5)
    feats_t = torch.from_numpy(feats).unsqueeze(0).to(device)  # (1, L, 5)
    outs = []
    with torch.no_grad():
        if model_type == "mafenn":
            # 按块分段处理，保持状态连续
            state = net.init_state(1, device)
            for start in range(0, feats_t.size(1), chunk):
                seg = feats_t[:, start:start + chunk, :]
                y_pred, _, state = net(seg, state)
                outs.append(y_pred.cpu().numpy())
        else:
            for start in range(0, feats_t.size(1), chunk):
                seg = feats_t[:, start:start + chunk, :]
                y_pred = net(seg)
                outs.append(y_pred.cpu().numpy())
    y = np.concatenate(outs, axis=1).squeeze(0)  # (L, 2)
    return (y[:, 0] + 1j * y[:, 1]).astype(np.complex64)


# ---------------------------------------------------------------------------
# 主入口
# ---------------------------------------------------------------------------
def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--mafenn_ckpt", default="MAFENN_DPD/checkpoints/best_mafenn_run.pt")
    parser.add_argument("--ff_ckpt", default="MAFENN_DPD/checkpoints/best_ff_run.pt")
    parser.add_argument("--num_samples", type=int, default=20000)
    parser.add_argument("--device", default="auto")
    parser.add_argument("--adj_offset_mhz", type=float, default=100.0)
    parser.add_argument("--main_bw_mhz", type=float, default=100.0)
    args = parser.parse_args()

    cfg = DEFAULT_CONFIG
    device = torch.device("cuda" if (args.device == "auto" and torch.cuda.is_available())
                          else ("cuda" if args.device == "cuda" else "cpu"))
    print(f"[evaluate] 使用设备 {device}")

    # --- 1) 生成仿真信号 ----------------------------------------------------
    x = generate_ofdm_baseband(cfg.ofdm, num_samples=args.num_samples)
    pa = MemoryPolynomialPA(cfg.pa)
    gain = cfg.pa.gain_linear

    # --- 2) 训练记忆多项式 DPD（用训练集） ----------------------------------
    print("[evaluate] 拟合记忆多项式 DPD ...")
    raw = build_raw_dataset(cfg)
    # 训练集的 PA 输入 = raw.y, PA 输出/gain = raw.x
    mp = MemoryPolynomialDPD(nonlinear_order=cfg.pa.nonlinear_order,
                             memory_depth=cfg.pa.memory_depth)
    mp.fit(pa_in=raw.y[:cfg.data.train_samples],
           pa_out_over_gain=raw.x[:cfg.data.train_samples])

    # --- 3) 四种方案 --------------------------------------------------------
    results: dict[str, np.ndarray] = {}

    # (a) 未预失真
    results["No DPD"] = pa(x)

    # (b) 记忆多项式 DPD
    x_mp = mp.apply(x)
    results["MP-DPD"] = pa(x_mp)

    # (c) 前馈网络
    if Path(args.ff_ckpt).is_file():
        ff_net = load_net(args.ff_ckpt, "ff", cfg, device)
        x_ff = apply_net_dpd(ff_net, x, "ff", cfg, device)
        results["FF-NN DPD"] = pa(x_ff)
    else:
        print(f"[warn] 未找到前馈网络 ckpt: {args.ff_ckpt}")

    # (d) MAFENN-DPD
    if Path(args.mafenn_ckpt).is_file():
        mafenn_net = load_net(args.mafenn_ckpt, "mafenn", cfg, device)
        x_ma = apply_net_dpd(mafenn_net, x, "mafenn", cfg, device)
        results["MAFENN-DPD"] = pa(x_ma)
    else:
        print(f"[warn] 未找到 MAFENN ckpt: {args.mafenn_ckpt}")

    # --- 4) 计算指标 --------------------------------------------------------
    fs = cfg.ofdm.sample_rate_hz
    main_bw = args.main_bw_mhz * 1e6
    adj_offset = args.adj_offset_mhz * 1e6
    print()
    print("ACPR (dBc)：下边带 / 上边带")
    print("-" * 40)
    acpr_tab = {}
    for name, y in results.items():
        lo, hi = acpr_db(y, fs=fs, main_bw=main_bw, adj_offset=adj_offset)
        acpr_tab[name] = (lo, hi)
        # 同时报告 NMSE（以 x*gain 为理想线性 PA 输出参考）
        ideal = x * gain
        nm = nmse_db(ideal, y)
        print(f"{name:14s}  ACPR = {lo:6.2f} / {hi:6.2f}   NMSE = {nm:6.2f} dB")

    # --- 5) 画 PSD 对比图 ---------------------------------------------------
    fig_dir = Path(cfg.train.figure_dir)
    fig_dir.mkdir(parents=True, exist_ok=True)
    fig, ax = plt.subplots(figsize=(9, 5))
    for name, y in results.items():
        freqs, psd_db = compute_psd(y, fs=fs, nfft=4096)
        ax.plot(freqs / 1e6, psd_db, label=name, linewidth=1.2)
    ax.set_xlabel("Frequency (MHz)")
    ax.set_ylabel("PSD (dB/Hz)")
    ax.set_title("不同 DPD 方案下 PA 输出功率谱密度")
    ax.grid(True, linestyle="--", alpha=0.5)
    ax.legend(loc="best")
    out_path = fig_dir / "psd_comparison.png"
    fig.tight_layout()
    fig.savefig(out_path, dpi=150)
    print(f"\nPSD 对比图已保存：{out_path}")


if __name__ == "__main__":
    main()
