#!/usr/bin/env python3
"""画 task6 RMSE vs 目标数 Q 的三张图：角度/速度/距离，各含 ZF/Nullspace/Lagrange 三曲线"""

import h5py
import numpy as np
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
from matplotlib.ticker import ScalarFormatter, LogLocator
import os

# ── 加载数据 ──────────────────────────────────────────
_script_dir = os.path.dirname(os.path.abspath(__file__))
mat_path = os.path.join(_script_dir, 'task6_rmse_vs_Q.mat')
png_dir = os.path.join(_script_dir, 'png图片结果')  # 使用现有的 png 目录
os.makedirs(png_dir, exist_ok=True)

f = h5py.File(mat_path, 'r')
rmse_angle = f['rmse_angle'][()]   # (8,8), rows: 0=zf, 1=nullspace, 2=lagrange
rmse_range = f['rmse_range'][()]
rmse_vel   = f['rmse_vel'][()]
N_mc = int(f['N_mc'][()].ravel()[0])
f.close()

# ── 配置 ──────────────────────────────────────────────
x_axis = np.arange(0, 16, 2)          # 0,2,4,6,8,10,12,14
labels = ['ZF', 'Nullspace', 'Lagrange']
colors = ['#2E86AB', '#A23B72', '#F18F01']
markers = ['o', 's', '^']
line_styles = ['-', '--', '-.']
line_width = 2.0
marker_size = 9

datasets = {
    'Angle (deg)':  (rmse_angle[0:3, :], '角度 RMSE'),
    'Velocity (m/s)': (rmse_vel[0:3, :], '速度 RMSE'),
    'Range (m)':   (rmse_range[0:3, :], '距离 RMSE'),
}

# ── 全局 matplotlib 设置 ──────────────────────────────
# 用 SimHei 支持中文标题
from matplotlib.font_manager import FontProperties
simhei = FontProperties(fname=r'C:\Windows\Fonts\simhei.ttf', size=13)
simhei_title = FontProperties(fname=r'C:\Windows\Fonts\simhei.ttf', size=16)

plt.rcParams.update({
    'font.family': 'sans-serif',
    'font.size': 13,
    'axes.titlesize': 16,
    'axes.labelsize': 14,
    'legend.fontsize': 11,
    'xtick.labelsize': 11,
    'ytick.labelsize': 11,
    'figure.dpi': 150,
    'savefig.dpi': 300,
    'savefig.bbox': 'tight',
    'savefig.pad_inches': 0.1,
})

# ── 逐张画图 ──────────────────────────────────────────
for key, (data, title_cn) in datasets.items():
    fig, ax = plt.subplots(figsize=(8, 5.5))

    for i in range(3):
        ax.plot(x_axis, data[i, :],
                color=colors[i], marker=markers[i], linestyle=line_styles[i],
                linewidth=line_width, markersize=marker_size,
                label=labels[i], markeredgewidth=1.2, markeredgecolor='white')

    ax.set_yscale('log')
    ax.set_xlabel('Number of Targets Q')
    ax.set_ylabel(f'{key} RMSE')
    ax.set_title(f'RMSE vs Number of Targets — {title_cn}  (N_m_c = {N_mc})', fontproperties=simhei_title)
    ax.set_xticks(x_axis)
    ax.grid(True, which='major', alpha=0.35, linestyle='-')
    ax.grid(True, which='minor', alpha=0.12, linestyle=':')
    ax.legend(framealpha=0.85, edgecolor='gray')

    # 把 y 轴刻度标成 10^n 形式（不是科学计数）
    ax.yaxis.set_major_formatter(ScalarFormatter())
    ax.yaxis.set_major_locator(LogLocator(base=10.0, numticks=10))
    # 手动标注 yticklabels 为 10^n
    yticks = [1e-3, 1e-2, 1e-1, 1e0, 1e1, 1e2, 1e3]
    ax.set_yticks(yticks)
    ax.set_yticklabels([r'$10^{-3}$', r'$10^{-2}$', r'$10^{-1}$',
                         r'$10^{0}$', r'$10^{1}$', r'$10^{2}$', r'$10^{3}$'])

    fig.tight_layout()

    # 生成文件名
    eng_key = key.split()[0].lower()
    fname_png = os.path.join(png_dir, f'task6_rmse_vs_Q_{eng_key}.png')
    fig.savefig(fname_png, dpi=300, facecolor='white', edgecolor='none')
    plt.close(fig)
    print(f'✅ 已保存: {fname_png}')

print('\n🎉 三张图全部生成完毕！')
