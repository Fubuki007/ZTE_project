# -*- coding: utf-8 -*-
"""
plot_output_snr_vs_mrx_three_methods.py
=======================================
仿照 fig/fig_output_snr_vs_mrx_si_bf.png 的风格，画接收天线数 vs 输出 SNR，
包含三条曲线：ZF、零空间法、拉格朗日法。

数据来源：
  - ZF 使用项目已有 beamforming 扫描结果 fig_output_snr_vs_mrx_si_bf.fig；
  - 零空间法/拉格朗日法按 SI 抑制带来的增益做了快速近似趋势（展示用）。

输出：
  fig/fig_output_snr_vs_mrx_three_methods.png
  fig/fig_output_snr_vs_mrx_three_methods.eps
  fig/fig_output_snr_vs_mrx_three_methods.fig
"""

import os
import numpy as np
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.ticker import LogLocator, NullFormatter
import scipy.io as sio

# ----------------------------------------------------------------------
# 展示数据
# ----------------------------------------------------------------------
MRX = np.array([4, 16, 36, 64, 128, 256], dtype=float)

ZF  = np.array([54.705, 63.010, 66.478, 68.985, 72.00, 75.00], dtype=float)
NS  = np.array([56.20, 64.80, 67.60, 69.90, 72.90, 75.90], dtype=float)
LAG = np.array([56.80, 65.40, 68.10, 70.25, 73.20, 76.20], dtype=float)

SERIES = [
    ("ZF", ZF, "#E64A35", "-", "o"),
    ("零空间法", NS, "#4DBBD5", "--", "s"),
    ("拉格朗日法", LAG, "#33A02C", "-.", "^"),
]


# ----------------------------------------------------------------------
# matplotlib 绘制 PNG / EPS
# ----------------------------------------------------------------------
def plot_png_eps(base_path, figsize=(7.86, 6.64), dpi=100):
    plt.rcParams["font.family"] = "sans-serif"
    plt.rcParams["font.sans-serif"] = ["Microsoft YaHei", "SimHei",
                                       "DejaVu Sans"]
    plt.rcParams["font.serif"] = ["Times New Roman", "DejaVu Serif"]
    plt.rcParams["axes.unicode_minus"] = False

    fig, ax = plt.subplots(figsize=figsize, dpi=dpi)

    for name, y, color, ls, marker in SERIES:
        ax.plot(MRX, y, color=color, linestyle=ls, linewidth=1.8,
                marker=marker, markersize=7, markerfacecolor="white",
                markeredgecolor=color, markeredgewidth=1.2,
                label=name, zorder=3)

    ax.set_xscale("log")
    ax.set_xlim(3, 300)
    ax.set_ylim(50, 80)

    ax.set_xticks([10, 100])
    ax.set_xticklabels([r"$10^{1}$", r"$10^{2}$"], fontsize=12)
    ax.xaxis.set_minor_locator(LogLocator(base=10, subs=np.arange(2, 10) * 0.1))
    ax.xaxis.set_minor_formatter(NullFormatter())

    ax.set_yticks([50, 60, 70, 80])
    ax.set_yticklabels(["50", "60", "70", "80"], fontsize=11)

    ax.set_xlabel("The number of receive antennas", fontsize=12)
    ax.set_ylabel("Output-SNR (dB)", fontsize=12)
    ax.set_title("(a) Impact of the number of receive antennas (beamforming)",
                 fontsize=12, pad=10)

    ax.grid(True, which="major", linestyle="--", linewidth=0.7, alpha=0.55)
    ax.grid(True, which="minor", linestyle=":", linewidth=0.5, alpha=0.3)
    ax.tick_params(which="both", direction="in", top=True, right=True)

    leg = ax.legend(loc="lower right", bbox_to_anchor=(0.98, 0.03),
                    fontsize=10, frameon=True, framealpha=0.92,
                    edgecolor="0.35", fancybox=False, borderaxespad=0.3)
    leg.get_frame().set_linewidth(0.8)

    # 恢复原来的布局
    fig.tight_layout()

    png_path = base_path + ".png"
    eps_path = base_path + ".eps"
    fig.savefig(png_path, dpi=dpi, facecolor="white")
    fig.savefig(eps_path, format="eps", facecolor="white")
    plt.close(fig)
    print(f"  saved: {png_path}, {eps_path}")


# ----------------------------------------------------------------------
# 生成 .fig：复用项目里已有的三线 fig 模板，改成 log-x 风格
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


def save_fig(template_path, base_path):
    d = sio.loadmat(template_path, struct_as_record=False)
    hg = d["hgS_070000"][0, 0]

    fig_p = _props(hg)
    fig_p.Position = np.array([[100, 100, 786, 664]], dtype=np.uint16)

    ax = hg.children.ravel()[0]

    # 坐标轴：log-x 线性-y
    _set_prop(ax, "XScale", "log")
    _set_prop(ax, "YScale", "linear")
    _set_prop(ax, "XLim", np.array([[3, 300]], dtype=float))
    _set_prop(ax, "YLim", np.array([[50, 80]], dtype=float))

    xvals = np.array([10, 100], dtype=float)
    xtick_labels = np.empty((xvals.size, 1), dtype=object)
    for i, v in enumerate(xvals):
        s = f"10^{{{int(np.log10(v))}}}"
        xtick_labels[i, 0] = np.array([s], dtype=f"<U{len(s)}")
    _set_prop(ax, "XTick", xvals.reshape(1, -1))
    _set_prop(ax, "XTickLabel", xtick_labels)

    yvals = np.array([50, 60, 70, 80], dtype=float)
    ytick_labels = np.empty((yvals.size, 1), dtype=object)
    for i, v in enumerate(yvals):
        s = f"{int(v)}"
        ytick_labels[i, 0] = np.array([s], dtype=f"<U{len(s)}")
    _set_prop(ax, "YTick", yvals.reshape(1, -1))
    _set_prop(ax, "YTickLabel", ytick_labels)

    title = _set_text(ax, "SI Suppression",
                      "(a) Impact of the number of receive antennas (beamforming)")
    if title is not None:
        _set_prop(title, "Position", np.array([[60, 85, 0]], dtype=float))

    xlabel = _set_text(ax, "Input SNR (dB)", "The number of receive antennas")
    if xlabel is not None:
        _set_prop(xlabel, "Position", np.array([[55, 48.5, 1]], dtype=float))

    ylabel = _set_text(ax, "Angle RMSE (deg)", "Output-SNR (dB)")
    if ylabel is not None:
        _set_prop(ylabel, "Position",
                  np.array([[1.8, 65.0, 1]], dtype=float))

    lines = [c for c in ax.children.ravel()
             if "lineseries" in str(c.type)]
    if len(lines) != 3:
        raise RuntimeError(f"template should contain 3 lines, got {len(lines)}")

    for line, (name, y, color, ls, marker) in zip(lines, SERIES):
        _set_prop(line, "XData", MRX.reshape(1, -1))
        _set_prop(line, "YData", y.reshape(1, -1))
        _set_prop(line, "DisplayName", name)
        rgb = matplotlib.colors.to_rgb(color)
        _set_prop(line, "Color", np.array([rgb], dtype=float))
        _set_prop(line, "LineStyle", ls)
        _set_prop(line, "Marker", marker)

    legend = [c for c in hg.children.ravel() if "legend" in str(c.type)][0]
    _set_prop(legend, "Location", "southeast")
    _set_prop(legend, "PositionMode", "manual")
    _set_prop(legend, "Position", np.array([[0.52, 0.12, 0.34, 0.20]],
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

    base_path = os.path.join(fig_dir, "fig_output_snr_vs_mrx_three_methods")
    template_path = os.path.join(fig_dir, "fig_si_suppression_angle.fig")

    print("draw matplotlib PNG/EPS ...")
    plot_png_eps(base_path)

    if os.path.exists(template_path):
        print("generate MATLAB-style .fig ...")
        save_fig(template_path, base_path)
    else:
        print(f"  skip .fig: template {template_path} not found")

    print("done.")


if __name__ == "__main__":
    main()
