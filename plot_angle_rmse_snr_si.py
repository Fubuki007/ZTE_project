# -*- coding: utf-8 -*-
"""
plot_angle_rmse_snr_si.py
=========================
根据用户提供的角度 RMSE 数据绘制“Angle RMSE vs SNR — SI Suppression”对比图。

修改说明:
    1. 传统 ZF 原始数据在 -30~-10 dB 出现“先下降后上升”，按用户的意见作了单调化修正:
       对三条曲线统一使用 cumulative minimum（随 SNR 增大 RMSE 不上升），
       再用 PCHIP 在 log10(RMSE) 域内插值，得到平滑无突刺曲线。
    2. 图例放在 axes 内部（右上），避免图例外置造成大片空白。
    3. 输出 fig / png / eps 三种格式:
       fig/angle_rmse_vs_snr_si_suppression.fig
       fig/angle_rmse_vs_snr_si_suppression.png
       fig/angle_rmse_vs_snr_si_suppression.eps
"""

import os
import numpy as np
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from scipy.interpolate import PchipInterpolator
import scipy.io as sio

# ----------------------------------------------------------------------
# 原始数据
# ----------------------------------------------------------------------
SNR = np.array([-60, -55, -50, -45, -40, -35, -30, -25, -20, -15, -10,
                -5, 0, 5, 10, 15, 20, 25, 30], dtype=float)

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

LAG_RAW = np.array([
    42.7098, 38.7181, 41.9595, 33.3748, 34.4338, 25.7222, 14.6590,
    5.6996, 2.2272, 0.9409, 0.5744, 0.3266, 0.1854, 0.0817,
    0.0805, 0.0620, 0.0609, 0.0606, 0.0609
], dtype=float)

SERIES = [
    ("传统 ZF (不抑制)", ZF_RAW, "#E64A35", "-", "o"),
    ("零空间法", NS_RAW, "#4DBBD5", "--", "s"),
    ("拉格朗日法", LAG_RAW, "#33A02C", "-.", "^"),
]

# 单调化修正: 随 SNR 增加 RMSE 不允许再上升
CORRECTED = {name: np.minimum.accumulate(raw) for name, raw, _, _, _ in SERIES}


def make_dense_curve(snr, values, n=500):
    """在 log10 域用 PCHIP 插值，保证平滑且不产生单调性震荡。"""
    x = np.linspace(snr.min(), snr.max(), n)
    log_y = np.log10(np.maximum(values, 1e-12))
    p = PchipInterpolator(snr, log_y)
    y = np.power(10.0, p(x))
    return x, y


def plot_matplotlib(base_path, png_size=(5.25, 3.89), dpi=100):
    """用 matplotlib 绘制 PNG 和 EPS。"""
    plt.rcParams["font.family"] = "sans-serif"
    plt.rcParams["font.sans-serif"] = ["Microsoft YaHei", "SimHei",
                                       "DejaVu Sans"]
    plt.rcParams["font.serif"] = ["Times New Roman", "DejaVu Serif"]
    plt.rcParams["axes.unicode_minus"] = False
    plt.rcParams["mathtext.fontset"] = "stix"

    fig, ax = plt.subplots(figsize=png_size, dpi=dpi)

    for name, raw, color, ls, marker in SERIES:
        vals = CORRECTED[name]
        xd, yd = make_dense_curve(SNR, vals)
        line, = ax.semilogy(xd, yd, color=color, linestyle=ls,
                            linewidth=1.6, label=name, zorder=3)
        ax.semilogy(SNR, vals, color=color, linestyle="none", marker=marker,
                    markersize=5.0, markerfacecolor="white",
                    markeredgecolor=color, markeredgewidth=1.0, zorder=4)

    ax.set_xlabel("Input SNR (dB)", fontsize=10)
    ax.set_ylabel("Angle RMSE (°)", fontsize=10)
    ax.set_title("Angle RMSE vs SNR  —  SI Suppression Comparison (L=256, MC=100)",
                 fontsize=9, pad=6)

    ax.set_xlim(-63, 33)
    ax.set_ylim(0.04, 100)

    ax.set_xticks(np.arange(-60, 31, 10))
    ax.set_xticklabels([str(v) for v in np.arange(-60, 31, 10)], fontsize=8.5)
    ax.set_yticks([0.1, 1, 10, 100])
    ax.set_yticklabels(["$10^{-1}$", "$10^{0}$", "$10^{1}$", "$10^{2}$"],
                       fontsize=8.5)

    ax.grid(True, which="major", linestyle="-", linewidth=0.7, alpha=0.5)
    ax.grid(True, which="minor", linestyle=":", linewidth=0.5, alpha=0.3)
    ax.tick_params(which="both", direction="in", top=True, right=True)

    # 图例放在图内部，避免外置留白
    leg = ax.legend(loc="upper right", bbox_to_anchor=(0.99, 0.99),
                    fontsize=8, frameon=True, framealpha=0.92,
                    edgecolor="0.35", fancybox=False, borderaxespad=0.35)
    leg.get_frame().set_linewidth(0.7)

    fig.tight_layout()

    png_path = base_path + ".png"
    eps_path = base_path + ".eps"
    fig.savefig(png_path, dpi=dpi, facecolor="white")
    fig.savefig(eps_path, format="eps", facecolor="white")
    plt.close(fig)
    print(f"  saved: {png_path}, {eps_path}")
    return png_path, eps_path


# ----------------------------------------------------------------------
# MATLAB .fig 修改
# ----------------------------------------------------------------------
def get_props(obj):
    p = obj.properties
    if isinstance(p, np.ndarray) and p.size == 1:
        return p.ravel()[0]
    return p


def set_prop(obj, name, value):
    props = get_props(obj)
    setattr(props, name, value)


def set_text_string_under(obj, contains, new_string):
    """在 axes children 中按 String 包含关系查找 text 并替换内容。"""
    for child in obj.children.ravel():
        if "text" not in str(child.type):
            continue
        props = get_props(child)
        s = str(props.String)
        if contains in s:
            set_prop(child, "String", new_string)
            return child
    return None


def _is_mat_struct(x):
    return hasattr(x, "_fieldnames")


def _convert_struct_array(arr):
    """把 scipy 的 mat_struct 对象数组转成 numpy 结构化数组。

    scipy 的 savemat 只有收到 numpy struct array 时才会写出 MATLAB struct array，
    如果直接写 mat_struct / object 数组会把嵌套结构写成 cell，导致 .fig 不兼容。
    """
    if not isinstance(arr, np.ndarray) or arr.size == 0:
        return arr
    flat = arr.ravel()
    if not _is_mat_struct(flat[0]):
        return arr
    fields = list(flat[0]._fieldnames)
    if not fields:
        # scipy 无法写出零字段的 struct array；空 ApplicationData 用空数组代替。
        return np.array([], dtype=float)
    dt = np.dtype([(f, "O") for f in fields])
    out = np.zeros(arr.shape, dtype=dt)
    for idx in np.ndindex(arr.shape):
        src = arr[idx]
        for f in fields:
            v = getattr(src, f)
            out[f][idx] = _convert_value(v)
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
    """把一个标量 mat_struct 转成 1x1 numpy struct array。"""
    return _convert_struct_array(np.array([[obj]]))


def save_matlab_fig(template_path, base_path):
    """基于已有 MATLAB fig 模板生成新的 .fig，避免手写 MATLAB 格式。"""
    d = sio.loadmat(template_path, struct_as_record=False)
    hg = d["hgS_070000"][0, 0]

    # --- 图窗尺寸 ---
    fig_props = get_props(hg)
    fig_props.Position = np.array([[80, 80, 525, 389]], dtype=np.uint16)

    # --- axes 和 lines ---
    ax = hg.children.ravel()[0]
    set_prop(ax, "XLim", np.array([[-63, 33]], dtype=float))
    set_prop(ax, "XTick", np.arange(-60, 31, 10).reshape(1, -1))
    xvals = np.arange(-60, 31, 10)
    xtick_labels = np.empty((xvals.size, 1), dtype=object)
    for i, v in enumerate(xvals):
        xtick_labels[i, 0] = np.array([f"{v}"], dtype=f"<U{len(f'{v}')}")
    set_prop(ax, "XTickLabel", xtick_labels)
    set_prop(ax, "YLim", np.array([[0.04, 100]], dtype=float))
    set_prop(ax, "YTick", np.array([[0.1, 1, 10, 100]], dtype=float))
    ytick_labels = np.empty((4, 1), dtype=object)
    ytick_strs = ["10^{-1}", "10^{0}", "10^{1}", "10^{2}"]
    for i, s in enumerate(ytick_strs):
        ytick_labels[i, 0] = np.array([s], dtype=f"<U{len(s)}")
    set_prop(ax, "YTickLabel", ytick_labels)

    # 标题、x/y 轴标签位置
    title = set_text_string_under(
        ax, "SI Suppression",
        "Angle RMSE vs SNR  --  SI Suppression Comparison (L=256, MC=100)")
    if title is not None:
        set_prop(title, "Position", np.array([[-15, 120, 0]], dtype=float))

    xlabel = set_text_string_under(ax, "Input SNR (dB)", "Input SNR (dB)")
    if xlabel is not None:
        set_prop(xlabel, "Position", np.array([[-15, 0.035, 1]], dtype=float))

    ylabel = set_text_string_under(ax, "Angle RMSE (deg)", "Angle RMSE (°)")
    if ylabel is not None:
        ylabel_mid = np.sqrt(0.04 * 100)
        set_prop(ylabel, "Position",
                 np.array([[-64.5, ylabel_mid, 1]], dtype=float))

    lines = [c for c in ax.children.ravel()
             if "lineseries" in str(c.type)]
    if len(lines) != 3:
        raise RuntimeError(f"template should contain 3 lines, got {len(lines)}")

    for line, (name, raw, color, ls, marker) in zip(lines, SERIES):
        vals = CORRECTED[name]
        set_prop(line, "XData", SNR.reshape(1, -1))
        set_prop(line, "YData", vals.reshape(1, -1))
        set_prop(line, "DisplayName", name)
        # 模板中的颜色已经是 ZF/NS/Lag 三色，这里显式保留
        rgb = matplotlib.colors.to_rgb(color)
        set_prop(line, "Color", np.array([rgb], dtype=float))

        style_map = {"-": "-", "--": "--", "-.": "-."}
        set_prop(line, "LineStyle", style_map[ls])
        set_prop(line, "Marker", marker)

    # --- 图例: 从 northeastoutside 改为内部 northeast ---
    legend = [c for c in hg.children.ravel() if "legend" in str(c.type)][0]
    leg_props = get_props(legend)
    set_prop(legend, "Location", "northeast")
    set_prop(legend, "PositionMode", "manual")
    set_prop(legend, "Position", np.array([[0.42, 0.60, 0.26, 0.16]],
                                          dtype=float))
    set_prop(legend, "String", np.array(
        [name for name, _, _, _, _ in SERIES], dtype=object).reshape(1, -1))

    # scipy 无法写 MatlabFunction，去掉 legend 的反序列化回调
    leg_app = get_props(legend).ApplicationData
    if isinstance(leg_app, np.ndarray) and leg_app.size == 1:
        leg_app = leg_app.ravel()[0]
    if hasattr(leg_app, "_fieldnames") and hasattr(leg_app, "PostDeserializeFcn"):
        leg_app.PostDeserializeFcn = np.array([], dtype=float)

    # --- 保存 .fig ---
    # 先转成 numpy struct array 再写 MAT 文件，才能保留 MATLAB 的 struct 层级
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

    base_path = os.path.join(fig_dir, "angle_rmse_vs_snr_si_suppression")
    template_path = os.path.join(fig_dir, "fig_si_suppression_angle.fig")

    if not os.path.exists(template_path):
        raise FileNotFoundError(
            f"template not found: {template_path}\n"
            "请确认 fig/fig_si_suppression_angle.fig 存在。")

    print("generate PNG/EPS ...")
    plot_matplotlib(base_path)
    print("generate MATLAB .fig ...")
    save_matlab_fig(template_path, base_path)
    print("done.")


if __name__ == "__main__":
    main()
