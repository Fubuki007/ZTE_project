# -*- coding: utf-8 -*-
"""
plot_si_suppression_zf_null.py — 根据 MATLAB 运行日志数据画 ZF vs 零空间法对比图
数据来源: data_si_suppression_zf_null.csv (median 估计值, SNR=-40:5:20, MC=200)
输出: fig/fig_si_suppression_{angle,velocity,range}_zf_null.png
"""
import numpy as np
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
import os

CSV = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                   'data_si_suppression_zf_null.csv')
FIGDIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'fig')
os.makedirs(FIGDIR, exist_ok=True)

# ---- 读数据 ----
data = np.genfromtxt(CSV, delimiter=',', names=True)
snr = data['snr']
zf  = {'R': data['zf_R'],  'th': data['zf_th'],  'v': data['zf_v']}
ns  = {'R': data['ns_R'],  'th': data['ns_th'],  'v': data['ns_v']}

# 项目配色: ZF 红 / 零空间 蓝青
C_ZF = (0.902, 0.294, 0.208)
C_NS = (0.302, 0.733, 0.835)
LEG  = ['ZF (no SI suppression)', 'Null-space']

titles  = ['Angle', 'Velocity', 'Range']
ylabels = ['Estimated angle (deg)', 'Estimated velocity (m/s)', 'Estimated range (m)']
fnames  = ['angle', 'velocity', 'range']
series  = [(zf, ns)]

for fi, (key, ylab) in enumerate(zip(['th', 'v', 'R'], ylabels)):
    fig, ax = plt.subplots(figsize=(6.2, 4.4))
    for s, c, m, lab in [(zf, C_ZF, 'o', LEG[0]), (ns, C_NS, 's', LEG[1])]:
        ax.semilogy(snr, np.maximum(s[key], 1e-12), color=c, marker=m,
                    linestyle='-', linewidth=1.3, markersize=5.5,
                    markerfacecolor='w', label=lab)
    ax.set_xlabel('Input SNR (dB)', fontsize=10)
    ax.set_ylabel(ylab, fontsize=10)
    ax.set_title(f'{titles[fi]} estimate vs SNR - SI suppression (ZF vs Null-space)\n'
                 f'L=256, MC=200, Mrx=16', fontsize=9)
    ax.legend(loc='best', fontsize=9)
    ax.grid(True, which='both', alpha=0.3)
    ax.set_xlim(snr[0] - 2, snr[-1] + 2)
    fig.tight_layout()
    out = os.path.join(FIGDIR, f'fig_si_suppression_{fnames[fi]}_zf_null.png')
    fig.savefig(out, dpi=200)
    plt.close(fig)
    print(f'  saved: {out}')

print('done.')
