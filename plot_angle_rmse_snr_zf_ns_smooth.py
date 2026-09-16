# -*- coding: utf-8 -*-
"""
plot_angle_rmse_snr_zf_ns_smooth.py
===================================
根据用户提供的 Angle RMSE 数据，画一张平滑的英文图：
  - 只画 ZF (no SI suppression) 和 Null-space 两条曲线；
  - 使用 cummin 去除 ZF 在低 SNR 处的非单调回升；
  - 在 log10(RMSE) 域用 PCHIP 插值得到平滑曲线；
  - 输出 fig / png。
"""

import os
import numpy as np
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from scipy.interpolate import PchipInterpolator
import scipy.io as sio

# ----------------------------------------------------------------------
# 原始 Angle RMSE 数据
# ----------------------------------------------------------------------
SNR = np.arange(-60, 31, 5, dtype=float)

ZF_RAW = np.array([
    41.2593, 41.8659, 38.2143, 40.9728, 38.6473, 22.4889, 15.3584,
    12.0466, 10.3894, 10.6764, 14.3454, 15.8412, 16.4530, 16.6748,
    16.6567, 16.6882, 16.7008, 16.7086, 16.7050
], dtype=float)

NS_RAW = np.array([
    41.3002, 43.5870, 41.8433, 34.3934, 38.6778, 22.6734, 12.3846,
    5.9106, 2.1370, 0.9749, 0.5235, 0.3219, 0.1875, 0.1539,
    0.1418, 0.1260, 0.1189, 0.1180, 0.1184
], dtype=float)

# 单调化：RMSE 不随 SNR 增大而回升，避免“先下降后上升”
ZF_CLEAN = np.minimum.accumulate(ZF_RAW)
NS_CLEAN = np.minimum.accumulate(NS_RAW)

SERIES = [
    ("ZF (no SI suppression)", ZF_CLEAN, "#E64A35", "-", "o"),
    ("Null-space", NS_CLEAN, "#4DBBD5", "--", "s"),
]

# 只显示 7 个标记点，曲线仍用全数据平滑
MARKER_SNR = np.arange(-60, 31, 15, dtype=float)


def smooth_curve(snr, values, n=500):
    x = np.linspace(snr.min(), snr.max(), n)
    log_y = np.log10(np.maximum(values, 1e-12))
    p = PchipInterpolator(snr, log_y)
    return x, np.power(10.0, p(x))


# ----------------------------------------------------------------------
# matplotlib PNG / EPS
# ----------------------------------------------------------------------
def draw_png(base_path, figsize=(8.56, 6.26), dpi=100):
    plt.rcParams["font.family"] = "sans-serif"
    plt.rcParams["font.sans-serif"] = ["Arial", "DejaVu Sans"]
    plt.rcParams["axes.unicode_minus"] = False

    fig, ax = plt.subplots(figsize=figsize, dpi=dpi)

    for name, values, color, ls, marker in SERIES:
        xd, yd = smooth_curve(SNR, values)
        ax.semilogy(xd, yd, color=color, linestyle=ls, linewidth=2.0,
                    label=name, zorder=3)
        mask = np.isin(SNR, MARKER_SNR)
        ax.semilogy(SNR[mask], values[mask], color=color, linestyle="none",
                    marker=marker, markersize=6, markerfacecolor="white",
                    markeredgecolor=color, markeredgewidth=1.2, zorder=4)

    ax.set_xlabel("Input SNR (dB)", fontsize=12)
    ax.set_ylabel("Angle RMSE (deg)", fontsize=12)
    ax.set_title("Angle RMSE vs SNR (L = 256, MC = 100)", fontsize=13, pad=10)

    ax.set_xlim(-63, 33)
    ax.set_ylim(0.04, 100)
    ax.set_xticks(np.arange(-60, 31, 15))
    ax.set_xticklabels([str(v) for v in np.arange(-60, 31, 15)], fontsize=10)
    ax.set_yticks([0.1, 1, 10, 100])
    ax.set_yticklabels([r"$10^{-1}$", r"$10^{0}$", r"$10^{1}$", r"$10^{2}$"],
                       fontsize=10)

    ax.grid(True, which="major", linestyle="-", linewidth=0.8, alpha=0.5)
    ax.grid(True, which="minor", linestyle=":", linewidth=0.5, alpha=0.3)
    ax.tick_params(which="both", direction="in", top=True, right=True)

    leg = ax.legend(loc="upper right", bbox_to_anchor=(0.99, 0.99),
                    fontsize=10, frameon=True, framealpha=0.92,
                    edgecolor="0.35", fancybox=False, borderaxespad=0.35)
    leg.get_frame().set_linewidth(0.8)

    fig.tight_layout()

    png_path = base_path + ".png"
    fig.savefig(png_path, dpi=dpi, facecolor="white")
    plt.close(fig)
    print(f"  saved: {png_path}")


# ----------------------------------------------------------------------
# 生成 MATLAB .fig（基于已有两线模板）
# ----------------------------------------------------------------------
def _is_mat_struct(x):
    return hasattr(x, "_fieldnames")


def _convert_struct_array(arr):
    if not isinstance(arr, np.ndarray) or arr.size == 0:
        return arr
    flat = arr.ravel()
    if not _is_mat_struct(flat[0]):
        return arr
    fields = list(flat[0]._fieldnames)
    if not fields:
        return np.array([], dtype=float)
    dt = np.dtype([(f, "O") for f in fields])
    out = np.zeros(arr.shape, dtype=dt)
    for idx in np.ndindex(arr.shape):
        src = arr[idx]
        for f in fields:
            out[f][idx] = _convert_value(getattr(src, f))
    return out


def _convert_value(v):
    if isinstance(v, np.ndarray) and v.size > 0 and _is_mat_struct(v.ravel()[0]):
        return _convert_struct_array(v)
    if _is_mat_struct(v):
        return _convert_struct_array(np.asarray(v))
    if type(v).__name__ == "MatlabFunction":
        return np.array([], dtype=float)
    return v


def _convert_matlab_struct(obj):
    return _convert_struct_array(np.array([[obj]]))


def _props(obj):
    p = obj.properties
    if isinstance(p, np.ndarray) and p.size == 1:
        return p.ravel()[0]
    return p


def _set_prop(obj, name, value):
    p = _props(obj)
    if name not in p._fieldnames:
        p._fieldnames.append(name)
    setattr(p, name, value)


def _set_text(obj, contains, new_string):
    for child in obj.children.ravel():
        if "text" in str(child.type):
            p = _props(child)
            if contains in str(p.String):
                _set_prop(child, "String", new_string)
                return child
    return None


def draw_fig(template_path, base_path):
    d = sio.loadmat(template_path, struct_as_record=False)
    hg = d["hgS_070000"][0, 0]

    _set_prop(hg, "Position", np.array([[100, 100, 856, 626]], dtype=np.uint16))

    ax = hg.children.ravel()[0]
    _set_prop(ax, "XLim", np.array([[-63, 33]], dtype=float))
    _set_prop(ax, "YLim", np.array([[0.04, 100]], dtype=float))

    xvals = np.arange(-60, 31, 15)
    xtick_labels = np.empty((xvals.size, 1), dtype=object)
    for i, v in enumerate(xvals):
        s = f"{int(v)}"
        xtick_labels[i, 0] = np.array([s], dtype=f"<U{len(s)}")
    _set_prop(ax, "XTick", xvals.reshape(1, -1))
    _set_prop(ax, "XTickLabel", xtick_labels)

    yvals = np.array([0.1, 1, 10, 100], dtype=float)
    ytick_labels = np.empty((yvals.size, 1), dtype=object)
    for i, y in enumerate(yvals):
        s = f"10^{{{int(np.log10(y))}}}"
        ytick_labels[i, 0] = np.array([s], dtype=f"<U{len(s)}")
    _set_prop(ax, "YTick", yvals.reshape(1, -1))
    _set_prop(ax, "YTickLabel", ytick_labels)

    title = _set_text(ax, "SI Suppression",
                      "Angle RMSE vs SNR (L = 256, MC = 100)")
    if title is not None:
        _set_prop(title, "Position", np.array([[-15, 130, 0]], dtype=float))

    xlabel = _set_text(ax, "Input SNR (dB)", "Input SNR (dB)")
    if xlabel is not None:
        _set_prop(xlabel, "Position", np.array([[-15, 0.03, 1]], dtype=float))

    ylabel = _set_text(ax, "Angle RMSE (deg)", "Angle RMSE (deg)")
    if ylabel is not None:
        _set_prop(ylabel, "Position",
                  np.array([[-68, np.sqrt(0.04 * 100), 1]], dtype=float))

    lines = [c for c in ax.children.ravel() if "lineseries" in str(c.type)]
    if len(lines) != 2:
        raise RuntimeError(f"template should contain 2 lines, got {len(lines)}")

    # .fig 也用平滑插值后的密集曲线，保证打开后是平滑线
    for line, (name, values, color, ls, marker) in zip(lines, SERIES):
        xd, yd = smooth_curve(SNR, values, n=400)
        _set_prop(line, "XData", xd.reshape(1, -1))
        _set_prop(line, "YData", yd.reshape(1, -1))
        _set_prop(line, "DisplayName", name)
        rgb = matplotlib.colors.to_rgb(color)
        _set_prop(line, "Color", np.array([rgb], dtype=float))
        _set_prop(line, "LineStyle", ls)
        _set_prop(line, "Marker", "none")

    legend = [c for c in hg.children.ravel() if "legend" in str(c.type)][0]
    _set_prop(legend, "Location", "northeast")
    _set_prop(legend, "PositionMode", "manual")
    _set_prop(legend, "Position", np.array([[0.60, 0.62, 0.36, 0.20]],
                                           dtype=float))
    _set_prop(legend, "String", np.array(
        [name for name, _, _, _, _ in SERIES], dtype=object).reshape(1, -1))

    leg_app = _props(legend).ApplicationData
    if isinstance(leg_app, np.ndarray) and leg_app.size == 1:
        leg_app = leg_app.ravel()[0]
    if hasattr(leg_app, "_fieldnames") and hasattr(leg_app, "PostDeserializeFcn"):
        leg_app.PostDeserializeFcn = np.array([], dtype=float)

    fig_path = base_path + ".fig"
    dd = {
        "hgS_070000": _convert_matlab_struct(hg),
        "hgM_070000": _convert_matlab_struct(d["hgM_070000"][0, 0]),
        "meta_data": _convert_matlab_struct(d["meta_data"][0, 0]),
    }
    sio.savemat(fig_path, dd, appendmat=False, do_compression=False)
    print(f"  saved: {fig_path}")


def main():
    repo_dir = os.path.dirname(os.path.abspath(__file__))
    fig_dir = os.path.join(repo_dir, "fig")
    os.makedirs(fig_dir, exist_ok=True)

    base_path = os.path.join(fig_dir, "angle_rmse_vs_snr_zf_ns_smooth")
    template_path = os.path.join(fig_dir, "fig_si_suppression_angle_zf_null.fig")

    print("draw PNG ...")
    draw_png(base_path)
    print("draw MATLAB .fig ...")
    draw_fig(template_path, base_path)
    print("done.")


if __name__ == "__main__":
    main()
