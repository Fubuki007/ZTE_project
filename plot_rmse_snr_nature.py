"""
plot_rmse_snr_nature.py
Nature 期刊风格: RMSE vs SNR 三幅图 (距离/角度/速度)
三种预编码方案 (ZF / Nullspace / Lagrange) 三条曲线
数据来源: mat数据/task5_rmse_vs_snr_si_results.mat (SNR修正版)
"""
import h5py
import numpy as np
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
import matplotlib.ticker as ticker
import os

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
    'legend.fontsize': 7.5,
    'figure.dpi': 300,
    'savefig.dpi': 300,
    'savefig.bbox': 'tight',
    'savefig.pad_inches': 0.08,
    'axes.linewidth': 0.5,
    'xtick.major.width': 0.5,
    'ytick.major.width': 0.5,
    'xtick.major.size': 3,
    'ytick.major.size': 3,
    'xtick.minor.size': 1.5,
    'ytick.minor.size': 1.5,
    'lines.linewidth': 1.2,
    'lines.markersize': 4.5,
})

# Nature 期刊推荐配色 (色盲友好)
PREC_COLORS = {
    'ZF':        '#E64B35',  # 红
    'Nullspace': '#4DBBD5',  # 蓝
    'Lagrange':  '#00A087',  # 绿
}
PREC_MARKERS = {
    'ZF':        'o',
    'Nullspace': 's',
    'Lagrange':  '^',
}
PREC_STYLES = {
    'ZF':        '-',
    'Nullspace': '--',
    'Lagrange':  '-.',
}
PREC_NAMES = ['ZF', 'Nullspace', 'Lagrange']

# ============================================================
# 路径配置
# ============================================================
_script_dir = os.path.dirname(os.path.abspath(__file__))
mat_path = os.path.join(_script_dir, 'mat数据', 'task5_rmse_vs_snr_si_results.mat')
out_dir  = os.path.join(_script_dir, 'png图片结果')
os.makedirs(out_dir, exist_ok=True)

# ============================================================
# 读取数据
# ============================================================
print("读取数据...")
f = h5py.File(mat_path, 'r')
snr = f['snr_list'][:].flatten()
# 维度: (mc, snr, precoder) → med: (snr, precoder)
rmse_R_med     = f['rmse_R_med'][:]
rmse_theta_med = f['rmse_theta_med'][:]
rmse_v_med     = f['rmse_v_med'][:]
rmse_R_raw     = f['rmse_R'][:]       # (mc, snr, precoder)
n_mc = int(f['n_mc'][()].flatten()[0] if 'n_mc' in f else rmse_R_raw.shape[0])

# 读取 SI 泄漏信息 (如果存在)
si_leak_info = None
try:
    si_enabled = int(f['si_enabled'][()].flatten()[0]) if 'si_enabled' in f else 0
except:
    si_enabled = 1

print(f"SNR 范围: {snr[0]:.0f} ~ {snr[-1]:.0f} dB, MC={n_mc}")
print(f"SI enabled: {si_enabled}")

# 打印摘要
print(f"\n{'SNR':>6s}  {'ZF':>10s}  {'Nullspace':>10s}  {'Lagrange':>10s}")
for i, s in enumerate(snr):
    print(f"{s:+6.0f}  {rmse_R_med[i,0]:10.4f}  {rmse_R_med[i,1]:10.4f}  {rmse_R_med[i,2]:10.4f}")

# 距离分辨率
delta_R = 0.099

# ============================================================
# 辅助函数: 画单张 RMSE 图
# ============================================================
def plot_rmse_panel(ax, snr, data_med, data_raw, ylabel, title, ref_line=None,
                     ref_label=None, yscale='linear'):
    """
    在给定 axes 上画三条预编码曲线
    data_med: (snr, precoder) 中位数
    data_raw: (mc, snr, precoder) 原始数据，用于误差棒
    """
    for i, name in enumerate(PREC_NAMES):
        y_med = data_med[:, i]
        # 计算 std
        y_std = np.zeros(len(snr))
        for j in range(len(snr)):
            vals = data_raw[:, j, i]
            y_std[j] = np.nanstd(vals) if np.sum(~np.isnan(vals)) > 1 else 0

        color = PREC_COLORS[name]
        marker = PREC_MARKERS[name]
        ls = PREC_STYLES[name]

        # 主线 + 误差棒
        ax.errorbar(snr, y_med, yerr=y_std,
                    color=color, marker=marker, linestyle=ls,
                    linewidth=1.2, markersize=4.5,
                    markerfacecolor=color,
                    markeredgewidth=0.5, markeredgecolor='white',
                    capsize=3, capthick=0.6, elinewidth=0.6,
                    label=name, clip_on=True, zorder=5-i)

    if ref_line is not None:
        ax.axhline(y=ref_line, color='gray', linestyle=':', linewidth=0.6, alpha=0.6)
        if ref_label:
            ax.text(snr[-1] + 0.3, ref_line * 1.3, ref_label,
                    fontsize=6.5, color='gray', ha='right', va='bottom')

    ax.set_yscale(yscale)
    ax.set_xlabel('SNR (dB)', fontweight='normal')
    ax.set_ylabel(ylabel, fontweight='normal')
    ax.set_title(title, fontweight='bold', pad=5)

    # 网格
    ax.grid(True, alpha=0.15, linewidth=0.3)
    ax.set_axisbelow(True)

    # X轴刻度
    ax.set_xticks(snr)
    ax.xaxis.set_minor_locator(ticker.MultipleLocator(2.5))

    # 图例
    ax.legend(frameon=True, edgecolor='#cccccc', facecolor='white',
              framealpha=0.9, loc='best', borderpad=0.4,
              handlelength=1.5, handletextpad=0.5)


# ============================================================
# Fig 1: 距离 RMSE (log 轴, ZF/NS/LG 差距 1400 倍)
# ============================================================
fig1, ax1 = plt.subplots(figsize=(4.5, 3.2))

plot_rmse_panel(ax1, snr, rmse_R_med, rmse_R_raw,
                ylabel='Range RMSE (m)',
                title='Range Estimation RMSE vs SNR\n(SI-ON, $\\beta_{SI}$=0.02, SNR based on target power)',
                ref_line=delta_R,
                ref_label=f'$\\Delta R$={delta_R}m',
                yscale='log')

# 标注 ZF 失败原因
ax1.annotate('ZF: SI leakage $\\approx$210\n(failed, detecting SI ghost peaks)',
             xy=(10, 400), fontsize=7, color='#E64B35',
             ha='center', va='center',
             bbox=dict(boxstyle='round,pad=0.3', facecolor='#FFF0F0',
                       edgecolor='#E64B35', alpha=0.8, linewidth=0.5))

# 标注 NS/LG 成功区 (RMSE ≈ 0.007m << ΔR)
ax1.annotate('NS/LG: SI suppressed\nRMSE≈0.007m << ΔR=0.099m',
             xy=(10, 0.015), fontsize=7, color='#00A087',
             ha='center', va='bottom',
             bbox=dict(boxstyle='round,pad=0.3', facecolor='#F0FFF5',
                       edgecolor='#00A087', alpha=0.8, linewidth=0.5))

ax1.set_ylim(0.003, 2000)
fig1.tight_layout(pad=0.8)
fig1.savefig(os.path.join(out_dir, 'fig_range_rmse_vs_snr.png'))
plt.close(fig1)
print(f'  \u2713 fig_range_rmse_vs_snr.png')

# ============================================================
# Fig 2: 角度 RMSE
# ============================================================
fig2, ax2 = plt.subplots(figsize=(4.5, 3.2))

plot_rmse_panel(ax2, snr, rmse_theta_med, f['rmse_theta'][:],
                ylabel='Angle RMSE (°)',
                title='Angle Estimation RMSE vs SNR (SI-ON, $\\beta_{SI}$=0.02)',
                yscale='linear')

fig2.tight_layout(pad=0.8)
fig2.savefig(os.path.join(out_dir, 'fig_angle_rmse_vs_snr.png'))
plt.close(fig2)
print(f'  ✓ fig_angle_rmse_vs_snr.png')

# ============================================================
# Fig 3: 速度 RMSE
# ============================================================
fig3, ax3 = plt.subplots(figsize=(4.5, 3.2))

plot_rmse_panel(ax3, snr, rmse_v_med, f['rmse_v'][:],
                ylabel='Velocity RMSE (m/s)',
                title='Velocity Estimation RMSE vs SNR (SI-ON, $\\beta_{SI}$=0.02)',
                yscale='linear')

fig3.tight_layout(pad=0.8)
fig3.savefig(os.path.join(out_dir, 'fig_velocity_rmse_vs_snr.png'))
plt.close(fig3)
print(f'  ✓ fig_velocity_rmse_vs_snr.png')

# ============================================================
# Fig 4: 三合一横排 (Nature 期刊常用版面)
# ============================================================
fig4, axes = plt.subplots(1, 3, figsize=(10, 3.0))

datasets_med = [rmse_R_med, rmse_theta_med, rmse_v_med]
datasets_raw = [rmse_R_raw, f['rmse_theta'][:], f['rmse_v'][:]]
titles = ['Range RMSE', 'Angle RMSE', 'Velocity RMSE']
ylabels = ['Range RMSE (m)', 'Angle RMSE (°)', 'Velocity RMSE (m/s)']
refs = [delta_R, None, None]

for idx, (ax, d_med, d_raw, title, ylabel, ref) in enumerate(
        zip(axes, datasets_med, datasets_raw, titles, ylabels, refs)):

    for i, name in enumerate(PREC_NAMES):
        y_med = d_med[:, i]
        color = PREC_COLORS[name]
        marker = PREC_MARKERS[name]
        ls = PREC_STYLES[name]

        ax.plot(snr, y_med,
                color=color, marker=marker, linestyle=ls,
                linewidth=1.1, markersize=4,
                markerfacecolor=color,
                markeredgewidth=0.5, markeredgecolor='white',
                label=name if idx == 0 else None, clip_on=True)

    if ref is not None:
        ax.axhline(y=ref, color='gray', linestyle=':', linewidth=0.5, alpha=0.6)

    # 距离子图用 log 轴 (ZF≈142 >> NS/LG≈0.007)
    if idx == 0:
        ax.set_yscale('log')
        ax.set_ylim(0.003, 1500)

    ax.set_xlabel('SNR (dB)', fontsize=8)
    ax.set_ylabel(ylabel, fontsize=8)
    ax.set_title(title, fontweight='bold', fontsize=9)
    ax.grid(True, alpha=0.15, linewidth=0.3)
    ax.set_axisbelow(True)
    ax.set_xticks(snr)

# 统一图例
handles, labs = axes[0].get_legend_handles_labels()
fig4.legend(handles, labs, loc='upper center', ncol=3,
            frameon=True, edgecolor='#cccccc', facecolor='white',
            framealpha=0.9, fontsize=8, borderpad=0.3,
            bbox_to_anchor=(0.5, 1.05))

fig4.suptitle('3-D Estimation RMSE vs SNR (SI-ON, $\\beta_{SI}$=0.02, SNR corrected)',
              fontweight='bold', fontsize=10, y=1.18)
fig4.tight_layout(pad=0.8)
fig4.savefig(os.path.join(out_dir, 'fig_rmse_3in1_snr.png'), dpi=300)
plt.close(fig4)
print(f'  ✓ fig_rmse_3in1_snr.png')

f.close()
print(f'\n=== 四张 Nature 风格图生成完毕 ===')
print(f'输出目录: {out_dir}')
