# -*- coding: utf-8 -*-
"""
plot_rmse_snr_zf_ns_smooth_all.py
=================================
根据用户提供的三组 RMSE 数据，分别画 Angle / Velocity / Range 三张平滑图：
  - 只画 ZF 和 Null-space；
  - 全英文；
  - 标记点只保留 7 个：-60, -45, -30, -15, 0, 15, 30 dB；
  - 对数据做 cummin + log10 域 PCHIP 平滑；
  - 每张图输出 .fig 和 .png。

输出：
  fig/angle_rmse_vs_snr_zf_ns_smooth.png/.fig
  fig/velocity_rmse_vs_snr_zf_ns_smooth.png/.fig
  fig/range_rmse_vs_snr_zf_ns_smooth.png/.fig
"""

import os
import numpy as np
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from scipy.interpolate import PchipInterpolator
import scipy.io as sio

# ----------------------------------------------------------------------
# 数据
# ----------------------------------------------------------------------
SNR = np.arange(-60, 31, 5, dtype=float)

RANGE_ZF = np.array([
    500.0, 500.0, 500.0, 500.0, 500.0, 500.0, 141.8456,
    141.8456, 141.8456, 141.8456, 141.8456, 141.8456, 141.8456, 141.8456,
    141.8456, 141.8456, 141.8456, 141.8456, 141.8456
], dtype=float)
RANGE_NS = np.array([
    500.0, 500.0, 500.0, 500.0, 100.0, 1.0, 0.0110,
    0.0075, 0.0074, 0.0075, 0.0068, 0.0069, 0.0070, 0.0069, 0.0069,
    0.0070, 0.0070, 0.0070, 0.0070
], dtype=float)

ANGLE_ZF = np.array([
    41.2593, 41.8659, 38.2143, 40.9728, 38.6473, 22.4889, 15.3584,
    12.0466, 10.3894, 10.6764, 14.3454, 15.8412, 16.4530, 16.6748,
    16.6567, 16.6882, 16.7008, 16.7086, 16.7050
], dtype=float)
ANGLE_NS = np.array([
    41.3002, 43.5870, 41.8433, 34.3934, 38.6778, 22.6734, 12.3846,
    5.9106, 2.1370, 0.9749, 0.5235, 0.3219, 0.1875, 0.1539,
    0.1418, 0.1260, 0.1189, 0.1180, 0.1184
], dtype=float)

VELOCITY_ZF = np.array([
    150.0, 150.0, 110.0, 95.0, 95.0, 95.0, 10.6770,
    10.6810, 10.6779, 10.6793, 10.6781, 10.6780, 10.6782, 10.6781,
    10.6781, 10.6781, 10.6781, 10.6781, 10.6781
], dtype=float)
VELOCITY_NS = np.array([
    150.0, 150.0, 110.0, 95.0, 30.0, 5.0, 0.3225,
    0.2221, 0.2267, 0.2316, 0.2284, 0.2279, 0.2275, 0.2275,
    0.2276, 0.2275, 0.2277, 0.2277, 0.2277
], dtype=float)

DATASETS = [
    dict(
        name="angle",
        title="Angle RMSE vs SNR (L = 256, MC = 100)",
        ylabel="Angle RMSE (deg)",
        zf=ANGLE_ZF,
        ns=ANGLE_NS,
        ylim=(0.04, 100),
        yticks=[0.1, 1, 10, 100],
    ),
    dict(
        name="velocity",
        title="Velocity RMSE vs SNR (L = 256, MC = 100)",
        ylabel="Velocity RMSE (m/s)",
        zf=VELOCITY_ZF,
        ns=VELOCITY_NS,
        ylim=(0.1, 1000),
        yticks=[0.1, 1, 10, 100, 1000],
    ),
    dict(
        name="range",
        title="Range RMSE vs SNR (L = 256, MC = 100)",
        ylabel="Range RMSE (m)",
        zf=RANGE_ZF,
        ns=RANGE_NS,
        ylim=(0.005, 1000),
        yticks=[0.01, 0.1, 1, 10, 100, 1000],
    ),
]

MARKER_SNR = np.arange(-60, 31, 15, dtype=float)

COLORS = {
    "ZF": "#E64A35",
    "NS": "#4DBBD5",
}

SERIES_DEF = [
    ("ZF (no SI suppression)", "ZF", "-", "o"),
    ("Null-space", "NS", "--", "s"),
]


def clean(values):
    return np.minimum.accumulate(values)


def smooth_curve(snr, values, n=500):
    x = np.linspace(snr.min(), snr.max(), n)
    log_y = np.log10(np.maximum(values, 1e-12))
    p = PchipInterpolator(snr, log_y)
    return x, np.power(10.0, p(x))


# ----------------------------------------------------------------------
# matplotlib PNG
# ----------------------------------------------------------------------
def draw_png(base_path, data, figsize=(8.56, 6.26), dpi=100):
    plt.rcParams["font.family"] = "sans-serif"
    plt.rcParams["font.sans-serif"] = ["Arial", "DejaVu Sans"]
    plt.rcParams["axes.unicode_minus"] = False

    zf_c = clean(data["zf"])
    ns_c = clean(data["ns"])
    values = {"ZF": zf_c, "NS": ns_c}

    fig, ax = plt.subplots(figsize=figsize, dpi=dpi)

    for label, key, ls, marker in SERIES_DEF:
        vals = values[key]
        xd, yd = smooth_curve(SNR, vals)
        ax.semilogy(xd, yd, color=COLORS[key], linestyle=ls, linewidth=2.0,
                    label=label, zorder=3)
        mask = np.isin(SNR, MARKER_SNR)
        ax.semilogy(SNR[mask], vals[mask], color=COLORS[key], linestyle="none",
                    marker=marker, markersize=6, markerfacecolor="white",
                    markeredgecolor=COLORS[key], markeredgewidth=1.2, zorder=4)

    ax.set_xlabel("Input SNR (dB)", fontsize=12)
    ax.set_ylabel(data["ylabel"], fontsize=12)
    ax.set_title(data["title"], fontsize=13, pad=10)

    ax.set_xlim(-63, 33)
    ax.set_ylim(*data["ylim"])
    ax.set_xticks(np.arange(-60, 31, 15))
    ax.set_xticklabels([str(v) for v in np.arange(-60, 31, 15)], fontsize=10)
    ax.set_yticks(data["yticks"])
    ax.set_yticklabels([f"$10^{{{int(np.log10(v))}}}$" for v in data["yticks"]],
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
# MATLAB .fig
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


def draw_fig(base_path, data, template_path):
    d = sio.loadmat(template_path, struct_as_record=False)
    hg = d["hgS_070000"][0, 0]

    _set_prop(hg, "Position", np.array([[100, 100, 856, 626]], dtype=np.uint16))

    ax = hg.children.ravel()[0]
    _set_prop(ax, "XLim", np.array([[-63, 33]], dtype=float))
    _set_prop(ax, "YLim", np.array([data["ylim"]], dtype=float))

    xvals = np.arange(-60, 31, 15)
    xtick_labels = np.empty((xvals.size, 1), dtype=object)
    for i, v in enumerate(xvals):
        s = f"{int(v)}"
        xtick_labels[i, 0] = np.array([s], dtype=f"<U{len(s)}")
    _set_prop(ax, "XTick", xvals.reshape(1, -1))
    _set_prop(ax, "XTickLabel", xtick_labels)

    yvals = np.array(data["yticks"], dtype=float)
    ytick_labels = np.empty((yvals.size, 1), dtype=object)
    for i, y in enumerate(yvals):
        s = f"10^{{{int(np.log10(y))}}}"
        ytick_labels[i, 0] = np.array([s], dtype=f"<U{len(s)}")
    _set_prop(ax, "YTick", yvals.reshape(1, -1))
    _set_prop(ax, "YTickLabel", ytick_labels)

    title = _set_text(ax, "SI Suppression", data["title"])
    if title is not None:
        _set_prop(title, "Position", np.array([[-15, data["ylim"][1] * 1.3, 0]],
                                              dtype=float))

    xlabel = _set_text(ax, "Input SNR (dB)", "Input SNR (dB)")
    if xlabel is not None:
        _set_prop(xlabel, "Position", np.array([[-15, data["ylim"][0] * 0.75, 1]],
                                               dtype=float))

    ylabel = _set_text(ax, "Angle RMSE (deg)", data["ylabel"])
    if ylabel is not None:
        _set_prop(ylabel, "Position",
                  np.array([[-68, np.sqrt(data["ylim"][0] * data["ylim"][1]), 1]],
                           dtype=float))

    lines = [c for c in ax.children.ravel() if "lineseries" in str(c.type)]
    if len(lines) != 2:
        raise RuntimeError(f"template should contain 2 lines, got {len(lines)}")

    zf_c = clean(data["zf"])
    ns_c = clean(data["ns"])
    values = {"ZF": zf_c, "NS": ns_c}

    for line, (_, key, ls, _) in zip(lines, SERIES_DEF):
        xd, yd = smooth_curve(SNR, values[key], n=400)
        _set_prop(line, "XData", xd.reshape(1, -1))
        _set_prop(line, "YData", yd.reshape(1, -1))
        _set_prop(line, "DisplayName", _get_label(key))
        rgb = matplotlib.colors.to_rgb(COLORS[key])
        _set_prop(line, "Color", np.array([rgb], dtype=float))
        _set_prop(line, "LineStyle", ls)
        _set_prop(line, "Marker", "none")

    legend = [c for c in hg.children.ravel() if "legend" in str(c.type)][0]
    _set_prop(legend, "Location", "northeast")
    _set_prop(legend, "PositionMode", "manual")
    _set_prop(legend, "Position", np.array([[0.60, 0.62, 0.36, 0.20]],
                                           dtype=float))
    _set_prop(legend, "String", np.array(
        [_get_label(key) for _, key, _, _ in SERIES_DEF],
        dtype=object).reshape(1, -1))

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


def _get_label(key):
    return "ZF (no SI suppression)" if key == "ZF" else "Null-space"


def main():
    repo_dir = os.path.dirname(os.path.abspath(__file__))
    fig_dir = os.path.join(repo_dir, "fig")
    os.makedirs(fig_dir, exist_ok=True)
    template_path = os.path.join(fig_dir, "fig_si_suppression_angle_zf_null.fig")

    for data in DATASETS:
        base_path = os.path.join(
            fig_dir, f"{data['name']}_rmse_vs_snr_zf_ns_smooth")
        print(f"draw {data['name']} ...")
        draw_png(base_path, data)
        draw_fig(base_path, data, template_path)

    print("done.")


if __name__ == "__main__":
    main()
