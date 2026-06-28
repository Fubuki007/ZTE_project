"""
task5_plot_nature.py
Nature 期刊风格: Processing Gain (dB) vs N_rx / N_s / L 三幅图
三种预编码方案 (ZF / Nullspace / Lagrange) 三条曲线
"""
import json
import math
import os
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
import matplotlib.ticker as ticker
import numpy as np

# ============================================================
# Nature 期刊风格设置
# ============================================================
plt.rcParams.update({
    'font.family': 'sans-serif',
    'font.sans-serif': ['Arial', 'Helvetica', 'DejaVu Sans'],
    'font.size': 8,
    'axes.titlesize': 9,
    'axes.labelsize': 8,
    'xtick.labelsize': 7,
    'ytick.labelsize': 7,
    'legend.fontsize': 7,
    'figure.dpi': 300,
    'savefig.dpi': 300,
    'savefig.bbox': 'tight',
    'savefig.pad_inches': 0.05,
    'axes.linewidth': 0.5,
    'xtick.major.width': 0.5,
    'ytick.major.width': 0.5,
    'xtick.major.size': 3,
    'ytick.major.size': 3,
    'xtick.minor.size': 1.5,
    'ytick.minor.size': 1.5,
    'lines.linewidth': 1.2,
    'lines.markersize': 4,
})

# Nature 期刊推荐配色 (色盲友好)
NATURE_COLORS = {
    'ZF':        '#E64B35',  # 红
    'Nullspace': '#4DBBD5',  # 蓝
    'Lagrange':  '#00A087',  # 绿
}
NATURE_MARKERS = {
    'ZF':        'o',
    'Nullspace': 's',
    'Lagrange':  '^',
}

# ============================================================
# 数据目录
# ============================================================
# 使用脚本所在目录的相对路径, 兼容 C:/D: 盘迁移
_script_dir = os.path.dirname(os.path.abspath(__file__))
data_dir = os.path.join(_script_dir, 'task5_results')
out_dir = data_dir  # 图片也放在这里

def load_json(fname):
    with open(os.path.join(data_dir, fname), 'r', encoding='utf-8') as f:
        return json.load(f)

def make_figure(data, xlabel, ylabel, title, out_name):
    """
    生成单幅 Nature 风格折线图
    """
    fig, ax = plt.subplots(figsize=(3.5, 2.6))  # Nature 单栏宽度 ≈ 8.6cm ≈ 3.4in
    
    x = np.array(data['labels'])
    series = data['series']
    
    for name, y in series.items():
        y = np.array(y)
        color = NATURE_COLORS.get(name, '#333333')
        marker = NATURE_MARKERS.get(name, 'o')
        ax.plot(x, y, color=color, marker=marker, label=name,
                linewidth=1.2, markersize=4, markeredgewidth=0.5,
                markeredgecolor='white', markerfacecolor=color,
                clip_on=True)
    
    # 坐标轴标签
    ax.set_xlabel(xlabel, fontweight='normal')
    ax.set_ylabel(ylabel, fontweight='normal')
    ax.set_title(title, fontweight='bold', pad=6)
    
    # 网格 (极淡)
    ax.grid(True, alpha=0.15, linewidth=0.3)
    ax.set_axisbelow(True)
    
    # 图例
    ax.legend(frameon=True, edgecolor='#cccccc', facecolor='white',
              framealpha=0.9, loc='lower right', borderpad=0.4,
              handlelength=1.5, handletextpad=0.5)
    
    # X 轴对数刻度 (base=10, 标签显示 10^1 10^2 ...)
    x_range = max(x) / max(min(x), 1)
    if x_range > 5:
        ax.set_xscale('log', base=10)
        lo = int(np.floor(np.log10(min(x))))
        hi = int(np.ceil(np.log10(max(x))))
        tick_vals = [10 ** e for e in range(lo, hi + 1)]
        tick_labels = [f'$10^{{{e}}}$' for e in range(lo, hi + 1)]
        ax.set_xticks(tick_vals)
        ax.set_xticklabels(tick_labels)
        pad = 0.05
        ax.set_xlim(10 ** (np.log10(min(x)) - pad),
                    10 ** (np.log10(max(x)) + pad))
        ax.xaxis.set_minor_formatter(ticker.NullFormatter())
    
    # 紧凑布局
    fig.tight_layout(pad=0.8)
    
    # 保存 PNG
    png_path = os.path.join(out_dir, out_name + '.png')
    fig.savefig(png_path, dpi=300)
    plt.close(fig)
    print(f'  ✓ {out_name}.png')

# ============================================================
# Fig 1: Output SNR vs 接收天线数 N_rx
# ============================================================
data1 = load_json('snr_vs_nrx.json')
make_figure(
    data1,
    xlabel=r'Number of Receive Antennas  $N_\mathrm{rx}$',
    ylabel=r'Output SNR (dB)',
    title='Output SNR vs Receive Array Size',
    out_name='fig1_snr_vs_nrx'
)

# ============================================================
# Fig 2: Output SNR vs 子载波数 N_s
# ============================================================
data2 = load_json('snr_vs_ns.json')
make_figure(
    data2,
    xlabel=r'Number of Subcarriers  $N_\mathrm{s}$',
    ylabel=r'Output SNR (dB)',
    title='Output SNR vs Number of Subcarriers',
    out_name='fig2_snr_vs_ns'
)

# ============================================================
# Fig 3: Output SNR vs CPI 长度 L
# ============================================================
data3 = load_json('snr_vs_l.json')
make_figure(
    data3,
    xlabel=r'CPI Length (OFDM Symbols)  $L$',
    ylabel=r'Output SNR (dB)',
    title='Output SNR vs CPI Length',
    out_name='fig3_snr_vs_l'
)

print('\n=== 三幅 Nature 风格图生成完毕 ===')
print(f'输出目录: {out_dir}')
