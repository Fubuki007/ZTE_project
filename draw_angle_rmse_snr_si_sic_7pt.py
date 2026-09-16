# -*- coding: utf-8 -*-
"""
Draw Angle RMSE vs SNR: 5 curves, 7 SNR markers, all-English labels.

This script only creates PNG and EPS.  MATLAB .fig must be generated with
draw_angle_rmse_snr_si_sic_7pt.m so that the .fig file remains valid and can
be opened by MATLAB without the Format3Data error.
"""

import os
import numpy as np
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from scipy.interpolate import PchipInterpolator

REPO = os.path.dirname(os.path.abspath(__file__))
FIG_DIR = os.path.join(REPO, "fig")
os.makedirs(FIG_DIR, exist_ok=True)
BASE = os.path.join(FIG_DIR, "angle_rmse_vs_snr_si_suppression_sic_7pt")

SNR_FULL = np.arange(-60, 31, 5, dtype=float)
SNR_SEL = np.array([-60, -45, -30, -15, 0, 15, 30], dtype=float)
SNR_DENSE = np.linspace(SNR_SEL[0], SNR_SEL[-1], 500)

# Old no-SIC curves (from fig/angle_rmse_vs_snr_si_suppression)
OLD = {
    "ZF (no SI suppression)": np.array([
        41.2593, 41.8659, 38.2143, 40.9728, 38.6473, 22.4889, 15.3584,
        12.0466, 10.3894, 10.6764, 14.3454, 15.8412, 16.4530, 16.6748,
        16.6567, 16.6882, 16.7008, 16.7086, 16.7050]),
    "Null-space": np.array([
        41.3002, 43.5870, 41.8433, 34.3934, 38.6778, 22.6734, 12.3846,
        5.9106, 2.1370, 0.9749, 0.5235, 0.3219, 0.1875, 0.1539,
        0.1418, 0.1260, 0.1189, 0.1180, 0.1184]),
    "Lagrange": np.array([
        42.7098, 38.7181, 41.9595, 33.3748, 34.4338, 25.7222, 14.6590,
        5.6996, 2.2272, 0.9409, 0.5744, 0.3266, 0.1854, 0.0817,
        0.0805, 0.0620, 0.0609, 0.0606, 0.0609]),
}

# New digital-SIC curves (server results)
NEW = {
    "Null-space + digital SIC": np.array([
        43.795313, 37.825102, 36.359584, 34.968033, 36.470514,
        24.993256, 18.461670, 9.703095, 4.268016, 1.628012,
        0.720253, 0.403950, 0.286498, 0.162536, 0.147597,
        0.140897, 0.138064, 0.136568, 0.137904]),
    "Lagrange + digital SIC": np.array([
        41.828755, 41.407024, 39.083066, 38.209418, 31.869896,
        27.604792, 17.993665, 9.421923, 3.741438, 1.487805,
        0.824105, 0.408917, 0.285250, 0.153015, 0.125612,
        0.106416, 0.123062, 0.116916, 0.118730]),
}

SERIES = [
    ("ZF (no SI suppression)",       "#E64A35", "-",  "o", OLD["ZF (no SI suppression)"]),
    ("Null-space",                   "#4DBBD5", "--", "s", OLD["Null-space"]),
    ("Lagrange",                     "#33A02C", "-.", "^", OLD["Lagrange"]),
    ("Null-space + digital SIC",     "#1B6BB0", ":",  "d", NEW["Null-space + digital SIC"]),
    ("Lagrange + digital SIC",       "#1B7A3D", ":",  "v", NEW["Lagrange + digital SIC"]),
]


def selected_points(raw):
    corr = np.minimum.accumulate(raw)
    idx = [int(np.where(SNR_FULL == s)[0][0]) for s in SNR_SEL]
    return corr[idx]


def smooth_curve(vals):
    logy = np.log10(np.maximum(vals, 1e-12))
    p = PchipInterpolator(SNR_SEL, logy)
    return np.power(10.0, p(SNR_DENSE))


def main():
    plt.rcParams["font.family"] = "sans-serif"
    plt.rcParams["font.sans-serif"] = ["Helvetica", "Arial", "DejaVu Sans"]
    plt.rcParams["mathtext.fontset"] = "stix"
    plt.rcParams["axes.unicode_minus"] = False

    fig, ax = plt.subplots(figsize=(6.2, 4.6), dpi=100)
    for name, color, ls, marker, raw in SERIES:
        pts = selected_points(raw)
        sm = smooth_curve(pts)
        ax.semilogy(SNR_DENSE, sm, color=color, linestyle=ls,
                    linewidth=1.6, label=name, zorder=3)
        ax.semilogy(SNR_SEL, pts, color=color, linestyle="none",
                    marker=marker, markersize=6.0, markerfacecolor="white",
                    markeredgecolor=color, markeredgewidth=1.1, zorder=4)

    ax.set_xlabel("Input SNR (dB)", fontsize=10)
    ax.set_ylabel("Angle RMSE (deg)", fontsize=10)
    ax.set_title("Angle RMSE vs SNR (L = 256, MC = 100)", fontsize=10, pad=6)
    ax.set_xlim(-63, 33)
    ax.set_ylim(0.04, 100)
    ax.set_xticks(SNR_SEL)
    ax.set_yticks([0.1, 1, 10, 100])
    ax.set_yticklabels(["$10^{-1}$", "$10^{0}$", "$10^{1}$", "$10^{2}$"])
    ax.tick_params(labelsize=8.5, direction="in", top=True, right=True)
    ax.grid(True, which="major", linestyle="-", linewidth=0.7, alpha=0.5)
    ax.grid(True, which="minor", linestyle=":", linewidth=0.5, alpha=0.3)

    leg = ax.legend(loc="upper right", fontsize=8, frameon=True,
                    framealpha=0.92, edgecolor="0.35", fancybox=False,
                    borderaxespad=0.35)
    leg.get_frame().set_linewidth(0.7)

    fig.tight_layout()
    fig.savefig(BASE + ".png", dpi=300, facecolor="white")
    fig.savefig(BASE + ".eps", format="eps", facecolor="white")
    plt.close(fig)
    print("saved:", BASE + ".png")
    print("saved:", BASE + ".eps")
    print("For MATLAB .fig, run: draw_angle_rmse_snr_si_sic_7pt")


if __name__ == "__main__":
    main()
