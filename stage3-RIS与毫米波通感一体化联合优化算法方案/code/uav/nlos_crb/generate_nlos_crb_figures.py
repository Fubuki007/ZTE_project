#!/usr/bin/env python3
"""
Publication-grade IEEE & Presentation Figure Generator for:
3GPP UMi Urban Street-Canyon Blockage-Aware UAV-BS + Passive 32x32 2-bit RIS ISAC.

Reads exclusively from audited full-scale server outputs:
  - server-results/uav-nlos_crb/691743ee8ef239e5aeeefa2adb03b5379b5abb5a/case_metrics.csv
  - server-results/uav-nlos_crb/691743ee8ef239e5aeeefa2adb03b5379b5abb5a/independent_audit.json
  - server-results/uav-nlos_crb/691743ee8ef239e5aeeefa2adb03b5379b5abb5a/ablations.json
  - gate1_evidence.json & gate2_evidence.json

Outputs:
  1) figures/ieee/*.pdf, *.eps, *.png (300 DPI, English, IEEE journal styling)
  2) figures/ppt/*.png (300 DPI, Chinese, Microsoft YaHei, matched to PPT palette)
"""

from __future__ import annotations

import csv
import json
import math
from pathlib import Path
from typing import Dict, List, Tuple

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import matplotlib.patches as mpatches
from matplotlib.lines import Line2D
import numpy as np


# ---------------------------------------------------------------------------
# Paths & audited release identifiers
# ---------------------------------------------------------------------------
SCRIPT_DIR = Path(__file__).resolve().parent
REPO_ROOT = SCRIPT_DIR.parents[3]
RELEASE_SHA = "691743ee8ef239e5aeeefa2adb03b5379b5abb5a"
RESULTS_DIR = REPO_ROOT / "server-results" / "uav-nlos_crb" / RELEASE_SHA

IEEE_DIR = SCRIPT_DIR / "figures" / "ieee"
PPT_DIR = SCRIPT_DIR / "figures" / "ppt"
IEEE_DIR.mkdir(parents=True, exist_ok=True)
PPT_DIR.mkdir(parents=True, exist_ok=True)

# ---------------------------------------------------------------------------
# Color palette (harmonized across IEEE & PPT decks)
# ---------------------------------------------------------------------------
PAL = {
    "navy": "#0B1F3A",
    "teal": "#0E8F8F",
    "teal_light": "#E6F4F4",
    "orange": "#D98B00",
    "rose": "#CF4963",
    "blue": "#2563EB",
    "purple": "#7C3AED",
    "slate": "#475569",
    "muted": "#64748B",
    "gray": "#94A3B8",
    "silver": "#CBD5E1",
    "border": "#E2E8F0",
    "bg": "#FFFFFF",
    "panel_bg": "#F8FAFC",
}

METHODS = [
    "FixedOpt_NoRIS",
    "FixedOpt_RIS",
    "FixedOpt_RandomRIS",
    "OnlineUAV_NoRIS",
    "MatchedPos_NoRIS",
    "GridSelect_RIS",
    "Lit_EnergyMax_AO",
    "Proposed_Joint_CRB",
]

METHOD_EN = {
    "FixedOpt_NoRIS": "Fixed-Opt NoRIS",
    "FixedOpt_RIS": "Fixed-Opt RIS",
    "FixedOpt_RandomRIS": "Fixed-Opt RandRIS",
    "OnlineUAV_NoRIS": "Online UAV NoRIS",
    "MatchedPos_NoRIS": "Matched-Pos NoRIS",
    "GridSelect_RIS": "Grid-Select RIS",
    "Lit_EnergyMax_AO": "Lit. EnergyMax-AO",
    "Proposed_Joint_CRB": "Proposed Joint-CRB",
}

METHOD_ZH = {
    "FixedOpt_NoRIS": "固定站(无RIS)",
    "FixedOpt_RIS": "最优固定站(带RIS)",
    "FixedOpt_RandomRIS": "固定站(随机RIS)",
    "OnlineUAV_NoRIS": "无人机(无RIS)",
    "MatchedPos_NoRIS": "同位置(无RIS)",
    "GridSelect_RIS": "网格选点(带RIS)",
    "Lit_EnergyMax_AO": "现有法(照最亮)",
    "Proposed_Joint_CRB": "本文联合方案",
}

METHOD_COLOR = {
    "FixedOpt_NoRIS": "#94A3B8",
    "FixedOpt_RIS": "#2563EB",
    "FixedOpt_RandomRIS": "#CBD5E1",
    "OnlineUAV_NoRIS": "#64748B",
    "MatchedPos_NoRIS": "#475569",
    "GridSelect_RIS": "#D98B00",
    "Lit_EnergyMax_AO": "#CF4963",
    "Proposed_Joint_CRB": "#0E8F8F",
}

METHOD_MARKER = {
    "FixedOpt_NoRIS": "s",
    "FixedOpt_RIS": "D",
    "FixedOpt_RandomRIS": "v",
    "OnlineUAV_NoRIS": "^",
    "MatchedPos_NoRIS": "P",
    "GridSelect_RIS": "o",
    "Lit_EnergyMax_AO": "X",
    "Proposed_Joint_CRB": "*",
}


def set_style(lang: str = "en") -> None:
    plt.rcdefaults()
    if lang == "zh":
        plt.rcParams["font.sans-serif"] = ["Microsoft YaHei", "SimHei", "DejaVu Sans"]
    else:
        plt.rcParams["font.family"] = "serif"
        plt.rcParams["font.serif"] = ["Times New Roman", "DejaVu Serif", "STIXGeneral"]
    plt.rcParams["axes.unicode_minus"] = False
    plt.rcParams["pdf.fonttype"] = 42
    plt.rcParams["ps.fonttype"] = 42
    plt.rcParams["axes.edgecolor"] = "#334155"
    plt.rcParams["axes.linewidth"] = 0.85
    plt.rcParams["xtick.color"] = "#1E293B"
    plt.rcParams["ytick.color"] = "#1E293B"
    plt.rcParams["text.color"] = "#0F172A"
    plt.rcParams["grid.color"] = "#E2E8F0"
    plt.rcParams["grid.linestyle"] = "--"
    plt.rcParams["grid.linewidth"] = 0.65
    plt.rcParams["legend.frameon"] = True
    plt.rcParams["legend.framealpha"] = 0.94
    plt.rcParams["legend.edgecolor"] = "#CBD5E1"


def save_fig(fig: plt.Figure, name: str, lang: str = "en") -> None:
    if lang == "en":
        for ext in ("pdf", "eps", "png"):
            out = IEEE_DIR / f"{name}.{ext}"
            kwargs = {"dpi": 300, "bbox_inches": "tight", "facecolor": "white"}
            if ext == "eps":
                # Avoid transparency warnings in EPS while keeping crisp vectors
                kwargs["facecolor"] = "white"
            fig.savefig(out, **kwargs)
    else:
        out = PPT_DIR / f"{name}.png"
        fig.savefig(out, dpi=300, bbox_inches="tight", facecolor="white")
    plt.close(fig)


# ---------------------------------------------------------------------------
# Data loading & exact verification
# ---------------------------------------------------------------------------
def load_data():
    csv_path = RESULTS_DIR / "case_metrics.csv"
    rows: List[dict] = []
    with csv_path.open("r", encoding="utf-8-sig", newline="") as f:
        for r in csv.DictReader(f):
            parsed = {}
            for k, v in r.items():
                if k == "method":
                    parsed[k] = v
                else:
                    try:
                        parsed[k] = float(v)
                    except ValueError:
                        parsed[k] = v
            rows.append(parsed)

    assert len(rows) == 7200, f"Expected 7200 rows, got {len(rows)}"

    audit = json.loads((RESULTS_DIR / "independent_audit.json").read_text(encoding="utf-8"))
    ablations = json.loads((RESULTS_DIR / "ablations.json").read_text(encoding="utf-8"))
    gate1 = json.loads((SCRIPT_DIR / "gate1_evidence.json").read_text(encoding="utf-8"))
    gate2 = json.loads((SCRIPT_DIR / "gate2_evidence.json").read_text(encoding="utf-8"))

    # Organize by (rcs, method) sorted by trial
    by_rm: Dict[Tuple[int, str], List[dict]] = {}
    for r in rows:
        key = (int(round(r["rcs_m2"])), r["method"])
        by_rm.setdefault(key, []).append(r)
    for key in by_rm:
        by_rm[key].sort(key=lambda x: int(round(x["trial"])))
        assert len(by_rm[key]) == 300

    # Verify exact RMSE match with independent_audit.json
    audit_map = {(int(g["rcs_m2"]), g["method"]): g for g in audit["groups"]}
    for (rcs, m), grp in by_rm.items():
        sq = np.array([(r["err_t1_m"] ** 2 + r["err_t2_m"] ** 2) * 0.5 for r in grp])
        rmse = float(np.sqrt(np.mean(sq)))
        assert abs(rmse - audit_map[(rcs, m)]["rmse_all_m"]) < 1e-10, (rcs, m, rmse)

    return by_rm, audit, ablations, gate1, gate2


def compute_metrics(grp: List[dict], nlos_trials: set[int] | None = None) -> dict:
    sq = np.array([(r["err_t1_m"] ** 2 + r["err_t2_m"] ** 2) * 0.5 for r in grp])
    cap = np.array([r["captured_both"] > 0.5 for r in grp])
    succ1 = np.array([r["success_1m"] > 0.5 for r in grp])
    succ2p = np.array([r["success_rel2pct"] > 0.5 for r in grp])
    e2 = np.array([r["err_t2_m"] for r in grp])
    res = {
        "rmse_all": float(np.sqrt(np.mean(sq))),
        "cond_rmse": float(np.sqrt(np.mean(sq[cap]))) if np.any(cap) else float("nan"),
        "succ1": float(np.mean(succ1) * 100.0),
        "succ2p": float(np.mean(succ2p) * 100.0),
        "capture": float(np.mean(cap) * 100.0),
        "t2_cond_rmse": float(np.sqrt(np.mean(e2[cap] ** 2))) if np.any(cap) else float("nan"),
    }
    if nlos_trials is not None:
        sub = [r for r in grp if int(round(r["trial"])) in nlos_trials]
        sub_cap = np.array([r["captured_both"] > 0.5 for r in sub])
        sub_s1 = np.array([r["success_1m"] > 0.5 for r in sub])
        sub_e2 = np.array([r["err_t2_m"] for r in sub])
        res["nlos_n"] = len(sub)
        res["nlos_succ1"] = float(np.mean(sub_s1) * 100.0)
        res["nlos_t2_cond"] = float(np.sqrt(np.mean(sub_e2[sub_cap] ** 2))) if np.any(sub_cap) else float("nan")
    return res


def paired_bootstrap(grp_a: List[dict], grp_b: List[dict], n_boot: int = 4000, seed: int = 20261125) -> dict:
    rng = np.random.default_rng(seed)
    n = len(grp_a)
    sq_a = np.array([(r["err_t1_m"] ** 2 + r["err_t2_m"] ** 2) * 0.5 for r in grp_a])
    sq_b = np.array([(r["err_t1_m"] ** 2 + r["err_t2_m"] ** 2) * 0.5 for r in grp_b])
    s1_a = np.array([r["success_1m"] for r in grp_a])
    s1_b = np.array([r["success_1m"] for r in grp_b])

    idx = rng.integers(0, n, size=(n_boot, n))
    rmse_a = np.sqrt(np.mean(sq_a[idx], axis=1))
    rmse_b = np.sqrt(np.mean(sq_b[idx], axis=1))
    gain_pct = (rmse_b - rmse_a) / rmse_b * 100.0
    pp_diff = (np.mean(s1_a[idx], axis=1) - np.mean(s1_b[idx], axis=1)) * 100.0

    pt_rmse_a = float(np.sqrt(np.mean(sq_a)))
    pt_rmse_b = float(np.sqrt(np.mean(sq_b)))
    return {
        "rmse_gain_pct": (pt_rmse_b - pt_rmse_a) / pt_rmse_b * 100.0,
        "rmse_ci": [float(np.percentile(gain_pct, 2.5)), float(np.percentile(gain_pct, 97.5))],
        "succ1_pp": float((np.mean(s1_a) - np.mean(s1_b)) * 100.0),
        "succ1_ci": [float(np.percentile(pp_diff, 2.5)), float(np.percentile(pp_diff, 97.5))],
    }


def rmse_bootstrap_ci(grp: List[dict], n_boot: int = 2000, seed: int = 20261125) -> Tuple[float, float, float]:
    rng = np.random.default_rng(seed)
    sq = np.array([(r["err_t1_m"] ** 2 + r["err_t2_m"] ** 2) * 0.5 for r in grp])
    idx = rng.integers(0, len(sq), size=(n_boot, len(sq)))
    vals = np.sqrt(np.mean(sq[idx], axis=1))
    pt = float(np.sqrt(np.mean(sq)))
    return pt, float(np.percentile(vals, 2.5)), float(np.percentile(vals, 97.5))


# ---------------------------------------------------------------------------
# Figure 1: 3GPP UMi Street Canyon Geometry + Optimal UAV Placement + ECDF
# ---------------------------------------------------------------------------
def plot_fig1_geometry_ecdf(by_rm: dict, lang: str = "en") -> None:
    set_style(lang)
    is_zh = lang == "zh"
    if is_zh:
        fig, ax = plt.subplots(figsize=(6.4, 4.9))
        axes = [ax]
    else:
        fig, (ax, ax_cdf) = plt.subplots(1, 2, figsize=(10.6, 4.3), gridspec_kw={"width_ratios": [1.12, 1.0]})
        axes = [ax, ax_cdf]

    # --- Panel A: Top-down 3GPP UMi Street Canyon (X-Y) ---
    # Main avenue road x in [-20, 0], y in [-160, 160]
    ax.add_patch(mpatches.Rectangle((-20, -160), 20, 320, facecolor="#F1F5F9", edgecolor="none", zorder=0))
    # Side alley x in [0, 32], y in [-6, 6]
    ax.add_patch(mpatches.Rectangle((0, -6), 30, 12, facecolor="#FEF3C7", alpha=0.55, edgecolor="none", zorder=0))

    # East buildings (30 m tall): south y <= -6, north y >= +6
    for y0, h in [(-165, 159), (6, 159)]:
        ax.add_patch(
            mpatches.Rectangle(
                (0, y0), 28, h, facecolor="#CBD5E1", edgecolor="#475569", linewidth=1.1, hatch="///", alpha=0.85, zorder=2
            )
        )
    # West facade wall line x = -20
    ax.plot([-20, -20], [-160, 160], color="#334155", linewidth=2.2, zorder=3)

    # RIS on West facade (-20, 0)
    ax.plot([-20, -20], [-8, 8], color=PAL["teal"], linewidth=5.5, solid_capstyle="butt", zorder=5)
    ax.scatter([-20], [0], s=85, marker="s", color=PAL["teal"], edgecolor="white", linewidth=1.0, zorder=6)

    # Far-field boundary circle D_F = 11 m (and safe min 14 m) around RIS (-20, 0)
    theta = np.linspace(-np.pi / 2, np.pi / 2, 120)
    ax.plot(-20 + 14.0 * np.cos(theta), 14.0 * np.sin(theta), linestyle=":", color=PAL["teal"], linewidth=1.2, zorder=3)

    # Optimal UAV positions from 300 trials at RCS=30 (Proposed_Joint_CRB)
    prop30 = by_rm[(30, "Proposed_Joint_CRB")]
    qx = np.array([r["qx"] for r in prop30 if math.isfinite(r["qx"])])
    qy = np.array([r["qy"] for r in prop30 if math.isfinite(r["qy"])])
    via_ris = np.array([r["t2_via_ris"] > 0.5 for r in prop30 if math.isfinite(r["qx"])])

    ax.scatter(
        qx[via_ris], qy[via_ris], s=18, color=PAL["teal"], alpha=0.55, edgecolors="none", zorder=4,
        label="无人机最优悬停位 (经RIS看盲区)" if is_zh else "Optimal UAV (RR-only via RIS)"
    )
    ax.scatter(
        qx[~via_ris], qy[~via_ris], s=22, color=PAL["orange"], alpha=0.75, edgecolors="none", zorder=4,
        label="无人机最优悬停位 (两目标均直视)" if is_zh else "Optimal UAV (Dual-LoS)"
    )

    # Offline-optimal fixed BS from case_metrics.csv
    fix30 = by_rm[(30, "FixedOpt_RIS")]
    fx = [r["qx"] for r in fix30 if math.isfinite(r["qx"])]
    fy = [r["qy"] for r in fix30 if math.isfinite(r["qy"])]
    if fx:
        ax.scatter(
            [fx[0]], [fy[0]], s=110, marker="D", color=PAL["blue"], edgecolor="white", linewidth=1.1, zorder=7,
            label="全街最强固定基站位置" if is_zh else "Offline-Opt Fixed BS"
        )

    # Illustrative active block zones (South block example)
    ax.add_patch(mpatches.Rectangle((-18, -58), 16, 20, facecolor="#DBEAFE", edgecolor=PAL["blue"], linestyle="--", linewidth=0.9, alpha=0.65, zorder=2))
    ax.add_patch(mpatches.Rectangle((-18, -152), 16, 26, facecolor="#DBEAFE", edgecolor=PAL["blue"], linestyle="--", linewidth=0.9, alpha=0.65, zorder=2))
    ax.add_patch(mpatches.Rectangle((-18, -115), 16, 40, facecolor="#FCE7F3", edgecolor=PAL["rose"], linestyle="--", linewidth=0.9, alpha=0.45, zorder=2))
    ax.add_patch(mpatches.Rectangle((4, -4), 8, 8, facecolor="#FEE2E2", edgecolor=PAL["rose"], linewidth=1.2, alpha=0.85, zorder=3))

    # Representative ray diagram for a South-block trial
    uav_ex = (-4.5, -24.0)
    t2_ex = (8.5, 0.0)
    t1_ex = (-10.0, -95.0)
    ris_pt = (-20.0, 0.0)
    # Blocked DD ray (UAV -> T2)
    ax.plot([uav_ex[0], t2_ex[0]], [uav_ex[1], t2_ex[1]], color=PAL["rose"], linestyle="--", linewidth=1.3, zorder=6)
    # Unblocked RR double-bounce (UAV -> RIS -> T2)
    ax.plot([uav_ex[0], ris_pt[0], t2_ex[0]], [uav_ex[1], ris_pt[1], t2_ex[1]], color=PAL["teal"], linewidth=1.9, zorder=6)
    # LoS ray (UAV -> T1)
    ax.plot([uav_ex[0], t1_ex[0]], [uav_ex[1], t1_ex[1]], color=PAL["navy"], linestyle="-.", linewidth=1.1, alpha=0.8, zorder=5)
    ax.scatter([t2_ex[0]], [t2_ex[1]], s=65, marker="^", color=PAL["rose"], edgecolor="white", linewidth=0.8, zorder=8)
    ax.scatter([t1_ex[0]], [t1_ex[1]], s=55, marker="o", color=PAL["navy"], edgecolor="white", linewidth=0.8, zorder=8)

    # Clean text callouts
    if is_zh:
        ax.text(14, 78, "30米高大楼\n(挡住视线)", ha="center", va="center", fontsize=9.5, fontweight="bold", color="#334155", zorder=8)
        ax.text(14, -78, "30米高大楼\n(挡住视线)", ha="center", va="center", fontsize=9.5, fontweight="bold", color="#334155", zorder=8)
        ax.text(20.0, 0.0, "12m 窄小巷\n盲区目标2", ha="center", va="center", fontsize=8.0, fontweight="bold", color="#991B1B", zorder=9,
                bbox=dict(boxstyle="round,pad=0.20", fc="#FFFBEB", ec="#F59E0B", lw=0.7, alpha=0.95))
        ax.annotate("墙面无源 RIS\n(32×32, 17.1cm)", xy=(-20, 0), xytext=(-37, 38),
                    fontsize=8.3, fontweight="bold", color=PAL["teal"],
                    arrowprops=dict(arrowstyle="->", color=PAL["teal"], lw=1.1))
        ax.annotate("经 RIS 反射绕开大楼", xy=(-12.5, -12), xytext=(-38, -28),
                    fontsize=8.0, color=PAL["teal"], fontweight="bold",
                    arrowprops=dict(arrowstyle="->", color=PAL["teal"], lw=1.0))
        ax.annotate("直接看被墙挡住", xy=(2.0, -12.0), xytext=(4.8, -36),
                    fontsize=8.0, color=PAL["rose"], fontweight="bold",
                    arrowprops=dict(arrowstyle="->", color=PAL["rose"], lw=1.0))
        ax.text(-10, -48, "近处手机用户", ha="center", va="center", fontsize=7.8, color=PAL["blue"], fontweight="bold")
        ax.text(-10, -139, "远处手机用户", ha="center", va="center", fontsize=7.8, color=PAL["blue"], fontweight="bold")
        ax.text(-10, -108, "主路目标1 (可见)", ha="center", va="center", fontsize=7.8, color=PAL["navy"], fontweight="bold",
                bbox=dict(boxstyle="round,pad=0.16", fc="white", ec="none", alpha=0.88), zorder=9)
        ax.set_xlabel("街道宽度方向 X / m（左为主干道，右为小巷）", fontsize=9.5, fontweight="bold")
        ax.set_ylabel("街道长度方向 Y / m（全长 300 m）", fontsize=9.5, fontweight="bold")
        ax.set_title("城市高楼街谷示意图与 300 次测试无人机悬停分布", fontsize=10.5, fontweight="bold", color=PAL["navy"], pad=8)
    else:
        ax.text(14, 82, "East Bldg.\n(30 m tall)", ha="center", va="center", fontsize=8.5, fontweight="bold", color="#334155", zorder=8)
        ax.text(14, -82, "East Bldg.\n(30 m tall)", ha="center", va="center", fontsize=8.5, fontweight="bold", color="#334155", zorder=8)
        ax.text(20.0, 0.0, "12 m Alley\nTarget 2", ha="center", va="center", fontsize=7.6, fontweight="bold", color="#991B1B", zorder=9,
                bbox=dict(boxstyle="round,pad=0.18", fc="#FFFBEB", ec="#F59E0B", lw=0.7, alpha=0.95))
        ax.annotate("32×32 Passive RIS\n(-20, 0, 12 m)", xy=(-20, 0), xytext=(-38, 38),
                    fontsize=8.0, fontweight="bold", color=PAL["teal"],
                    arrowprops=dict(arrowstyle="->", color=PAL["teal"], lw=1.0))
        ax.annotate("RR Double-Bounce", xy=(-12.5, -12), xytext=(-39, -30),
                    fontsize=7.8, color=PAL["teal"], fontweight="bold",
                    arrowprops=dict(arrowstyle="->", color=PAL["teal"], lw=0.9))
        ax.annotate("Blocked DD", xy=(1.8, -12.0), xytext=(4.5, -36),
                    fontsize=7.8, color=PAL["rose"], fontweight="bold",
                    arrowprops=dict(arrowstyle="->", color=PAL["rose"], lw=0.9))
        ax.text(-10, -48, "User 1", ha="center", va="center", fontsize=7.5, color=PAL["blue"], fontweight="bold")
        ax.text(-10, -139, "User 2", ha="center", va="center", fontsize=7.5, color=PAL["blue"], fontweight="bold")
        ax.text(-10, -108, "Target 1 (LoS)", ha="center", va="center", fontsize=7.3, color=PAL["navy"], fontweight="bold",
                bbox=dict(boxstyle="round,pad=0.14", fc="white", ec="none", alpha=0.88), zorder=9)
        ax.set_xlabel("X Coordinate (m)", fontsize=9.5)
        ax.set_ylabel("Y Coordinate (m)", fontsize=9.5)
        ax.set_title("(a) 3GPP UMi Street-Canyon Geometry & UAV Placement", fontsize=10.0, fontweight="bold")

    ax.set_xlim(-40, 29)
    ax.set_ylim(-162, 162)
    ax.grid(True, alpha=0.55)
    ax.spines["top"].set_visible(False)
    ax.spines["right"].set_visible(False)
    ax.legend(loc="upper left", fontsize=7.5 if not is_zh else 8.0, framealpha=0.94, handletextpad=0.35)

    # --- Panel B (IEEE only): ECDF of 3D Localization Error at Primary RCS = 30 m^2 ---
    if not is_zh:
        selected = [
            "Proposed_Joint_CRB",
            "GridSelect_RIS",
            "Lit_EnergyMax_AO",
            "FixedOpt_RIS",
            "OnlineUAV_NoRIS",
            "MatchedPos_NoRIS",
            "FixedOpt_NoRIS",
        ]
        ls_map = {
            "Proposed_Joint_CRB": "-",
            "GridSelect_RIS": "-",
            "Lit_EnergyMax_AO": "--",
            "FixedOpt_RIS": "-.",
            "OnlineUAV_NoRIS": ":",
            "MatchedPos_NoRIS": "--",
            "FixedOpt_NoRIS": ":",
        }
        lw_map = {"Proposed_Joint_CRB": 2.4}
        for m in selected:
            grp = by_rm[(30, m)]
            errs = np.sort(np.array([r["scene_rmse_m"] for r in grp]))
            cdf = np.arange(1, len(errs) + 1) / len(errs)
            ax_cdf.plot(
                errs, cdf * 100.0,
                label=METHOD_EN[m],
                color=METHOD_COLOR[m],
                linestyle=ls_map[m],
                linewidth=lw_map.get(m, 1.55),
                zorder=5 if m == "Proposed_Joint_CRB" else 3,
            )
        ax_cdf.axvline(1.0, color="#334155", linestyle=":", linewidth=1.1)
        ax_cdf.text(1.09, 54, "1.0 m threshold", fontsize=8.0, color="#334155", rotation=90, va="bottom",
                    bbox=dict(boxstyle="round,pad=0.12", fc="white", ec="none", alpha=0.85))
        ax_cdf.set_xscale("log")
        ax_cdf.set_xlim(0.02, 15.0)
        ax_cdf.set_ylim(0, 102)
        ax_cdf.set_xlabel("Scene 3D Localization Error (m, log scale)", fontsize=9.5)
        ax_cdf.set_ylabel("Empirical CDF (%)", fontsize=9.5)
        ax_cdf.set_title("(b) Localization Error ECDF (RCS = 30 m²)", fontsize=10.0, fontweight="bold")
        ax_cdf.grid(True, which="both", alpha=0.5)
        ax_cdf.spines["top"].set_visible(False)
        ax_cdf.spines["right"].set_visible(False)
        ax_cdf.legend(loc="lower right", fontsize=7.6)

    fig.tight_layout()
    save_fig(fig, "fig1_scenario_ecdf" if not is_zh else "ppt_fig1_geometry", lang)


# ---------------------------------------------------------------------------
# Figure 2: 8-Method Main Comparison Across RCS = 10 / 30 / 100 m^2
# ---------------------------------------------------------------------------
def plot_fig2_main_rcs(by_rm: dict, lang: str = "en") -> None:
    set_style(lang)
    is_zh = lang == "zh"
    labels = METHOD_ZH if is_zh else METHOD_EN

    rcs_list = [10, 30, 100]
    fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(11.6, 4.45) if is_zh else (10.8, 4.25))

    x = np.arange(len(METHODS))
    width = 0.25
    rcs_colors = {10: "#94A3B8", 30: PAL["teal"], 100: PAL["navy"]}
    rcs_hatches = {10: "", 30: "", 100: ""}

    rcs_lbl = {10: "小目标 (10m²)", 30: "常规车辆 (30m²)", 100: "大目标 (100m²)"} if is_zh else {10: "RCS = 10 m²", 30: "RCS = 30 m²", 100: "RCS = 100 m²"}
    # Panel A: <1 m Success Rate across RCS
    vals_by_rcs = {rcs: [compute_metrics(by_rm[(rcs, m)])["succ1"] for m in METHODS] for rcs in rcs_list}
    for i, rcs in enumerate(rcs_list):
        vals = vals_by_rcs[rcs]
        bars = ax1.bar(
            x + (i - 1) * width, vals, width=width * 0.94,
            color=rcs_colors[rcs], edgecolor="white", linewidth=0.5,
            label=rcs_lbl[rcs], zorder=3,
        )
        if rcs == 30:
            for j, (b, m, v) in enumerate(zip(bars, METHODS, vals)):
                if m in ("FixedOpt_RIS", "MatchedPos_NoRIS", "GridSelect_RIS", "Lit_EnergyMax_AO", "Proposed_Joint_CRB"):
                    right_taller = vals_by_rcs[100][j] > v + 3.0
                    ax1.text(
                        b.get_x() + b.get_width() / 2 - (0.04 if right_taller else 0.0),
                        v + 1.8, f"{v:.1f}%",
                        ha="right" if right_taller else "center", va="bottom",
                        fontsize=7.3 if not is_zh else 7.6,
                        fontweight="bold" if m == "Proposed_Joint_CRB" else "normal",
                        color=PAL["teal"] if m == "Proposed_Joint_CRB" else "#334155",
                        bbox=dict(boxstyle="round,pad=0.08", fc="white", ec="none", alpha=0.75),
                        zorder=6,
                    )
        elif rcs == 100:
            b_prop = bars[-1]
            v_prop = vals[-1]
            ax1.text(
                b_prop.get_x() + b_prop.get_width() / 2, v_prop + 1.8, f"{v_prop:.1f}%",
                ha="center", va="bottom", fontsize=7.4 if not is_zh else 7.7, fontweight="bold", color=PAL["navy"], zorder=6,
            )

    # Highlight Proposed column subtly
    ax1.axvspan(len(METHODS) - 1.48, len(METHODS) - 0.52, color=PAL["teal_light"], alpha=0.55, zorder=1)
    ax1.set_xticks(x)
    ax1.set_xticklabels([labels[m] for m in METHODS], rotation=26, ha="right", fontsize=8.1 if not is_zh else 8.4)
    ax1.set_ylim(0, 108)
    ax1.set_ylabel("定位误差 <1 米的成功率 (%)" if is_zh else "<1 m Strict Success Rate (%)", fontsize=9.5, fontweight="bold" if is_zh else "normal")
    ax1.set_title("(a) 三种目标大小下的定位成功率（越高越好）" if is_zh else "(a) <1 m Strict Success Rate Across RCS", fontsize=10.2, fontweight="bold", color=PAL["navy"])
    ax1.grid(True, axis="y", alpha=0.6, zorder=0)
    ax1.spines["top"].set_visible(False)
    ax1.spines["right"].set_visible(False)
    ax1.legend(loc="upper left", fontsize=7.8 if is_zh else 8.2, ncol=3, columnspacing=0.7)

    # Panel B: All-Sample 3D RMSE with 95% Bootstrap CI across RCS (capped axis with crisp annotation for Lit_EnergyMax_AO)
    y_cap = 3.45
    lit_clipped_vals = []
    for i, rcs in enumerate(rcs_list):
        pts, err_lo, err_hi = [], [], []
        for m in METHODS:
            pt, lo, hi = rmse_bootstrap_ci(by_rm[(rcs, m)], n_boot=2000, seed=20261125 + rcs)
            pts.append(pt)
            err_lo.append(max(0.0, pt - lo))
            err_hi.append(max(0.0, hi - pt))
        disp_pts = [min(p, y_cap) for p in pts]
        disp_lo = [l if p <= y_cap else 0.0 for p, l in zip(pts, err_lo)]
        disp_hi = [h if p <= y_cap else 0.0 for p, h in zip(pts, err_hi)]
        bars = ax2.bar(
            x + (i - 1) * width, disp_pts, width=width * 0.94,
            color=rcs_colors[rcs], edgecolor="white", linewidth=0.5,
            yerr=[disp_lo, disp_hi], capsize=2.0,
            error_kw=dict(ecolor="#334155", elinewidth=0.75, capthick=0.75),
            label=rcs_lbl[rcs], zorder=3,
        )
        for b, m, p, hi_d in zip(bars, METHODS, pts, disp_hi):
            if p > y_cap and m == "Lit_EnergyMax_AO":
                lit_clipped_vals.append((b.get_x() + b.get_width() / 2, p))
            elif m == "Proposed_Joint_CRB":
                ax2.text(
                    b.get_x() + b.get_width() / 2, p + hi_d + 0.07, f"{p:.2f}",
                    ha="center", va="bottom", fontsize=7.3, fontweight="bold", color=PAL["navy"], zorder=6,
                )
    if lit_clipped_vals:
        cx = float(np.mean([t[0] for t in lit_clipped_vals]))
        txt = " / ".join(f"{t[1]:.1f}" for t in lit_clipped_vals) + " m ↑"
        ax2.text(
            cx, y_cap - 0.14, txt,
            ha="center", va="top", fontsize=6.9, fontweight="bold", color="white",
            bbox=dict(boxstyle="round,pad=0.18", fc=PAL["rose"], ec="white", lw=0.6), zorder=7,
        )

    ax2.axvspan(len(METHODS) - 1.48, len(METHODS) - 0.52, color=PAL["teal_light"], alpha=0.55, zorder=1)
    ax2.set_xticks(x)
    ax2.set_xticklabels([labels[m] for m in METHODS], rotation=26, ha="right", fontsize=8.1 if not is_zh else 8.4)
    ax2.set_ylim(0, 3.65)
    ax2.set_ylabel("平均定位误差 / 米（失败案例全保留）" if is_zh else "All-Sample 3D RMSE (m, Failures Retained)", fontsize=9.5, fontweight="bold" if is_zh else "normal")
    ax2.set_title("(b) 全样本平均定位误差（越低越好）" if is_zh else "(b) All-Sample 3D RMSE with 95% Bootstrap CI", fontsize=10.2, fontweight="bold", color=PAL["navy"])
    ax2.grid(True, axis="y", alpha=0.6, zorder=0)
    ax2.spines["top"].set_visible(False)
    ax2.spines["right"].set_visible(False)
    ax2.legend(loc="upper left", fontsize=7.8 if is_zh else 8.2, ncol=3, columnspacing=0.7)

    fig.tight_layout(w_pad=2.2)
    save_fig(fig, "fig2_rcs_comparison" if not is_zh else "ppt_fig2_main_rcs", lang)


# ---------------------------------------------------------------------------
# Figure 3: Joint (Success Rate, Conditional RMSE) Pareto + Pure-NLoS Breakdown
# ---------------------------------------------------------------------------
def plot_fig3_pareto_nlos(by_rm: dict, lang: str = "en") -> None:
    set_style(lang)
    is_zh = lang == "zh"
    labels = METHOD_ZH if is_zh else METHOD_EN

    fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(11.2, 4.4) if not is_zh else (8.1, 4.35), gridspec_kw={"width_ratios": [1.08, 1.0]})

    # --- Panel A: Joint (Success Rate, Conditional RMSE) at Primary RCS = 30 m^2 ---
    # Ideal corner shading (bottom-right)
    ax1.axvspan(75, 100, ymin=0, ymax=0.38, color=PAL["teal_light"], alpha=0.65, zorder=0)
    ax1.text(87.5, 0.095, "最理想区域\n(抓得稳+测得准)" if is_zh else "Ideal Region\n(High Succ. & Precision)",
             ha="center", va="center", fontsize=7.6, color=PAL["teal"], fontweight="bold")

    coords = {}
    for m in METHODS:
        met = compute_metrics(by_rm[(30, m)])
        coords[m] = (met["succ1"], met["cond_rmse"])
        size = 240 if m == "Proposed_Joint_CRB" else 90
        ax1.scatter(
            met["succ1"], met["cond_rmse"],
            s=size, marker=METHOD_MARKER[m], color=METHOD_COLOR[m],
            edgecolor="white", linewidth=1.0, zorder=5 if m == "Proposed_Joint_CRB" else 4,
        )

    # Custom non-overlapping label offsets
    offsets_en = {
        "FixedOpt_RandomRIS": (4, 7),
        "MatchedPos_NoRIS": (-24, -18),
        "FixedOpt_NoRIS": (4, 8),
        "OnlineUAV_NoRIS": (6, 8),
        "FixedOpt_RIS": (-16, -18),
        "Lit_EnergyMax_AO": (-28, -17),
        "GridSelect_RIS": (-26, 10),
        "Proposed_Joint_CRB": (-78, 12),
    }
    offsets_zh = {
        "FixedOpt_RandomRIS": (4, 7),
        "MatchedPos_NoRIS": (-22, -18),
        "FixedOpt_NoRIS": (5, 8),
        "OnlineUAV_NoRIS": (6, 9),
        "FixedOpt_RIS": (-16, -18),
        "Lit_EnergyMax_AO": (-26, -16),
        "GridSelect_RIS": (-28, 10),
        "Proposed_Joint_CRB": (-72, 12),
    }
    offs = offsets_zh if is_zh else offsets_en
    for m, (sx, cy) in coords.items():
        dx, dy = offs[m]
        ax1.annotate(
            labels[m], xy=(sx, cy), xytext=(dx, dy), textcoords="offset points",
            fontsize=7.3 if is_zh else 7.6,
            fontweight="bold" if m == "Proposed_Joint_CRB" else "normal",
            color=PAL["teal"] if m == "Proposed_Joint_CRB" else "#1E293B",
        )

    # Decoupled gain arrows to Proposed
    px, py = coords["Proposed_Joint_CRB"]
    fx, fy = coords["FixedOpt_RIS"]
    mx, my = coords["MatchedPos_NoRIS"]
    ax1.annotate("", xy=(px - 1.6, py), xytext=(fx + 2.2, fy),
                 arrowprops=dict(arrowstyle="->", color=PAL["blue"], lw=1.25, ls="--", connectionstyle="arc3,rad=0.14"))
    ax1.text(61, 0.112, "+46.3%\n(会飞的功劳)" if is_zh else "+46.3 pp\n(Mobility)",
             ha="center", va="center", fontsize=7.1, color=PAL["blue"], fontweight="bold")
    ax1.annotate("", xy=(px - 1.8, py + 0.03), xytext=(mx + 2.0, my + 0.05),
                 arrowprops=dict(arrowstyle="->", color=PAL["slate"], lw=1.1, ls=":", connectionstyle="arc3,rad=-0.22"))
    ax1.text(46, 0.56, "+69.3% (纯RIS净增益)" if is_zh else "+69.3 pp (Pure RIS Gain)",
             ha="center", va="center", fontsize=7.1, color=PAL["slate"], fontweight="bold")

    ax1.set_yscale("log")
    ax1.set_xlim(0, 96)
    ax1.set_ylim(0.07, 18.0)
    ax1.set_xlabel("整体定位成功率 (%，越靠右越好)" if is_zh else "<1 m Strict Success Rate (%)", fontsize=9.0, fontweight="bold" if is_zh else "normal")
    ax1.set_ylabel("抓到目标后的平均误差 / 米（越低越好）" if is_zh else "Conditional 3D RMSE (m, log scale)", fontsize=9.0, fontweight="bold" if is_zh else "normal")
    ax1.set_title("(a) 既抓得稳、又测得准综合对比（常规目标）" if is_zh else "(a) Joint Success Rate vs. Conditional RMSE (RCS = 30 m²)", fontsize=9.6, fontweight="bold", color=PAL["navy"])
    ax1.grid(True, which="both", alpha=0.5)
    ax1.spines["top"].set_visible(False)
    ax1.spines["right"].set_visible(False)

    # --- Panel B: Pure-NLoS (RR-only) Subset Breakdown Across RCS ---
    rcs_list = [10, 30, 100]
    key_methods = ["MatchedPos_NoRIS", "FixedOpt_RIS", "Lit_EnergyMax_AO", "GridSelect_RIS", "Proposed_Joint_CRB"]
    x = np.arange(len(rcs_list))
    w = 0.155
    for i, m in enumerate(key_methods):
        vals = []
        t2_conds = []
        for rcs in rcs_list:
            nlos_trials = {int(round(r["trial"])) for r in by_rm[(rcs, "Proposed_Joint_CRB")] if r["t2_via_ris"] > 0.5}
            met = compute_metrics(by_rm[(rcs, m)], nlos_trials=nlos_trials)
            vals.append(met["nlos_succ1"])
            t2_conds.append(met["nlos_t2_cond"])
        bars = ax2.bar(
            x + (i - 2) * w, vals, width=w * 0.92,
            color=METHOD_COLOR[m], edgecolor="white", linewidth=0.5,
            label=labels[m], zorder=3,
        )
        if m == "Proposed_Joint_CRB":
            for b, v, c2 in zip(bars, vals, t2_conds):
                ax2.text(
                    b.get_x() + b.get_width() / 2, v + 1.8, f"{v:.1f}%\n({c2:.3f}m)",
                    ha="center", va="bottom", fontsize=7.0, fontweight="bold", color=PAL["navy"],
                )

    nlos_counts = [sum(1 for r in by_rm[(rcs, "Proposed_Joint_CRB")] if r["t2_via_ris"] > 0.5) for rcs in rcs_list]
    ax2.set_xticks(x)
    if is_zh:
        sz_names = ["小目标", "常规车辆", "大目标"]
        ax2.set_xticklabels([f"{nm}\n({n}个盲区)" for nm, n in zip(sz_names, nlos_counts)], fontsize=8.2)
    else:
        ax2.set_xticklabels([f"RCS={r} m²\n(N={n})" for r, n in zip(rcs_list, nlos_counts)], fontsize=8.3)
    ax2.set_ylim(0, 114)
    ax2.set_ylabel("纯盲区定位成功率 (%)" if is_zh else "Pure-NLoS <1 m Success Rate (%)", fontsize=9.0, fontweight="bold" if is_zh else "normal")
    ax2.set_title("(b) 巷子盲区专项成绩（括号为盲区误差）" if is_zh else "(b) Pure-NLoS (RR-Only) Subset & T2 Cond. RMSE", fontsize=9.6, fontweight="bold", color=PAL["navy"])
    ax2.grid(True, axis="y", alpha=0.55)
    ax2.spines["top"].set_visible(False)
    ax2.spines["right"].set_visible(False)
    ax2.legend(loc="upper left", fontsize=7.2, ncol=1)

    fig.tight_layout(w_pad=1.8)
    save_fig(fig, "fig3_pareto_nlos" if not is_zh else "ppt_fig3_pareto_nlos", lang)


# ---------------------------------------------------------------------------
# Figure 4: Paired 95% Bootstrap Forest Plot + Angular EFIM Condition Number
# ---------------------------------------------------------------------------
def plot_fig4_bootstrap_cond(by_rm: dict, lang: str = "en") -> None:
    set_style(lang)
    is_zh = lang == "zh"

    contrasts = [
        ("Proposed_Joint_CRB", "MatchedPos_NoRIS", "比“同位置无RIS”\n(纯RIS净增益)" if is_zh else "vs Matched-Pos NoRIS\n(Pure RIS Gain)"),
        ("Proposed_Joint_CRB", "OnlineUAV_NoRIS", "比“无人机无RIS”\n(加装RIS的收益)" if is_zh else "vs Online UAV NoRIS\n(RIS on Mobile BS)"),
        ("Proposed_Joint_CRB", "FixedOpt_RIS", "比“最优固定站带RIS”\n(移动性净增益)" if is_zh else "vs Fixed-Opt RIS\n(Mobility Gain)"),
        ("Proposed_Joint_CRB", "Lit_EnergyMax_AO", "比“现有论文照最亮”\n(8组斜扫算法增益)" if is_zh else "vs Lit. EnergyMax-AO\n(CRB + Monopulse)"),
        ("Proposed_Joint_CRB", "GridSelect_RIS", "比“网格选点带RIS”\n(连续选位优化增益)" if is_zh else "vs Grid-Select RIS\n(Continuous BCD)"),
        ("FixedOpt_RIS", "FixedOpt_RandomRIS", "调优RIS vs 随机RIS\n(相移优化增益)" if is_zh else "Fixed RIS vs RandRIS\n(Phase Opt. Gain)"),
    ]

    stats = []
    for a, b, lbl in contrasts:
        st = paired_bootstrap(by_rm[(30, a)], by_rm[(30, b)], n_boot=4000, seed=20261125)
        st["label"] = lbl
        stats.append(st)

    fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(11.4, 4.35) if is_zh else (10.8, 4.25), gridspec_kw={"width_ratios": [1.18, 1.0]})

    # --- Panel A: Paired 95% Bootstrap Forest Plot (RCS = 30 m^2) ---
    y = np.arange(len(stats))[::-1]
    offset = 0.16

    for yi, st in zip(y, stats):
        # Success rate +pp (teal)
        s_pt = st["succ1_pp"]
        s_lo, s_hi = st["succ1_ci"]
        ax1.errorbar(
            s_pt, yi + offset, xerr=[[s_pt - s_lo], [s_hi - s_pt]],
            fmt="o", color=PAL["teal"], ecolor=PAL["teal"], elinewidth=2.0, capsize=3.5, markersize=6.2, zorder=4,
        )
        ax1.text(s_hi + 1.5, yi + offset, f"+{s_pt:.1f} pp", va="center", ha="left", fontsize=7.4, fontweight="bold", color=PAL["teal"])

        # RMSE reduction % (orange)
        r_pt = st["rmse_gain_pct"]
        r_lo, r_hi = st["rmse_ci"]
        ax1.errorbar(
            r_pt, yi - offset, xerr=[[r_pt - r_lo], [r_hi - r_pt]],
            fmt="s", color=PAL["orange"], ecolor=PAL["orange"], elinewidth=2.0, capsize=3.5, markersize=5.6, zorder=4,
        )
        ax1.text(r_hi + 1.5, yi - offset, f"-{r_pt:.1f}%", va="center", ha="left", fontsize=7.4, fontweight="bold", color=PAL["orange"])

    ax1.axvline(0.0, color=PAL["rose"], linestyle="--", linewidth=1.2, zorder=2)
    ax1.set_yticks(y)
    ax1.set_yticklabels([s["label"] for s in stats], fontsize=8.0)
    ax1.set_xlim(-5, 108)
    ax1.set_ylim(-0.65, len(stats) - 0.35)
    ax1.set_xlabel("净提升幅度及 95% 可信区间（全部远大于 0，绝非碰运气）" if is_zh else "Paired Gain with 95% Bootstrap CI (4,000 Resamples)", fontsize=8.8, fontweight="bold" if is_zh else "normal")
    ax1.set_title("(a) 6 组拆解对照：谁的功劳清清楚楚" if is_zh else "(a) Paired 95% Bootstrap CIs (RCS = 30 m²)", fontsize=9.8, fontweight="bold", color=PAL["navy"])
    ax1.grid(True, axis="x", alpha=0.55)
    ax1.spines["top"].set_visible(False)
    ax1.spines["right"].set_visible(False)

    leg_handles = [
        Line2D([0], [0], marker="o", color=PAL["teal"], lw=2.0, markersize=6, label="定位成功率净提升 (+百分点)" if is_zh else "<1 m Success Gain (+pp)"),
        Line2D([0], [0], marker="s", color=PAL["orange"], lw=2.0, markersize=5.5, label="平均误差净下降 (%)" if is_zh else "All-Sample RMSE Reduction (%)"),
    ]
    ax1.legend(handles=leg_handles, loc="lower right", fontsize=7.8)

    # --- Panel B: Angular EFIM Condition Number CDF (Pure-NLoS RR-Only, RCS=30) ---
    cond_methods = [
        ("Proposed_Joint_CRB", "本文：RIS 8组斜扫" if is_zh else "Proposed (8-Cfg Monopulse)", PAL["teal"], "-", 2.3),
        ("FixedOpt_RIS", "固定站：RIS 8组斜扫" if is_zh else "Fixed-Opt RIS (8-Cfg)", PAL["blue"], "-.", 1.7),
        ("FixedOpt_RandomRIS", "随机相移 RIS" if is_zh else "Random Diffuse RIS", PAL["slate"], ":", 1.7),
        ("Lit_EnergyMax_AO", "现有法：只管照最亮" if is_zh else "Lit. EnergyMax-AO (1-Beam)", PAL["rose"], "--", 2.1),
    ]
    for m, lbl, col, ls, lw in cond_methods:
        vals = np.array([
            r["ang_cond_t2"] for r in by_rm[(30, m)]
            if r["t2_via_ris"] > 0.5 and math.isfinite(r["ang_cond_t2"]) and r["ang_cond_t2"] > 0
        ])
        vals = np.sort(vals)
        cdf = np.arange(1, len(vals) + 1) / len(vals) * 100.0
        med = float(np.median(vals))
        med_str = f"{med:.2f}" if med < 100 else (f"{med/1e4:.1f}万" if is_zh else f"{med:.1e}")
        ax2.plot(vals, cdf, label=f"{lbl} (中位={med_str})" if is_zh else f"{lbl} (med={med_str})", color=col, linestyle=ls, linewidth=lw)

    ax2.set_xscale("log")
    ax2.set_xlim(1.0, 2e6)
    ax2.set_ylim(0, 103)
    ax2.axvline(10.0, color="#64748B", linestyle=":", linewidth=1.0)
    ax2.text(12.5, 10, "清晰可辨区 (<10)" if is_zh else "Well-conditioned κ < 10", fontsize=7.6, color="#475569")
    ax2.set_xlabel("左右分辨难度（数值越接近 1 越清晰，越大越脸盲）" if is_zh else "Target-2 Angular EFIM Condition Number $\\kappa_{\\mathrm{ang}}$ (log)", fontsize=8.8, fontweight="bold" if is_zh else "normal")
    ax2.set_ylabel("场景累计占比 (%)" if is_zh else "Empirical CDF (%)", fontsize=9.0, fontweight="bold" if is_zh else "normal")
    ax2.set_title("(b) 为什么我们这么准：彻底治好“左右脸盲”" if is_zh else "(b) Breaking RR Angular Ill-Conditioning", fontsize=9.8, fontweight="bold", color=PAL["navy"])
    ax2.grid(True, which="both", alpha=0.5)
    ax2.spines["top"].set_visible(False)
    ax2.spines["right"].set_visible(False)
    ax2.legend(loc="center", fontsize=7.2, bbox_to_anchor=(0.45, 0.50))

    fig.tight_layout(w_pad=1.8)
    save_fig(fig, "fig4_bootstrap_cond" if not is_zh else "ppt_fig4_bootstrap_cond", lang)


# ---------------------------------------------------------------------------
# Figure 5 (IEEE): A4 Comm-Sensing SINR-PEB Pareto & 25-Beam Detection ROC
# ---------------------------------------------------------------------------
def plot_fig5_comm_roc_ieee(ablations: dict) -> None:
    set_style("en")
    a4 = ablations["a4_pareto_roc"]
    fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(10.2, 4.0))

    # Panel A: Comm SINR vs Worst-Target PEB & Feasibility
    sinr = np.array(a4["sinr_grid_db"])
    peb = np.array(a4["median_worst_peb_m"])
    feas = np.array(a4["feasibility_rate"]) * 100.0

    l1 = ax1.plot(sinr, peb, marker="o", color=PAL["teal"], linewidth=2.2, markersize=7, label="Median Worst-Target PEB (m)")
    for s, p in zip(sinr, peb):
        dx = -11 if s == 13 else (-8 if s == 16 else 0)
        ax1.annotate(f"{p:.3f} m", xy=(s, p), xytext=(dx, 8), textcoords="offset points",
                     ha="center", fontsize=8.0, fontweight="bold", color=PAL["navy"])
    ax1.set_xlabel("Communication SINR Threshold $\\gamma_u$ (dB)", fontsize=9.5)
    ax1.set_ylabel("Median Worst-Target PEB (m)", fontsize=9.5, color=PAL["teal"])
    ax1.tick_params(axis="y", labelcolor=PAL["teal"])
    ax1.set_ylim(0, 0.40)
    ax1.set_xticks(sinr)
    ax1.grid(True, alpha=0.55)
    ax1.spines["top"].set_visible(False)

    ax1r = ax1.twinx()
    l2 = ax1r.plot(sinr, feas, marker="s", linestyle="--", color=PAL["rose"], linewidth=1.8, markersize=6, label="Feasibility Rate (%)")
    ax1r.set_ylabel("Feasibility Rate (%)", fontsize=9.5, color=PAL["rose"])
    ax1r.tick_params(axis="y", labelcolor=PAL["rose"])
    ax1r.set_ylim(85, 104)
    ax1r.spines["top"].set_visible(False)

    ax1.axvline(10.0, color=PAL["slate"], linestyle=":", linewidth=1.1)
    ax1.text(10.2, 0.34, "Nominal\n10 dB", fontsize=8.0, color=PAL["slate"])
    lines = l1 + l2
    ax1.legend(lines, [l.get_label() for l in lines], loc="upper left", fontsize=8.0)
    ax1.set_title("(a) Communication–Sensing Pareto Tradeoff (1 W Budget)", fontsize=10.0, fontweight="bold")

    # Panel B: 25-Beam Union Detection ROC (P_fa = 1e-6)
    snr = np.array(a4["roc_snr_db"])
    pd = np.array(a4["roc_pd"]) * 100.0
    ax2.plot(snr, pd, marker="o", color=PAL["navy"], linewidth=2.2, markersize=5.2, label="25-Beam Union ROC ($P_{fa}=10^{-6}$)")
    ax2.axhline(99.0, color=PAL["teal"], linestyle="--", linewidth=1.2, label="$P_d = 99\\%$ Target")
    ax2.axvspan(14.5, 16.5, color=PAL["teal_light"], alpha=0.75, label="C2 Design Margin (14.5–16.5 dB)")
    ax2.scatter([15, 16], [98.514, 99.906], s=70, color=PAL["rose"], zorder=6)
    ax2.annotate("15 dB: 98.5%", xy=(15, 98.514), xytext=(10.2, 90.0), fontsize=8.2, fontweight="bold", color=PAL["rose"],
                 arrowprops=dict(arrowstyle="->", color=PAL["rose"], lw=1.0))
    ax2.annotate("16 dB: 99.91%", xy=(16, 99.906), xytext=(16.8, 82.0), fontsize=8.2, fontweight="bold", color=PAL["teal"],
                 arrowprops=dict(arrowstyle="->", color=PAL["teal"], lw=1.0))

    ax2.set_xlabel("Single-Beam Coherent SNR (dB)", fontsize=9.5)
    ax2.set_ylabel("Detection Probability $P_d$ (%)", fontsize=9.5)
    ax2.set_xlim(6, 22)
    ax2.set_ylim(-2, 105)
    ax2.grid(True, alpha=0.55)
    ax2.spines["top"].set_visible(False)
    ax2.spines["right"].set_visible(False)
    ax2.legend(loc="lower right", fontsize=7.8)
    ax2.set_title("(b) Coarse 5×5 Codebook Detection Probability ($P_{fa}=10^{-6}$)", fontsize=10.0, fontweight="bold")

    fig.tight_layout(w_pad=2.0)
    save_fig(fig, "fig5_comm_roc", "en")


# ---------------------------------------------------------------------------
# Figure 6 (IEEE): A1/A2/A3/A5 Robustness, Wideband Squint & Energy Budget
# ---------------------------------------------------------------------------
def plot_fig6_ablations_ieee(ablations: dict) -> None:
    set_style("en")
    a1 = ablations["a1_wideband_squint"]
    a2 = ablations["a2_prior_sensitivity"]
    a3 = ablations["a3_ris_calibration"]
    a5 = ablations["a5_flight_energy"]

    fig, ((ax1, ax2), (ax3, ax4)) = plt.subplots(2, 2, figsize=(10.4, 7.2))

    # (a) A1 Wideband vs Narrowband Squint
    cats = ["Theoretical\nMedian PEB", "Wideband\n(True Freq.)", "Narrowband\n(Center fc)"]
    vals = [a1["median_peb_m"] * 100.0, a1["wideband_t2_med_m"] * 100.0, a1["narrowband_t2_med_m"] * 100.0]
    cols = [PAL["navy"], PAL["teal"], PAL["rose"]]
    bars = ax1.bar(cats, vals, width=0.52, color=cols, edgecolor="white")
    for b, v in zip(bars, vals):
        ax1.text(b.get_x() + b.get_width() / 2, v + 0.25, f"{v:.2f} cm", ha="center", va="bottom", fontsize=8.6, fontweight="bold")
    ax1.annotate("+25.6% squint bias", xy=(2.20, vals[2] + 0.08), xytext=(1.22, vals[2] + 1.55),
                 fontsize=8.3, fontweight="bold", color=PAL["rose"],
                 arrowprops=dict(arrowstyle="->", color=PAL["rose"], lw=1.1))
    ax1.set_ylabel("Median Target-2 3D Error (cm)", fontsize=9.2)
    ax1.set_ylim(0, 10.8)
    ax1.set_title("(a) A1: Wideband vs. Narrowband Beam Squint (40 NLoS)", fontsize=9.8, fontweight="bold")
    ax1.grid(True, axis="y", alpha=0.55)
    ax1.spines["top"].set_visible(False)
    ax1.spines["right"].set_visible(False)

    # (b) A2 Prior Error Sensitivity
    sig = np.array(a2["prior_sigma_m"])
    cap = np.array(a2["t2_capture_rate"]) * 100.0
    mis = np.array(a2["beam_misalignment_rate"]) * 100.0
    rmse = np.array(a2["t2_rmse_m"])
    x2 = np.arange(len(sig))
    w = 0.30
    b1 = ax2.bar(x2 - w / 2, cap, width=w, color=PAL["teal"], label="T2 Capture (%)")
    b2 = ax2.bar(x2 + w / 2, mis, width=w, color=PAL["rose"], label="Misalign. (%)")
    for b, v in zip(b1, cap):
        ax2.text(b.get_x() + b.get_width() / 2, v + 2.0, f"{v:.1f}%", ha="center", va="bottom", fontsize=7.8, fontweight="bold", color=PAL["teal"])
    for b, v in zip(b2, mis):
        ax2.text(b.get_x() + b.get_width() / 2, v + 2.0, f"{v:.1f}%", ha="center", va="bottom", fontsize=7.8, fontweight="bold", color=PAL["rose"])
    ax2.set_xticks(x2)
    ax2.set_xticklabels([f"σ = {int(s)} m" for s in sig], fontsize=9.0)
    ax2.set_ylim(0, 128)
    ax2.set_ylabel("Rate (%)", fontsize=9.2)
    ax2.spines["top"].set_visible(False)
    ax2.grid(True, axis="y", alpha=0.55)

    ax2r = ax2.twinx()
    l_rmse = ax2r.plot(x2, rmse, marker="D", color=PAL["navy"], linewidth=2.0, markersize=6.5, label="T2 RMSE (m)")
    rmse_offs = [(8, 9), (-16, 10), (-14, 9)]
    for xi, rv, (dx, dy) in zip(x2, rmse, rmse_offs):
        ax2r.annotate(
            f"{rv:.2f} m", xy=(xi, rv), xytext=(dx, dy), textcoords="offset points",
            fontsize=7.7, fontweight="bold", color=PAL["navy"],
            bbox=dict(boxstyle="round,pad=0.14", fc="white", ec="#CBD5E1", lw=0.5, alpha=0.92),
        )
    ax2r.set_ylabel("Target-2 3D RMSE (m)", fontsize=9.2, color=PAL["navy"])
    ax2r.set_ylim(0, 6.2)
    ax2r.spines["top"].set_visible(False)
    h1, l1 = ax2.get_legend_handles_labels()
    h2, l2 = ax2r.get_legend_handles_labels()
    ax2.legend(h1 + h2, l1 + l2, loc="upper center", ncol=3, fontsize=7.0, columnspacing=0.8, handletextpad=0.4)
    ax2.set_title("(b) A2: Prior Uncertainty Sensitivity (5×5 Codebook)", fontsize=9.8, fontweight="bold")

    # (c) A3 RIS Position Calibration Error
    cal_err = np.array(a3["ris_pos_error_m"]) * 100.0  # cm
    cal_rmse = np.array(a3["t2_rmse_m"])
    ax3.plot(cal_err, cal_rmse, marker="s", color=PAL["blue"], linewidth=2.2, markersize=7)
    ax3.fill_between(cal_err, 0, cal_rmse, color=PAL["blue"], alpha=0.08)
    for xe, yr in zip(cal_err, cal_rmse):
        ax3.annotate(f"{yr:.2f} m", xy=(xe, yr), xytext=(0, 8), textcoords="offset points", ha="center", fontsize=8.3, fontweight="bold", color=PAL["navy"])
    ax3.set_xlabel("RIS Position Calibration Perturbation (cm)", fontsize=9.2)
    ax3.set_ylabel("Target-2 3D RMSE (m)", fontsize=9.2)
    ax3.set_xticks(cal_err)
    ax3.set_ylim(0, 3.0)
    ax3.grid(True, alpha=0.55)
    ax3.spines["top"].set_visible(False)
    ax3.spines["right"].set_visible(False)
    ax3.set_title("(c) A3: RIS Calibration Error Robustness (20 NLoS)", fontsize=9.8, fontweight="bold")

    # (d) A5 UAV Relocation vs Hover Dwell Energy Budget
    dwell_t = np.array(a5["dwell_time_s"])
    hover_e = np.array(a5["hover_energy_kj"])
    cpis = np.array(a5["cpis_per_dwell"])
    reloc_e25 = a5["relocation_energy_kj"][1]  # 25 m -> 0.40 kJ
    reloc_e50 = a5["relocation_energy_kj"][2]  # 50 m -> 0.80 kJ
    x4 = np.arange(len(dwell_t))
    w4 = 0.42
    ax4.bar(x4, hover_e, width=w4, color=PAL["navy"], label="Hover Service Energy (kJ)")
    ax4.bar(x4, np.full_like(hover_e, reloc_e50), bottom=hover_e, width=w4, color=PAL["orange"], label="50 m Relocation Energy (0.80 kJ, 5 s)")
    for xi, he, cpi in zip(x4, hover_e, cpis):
        share = reloc_e50 / (he + reloc_e50) * 100.0
        ax4.text(xi, he + reloc_e50 + 0.35, f"{int(cpi):,} CPIs\n({share:.1f}% reloc.)", ha="center", va="bottom", fontsize=7.5, fontweight="bold", color=PAL["navy"])
    ax4.set_xticks(x4)
    ax4.set_xticklabels([f"{int(t)} s dwell" for t in dwell_t], fontsize=8.8)
    ax4.set_ylabel("Total Session Propulsion Energy (kJ)", fontsize=9.2)
    ax4.set_ylim(0, 14.0)
    ax4.grid(True, axis="y", alpha=0.55)
    ax4.spines["top"].set_visible(False)
    ax4.spines["right"].set_visible(False)
    ax4.legend(loc="upper left", fontsize=7.8)
    ax4.set_title("(d) A5: Propulsion Energy Overhead vs. Hover Dwell", fontsize=9.8, fontweight="bold")

    fig.tight_layout(h_pad=2.1, w_pad=2.0)
    save_fig(fig, "fig6_ablations_robustness", "en")


# ---------------------------------------------------------------------------
# PPT Figure 5 (Chinese): Clean 4-Panel Executive Ablations Summary (A4/A4/A2/A5)
# ---------------------------------------------------------------------------
def plot_ppt_fig5_ablations(ablations: dict) -> None:
    set_style("zh")
    a2 = ablations["a2_prior_sensitivity"]
    a4 = ablations["a4_pareto_roc"]
    a5 = ablations["a5_flight_energy"]

    fig, axes = plt.subplots(1, 4, figsize=(13.6, 3.65))
    ax1, ax2, ax3, ax4 = axes

    # 1. A4 Comm SINR vs Worst-Target PEB
    sinr = np.array(a4["sinr_grid_db"])
    peb = np.array(a4["median_worst_peb_m"])
    ax1.plot(sinr, peb, marker="o", color=PAL["teal"], linewidth=2.2, markersize=6.5)
    for s, p in zip(sinr, peb):
        dx = -11 if s == 13 else (-6 if s == 16 else 0)
        ax1.annotate(f"{p:.3f}", xy=(s, p), xytext=(dx, 7), textcoords="offset points", ha="center", fontsize=7.8, fontweight="bold", color=PAL["navy"])
    ax1.axvline(10, color=PAL["slate"], linestyle=":", lw=1.0)
    ax1.text(10.3, 0.28, "默认10 dB\n(100%可行)", fontsize=7.4, color=PAL["slate"])
    ax1.set_xticks(sinr)
    ax1.set_ylim(0, 0.39)
    ax1.set_xlabel("手机信号质量要求 / dB", fontsize=8.8, fontweight="bold")
    ax1.set_ylabel("最优定位精度 / 米", fontsize=8.8, fontweight="bold")
    ax1.set_title("① 手机要求更高网速的影响", fontsize=9.5, fontweight="bold", color=PAL["navy"])
    ax1.grid(True, alpha=0.55)
    ax1.spines["top"].set_visible(False)
    ax1.spines["right"].set_visible(False)

    # 2. A4 Detection ROC
    snr = np.array(a4["roc_snr_db"])
    pd = np.array(a4["roc_pd"]) * 100.0
    ax2.plot(snr, pd, marker="o", color=PAL["navy"], linewidth=2.1, markersize=4.5)
    ax2.axvspan(14.5, 16.5, color=PAL["teal_light"], alpha=0.85, label="设定安全区")
    ax2.axhline(99.0, color=PAL["teal"], linestyle="--", lw=1.1)
    ax2.annotate("16 dB:\n99.9%抓到", xy=(16, 99.91), xytext=(16.5, 70), fontsize=7.8, fontweight="bold", color=PAL["teal"],
                 arrowprops=dict(arrowstyle="->", color=PAL["teal"], lw=1.0))
    ax2.set_xlim(6, 22)
    ax2.set_ylim(-2, 106)
    ax2.set_xlabel("单波束信号强度 / dB", fontsize=8.8, fontweight="bold")
    ax2.set_ylabel("发现目标概率 (%)", fontsize=8.8, fontweight="bold")
    ax2.set_title("② 信号多强才能稳稳抓到", fontsize=9.5, fontweight="bold", color=PAL["navy"])
    ax2.grid(True, alpha=0.55)
    ax2.spines["top"].set_visible(False)
    ax2.spines["right"].set_visible(False)

    # 3. A2 Prior Uncertainty
    sig = np.array(a2["prior_sigma_m"])
    cap = np.array(a2["t2_capture_rate"]) * 100.0
    rmse = np.array(a2["t2_rmse_m"])
    x3 = np.arange(len(sig))
    bars = ax3.bar(x3, cap, width=0.46, color=[PAL["teal"], PAL["teal"], PAL["rose"]], edgecolor="white")
    for b, c_val, r_val in zip(bars, cap, rmse):
        ax3.text(b.get_x() + b.get_width() / 2, c_val + 2.0, f"{c_val:.1f}%\n(偏{r_val:.2f}m)",
                 ha="center", va="bottom", fontsize=7.4, fontweight="bold", color=PAL["navy"])
    ax3.set_xticks(x3)
    ax3.set_xticklabels([f"猜偏{int(s)}m" for s in sig], fontsize=8.5)
    ax3.set_ylim(0, 118)
    ax3.set_xlabel("初始猜测位置偏差", fontsize=8.8, fontweight="bold")
    ax3.set_ylabel("盲区抓到比例 (%)", fontsize=8.8, fontweight="bold")
    ax3.set_title("③ 初始猜得不准会怎样", fontsize=9.5, fontweight="bold", color=PAL["navy"])
    ax3.grid(True, axis="y", alpha=0.55)
    ax3.spines["top"].set_visible(False)
    ax3.spines["right"].set_visible(False)

    # 4. A5 Flight Energy Overhead
    dwell_t = np.array(a5["dwell_time_s"])
    hover_e = np.array(a5["hover_energy_kj"])
    reloc_e50 = a5["relocation_energy_kj"][2]
    x4 = np.arange(len(dwell_t))
    ax4.bar(x4, hover_e, width=0.48, color=PAL["navy"], label="悬停干活耗电")
    ax4.bar(x4, np.full_like(hover_e, reloc_e50), bottom=hover_e, width=0.48, color=PAL["orange"], label="飞50m换位(5秒)")
    for xi, he in zip(x4, hover_e):
        pct = reloc_e50 / (he + reloc_e50) * 100.0
        ax4.text(xi, he + reloc_e50 + 0.35, f"占{pct:.1f}%", ha="center", va="bottom", fontsize=7.6, fontweight="bold", color=PAL["orange"])
    ax4.set_xticks(x4)
    ax4.set_xticklabels([f"悬停{int(t)}秒" for t in dwell_t], fontsize=8.3)
    ax4.set_ylim(0, 13.8)
    ax4.set_xlabel("悬停工作时长（标换位占比）", fontsize=8.8, fontweight="bold")
    ax4.set_ylabel("总耗电量 / kJ", fontsize=8.8, fontweight="bold")
    ax4.set_title("④ 飞过去换位到底费不费电", fontsize=9.5, fontweight="bold", color=PAL["navy"])
    ax4.grid(True, axis="y", alpha=0.55)
    ax4.spines["top"].set_visible(False)
    ax4.spines["right"].set_visible(False)
    ax4.legend(loc="upper left", fontsize=7.2)

    fig.tight_layout(w_pad=1.5)
    save_fig(fig, "ppt_fig5_ablations", "zh")


def main() -> None:
    by_rm, audit, ablations, gate1, gate2 = load_data()
    print(f"Loaded and verified 7,200 rows from {RESULTS_DIR}")

    # IEEE Journal Figures (English: PDF + EPS + PNG)
    plot_fig1_geometry_ecdf(by_rm, lang="en")
    plot_fig2_main_rcs(by_rm, lang="en")
    plot_fig3_pareto_nlos(by_rm, lang="en")
    plot_fig4_bootstrap_cond(by_rm, lang="en")
    plot_fig5_comm_roc_ieee(ablations)
    plot_fig6_ablations_ieee(ablations)

    # PPT Presentation Figures (Chinese: 300 DPI PNG matched to PPT palette)
    plot_fig1_geometry_ecdf(by_rm, lang="zh")
    plot_fig2_main_rcs(by_rm, lang="zh")
    plot_fig3_pareto_nlos(by_rm, lang="zh")
    plot_fig4_bootstrap_cond(by_rm, lang="zh")
    plot_ppt_fig5_ablations(ablations)

    ieee_files = sorted(p.name for p in IEEE_DIR.iterdir())
    ppt_files = sorted(p.name for p in PPT_DIR.iterdir())
    print(f"Generated {len(ieee_files)} IEEE files in {IEEE_DIR}: {ieee_files}")
    print(f"Generated {len(ppt_files)} PPT files in {PPT_DIR}: {ppt_files}")


if __name__ == "__main__":
    main()
