"""
plot_rmse_snr_si_off.py
Nature 期刊风格: RMSE vs SNR 三幅图 (距离/角度/速度)
三种预编码方案 (ZF / Nullspace / Lagrange) 三条曲线
数据来源: task5_rmse_vs_snr_si_results.mat (SI-OFF 版)
"""
import h5py
import numpy as np
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
import matplotlib.ticker as ticker
import os, sys

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
    'ZF':        '#E64B35',
    'Nullspace': '#4DBBD5',
    'Lagrange':  '#00A087',
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
mat_path = sys.argv[1] if len(sys.argv) > 1 else r'C:\Users\Fubuki\Downloads\mat数据\task5_rmse_vs_snr_si_results.mat'
out_dir  = os.path.join(os.path.dirname(mat_path), '..', 'png图片结果')
# 如果上级没有 png图片结果，就用 input 旁边的 png/
if not os.path.isdir(out_dir):
    out_dir = os.path.join(os.path.dirname(mat_path), 'png')
os.makedirs(out_dir, exist_ok=True)

# ============================================================
# 读取数据
# ============================================================
print("读取数据...")
f = h5py.File(mat_path, 'r')
snr = f['snr_list'][:].flatten()
rmse_R_med     = f['rmse_R_med'][:]
rmse_theta_med = f['rmse_theta_med'][:]
rmse_v_med     = f['rmse_v_med'][:]
rmse_R_raw     = f['rmse_R'][:]
rmse_theta_raw = f['rmse_theta'][:]
rmse_v_raw     = f['rmse_v'][:]
n_mc = int(f['n_mc'][()].flatten()[0] if 'n_mc' in f else rmse_R_raw.shape[0])

# 检查 SI 状态
try:
    si_enabled = int(f['si_enabled'][()].flatten()[0]) if 'si_enabled' in f else 0
except:
    si_enabled = 0

# 从 params_summary 确认
si_label = 'SI-OFF'
try:
    ps = f['params_summary']
    if 'enable_SI' in ps:
        enable_si_val = int(np.array(ps['enable_SI']).ravel()[0])
        si_label = 'SI-ON' if enable_si_val else 'SI-OFF'
except:
    pass

print(f"SNR 范围: {snr[0]:.0f} ~ {snr[-1]:.0f} dB, MC={n_mc}, {si_label}")
print(f"rmse_R_med shape: {rmse_R_med.shape}")
print(f"rmse_R_raw shape: {rmse_R_raw.shape}")

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
            ax.text(snr[-1] + 0.3, ref_line * (1.3 if yscale != 'log' else 1.5),
                    ref_label, fontsize=6.5, color='gray', ha='right', va='bottom')

    ax.set_yscale(yscale)
    ax.set_xlabel('SNR (dB)', fontweight='normal')
    ax.set_ylabel(ylabel, fontweight='normal')
    ax.set_title(title, fontweight='bold', pad=5)

    ax.grid(True, alpha=0.15, linewidth=0.3)
    ax.set_axisbelow(True)
    ax.set_xticks(snr)
    ax.xaxis.set_minor_locator(ticker.MultipleLocator(2.5))

    ax.legend(frameon=True, edgecolor='#cccccc', facecolor='white',
              framealpha=0.9, loc='best', borderpad=0.4,
              handlelength=1.5, handletextpad=0.5)


# ============================================================
# Fig 1: 距离 RMSE (log 轴)
# ============================================================
fig1, ax1 = plt.subplots(figsize=(4.5, 3.2))

plot_rmse_panel(ax1, snr, rmse_R_med, rmse_R_raw,
                ylabel='Range RMSE (m)',
                title=f'Range Estimation RMSE vs SNR ({si_label}, K=256, MC={n_mc})',
                ref_line=delta_R,
                ref_label=f'$\\Delta R$={delta_R}m',
                yscale='log')

# 根据实际数据决定 Y 轴范围
ymin = max(0.001, np.nanmin(rmse_R_med[rmse_R_med > 0]) / 3)
ymax = np.nanmax(rmse_R_med) * 3
ax1.set_ylim(ymin, ymax)

fig1.tight_layout(pad=0.8)
fig1.savefig(os.path.join(out_dir, 'fig_range_rmse_vs_snr_sioff.png'))
plt.close(fig1)
print(f'  OK fig_range_rmse_vs_snr_sioff.png')

# ============================================================
# Fig 2: 角度 RMSE
# ============================================================
fig2, ax2 = plt.subplots(figsize=(4.5, 3.2))

plot_rmse_panel(ax2, snr, rmse_theta_med, rmse_theta_raw,
                ylabel='Angle RMSE (°)',
                title=f'Angle Estimation RMSE vs SNR ({si_label}, K=256, MC={n_mc})',
                yscale='linear')

fig2.tight_layout(pad=0.8)
fig2.savefig(os.path.join(out_dir, 'fig_angle_rmse_vs_snr_sioff.png'))
plt.close(fig2)
print(f'  OK fig_angle_rmse_vs_snr_sioff.png')

# ============================================================
# Fig 3: 速度 RMSE
# ============================================================
fig3, ax3 = plt.subplots(figsize=(4.5, 3.2))

plot_rmse_panel(ax3, snr, rmse_v_med, rmse_v_raw,
                ylabel='Velocity RMSE (m/s)',
                title=f'Velocity Estimation RMSE vs SNR ({si_label}, K=256, MC={n_mc})',
                yscale='linear')

fig3.tight_layout(pad=0.8)
fig3.savefig(os.path.join(out_dir, 'fig_velocity_rmse_vs_snr_sioff.png'))
plt.close(fig3)
print(f'  OK fig_velocity_rmse_vs_snr_sioff.png')

# ============================================================
# Fig 4: 三合一横排 (Nature 期刊常用版面)
# ============================================================
fig4, axes = plt.subplots(1, 3, figsize=(10, 3.0))

datasets_med = [rmse_R_med, rmse_theta_med, rmse_v_med]
datasets_raw = [rmse_R_raw, rmse_theta_raw, rmse_v_raw]
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

    if idx == 0:
        ax.set_yscale('log')
        ymin_r = max(0.001, np.nanmin(d_med[d_med > 0]) / 3)
        ymax_r = np.nanmax(d_med) * 3
        ax.set_ylim(ymin_r, ymax_r)

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

fig4.suptitle(f'3-D Estimation RMSE vs SNR ({si_label}, K=256, MC={n_mc})',
              fontweight='bold', fontsize=10, y=1.18)
fig4.tight_layout(pad=0.8)
fig4.savefig(os.path.join(out_dir, 'fig_rmse_3in1_snr_sioff.png'), dpi=300)
plt.close(fig4)
print(f'  OK fig_rmse_3in1_snr_sioff.png')

f.close()
print(f'\n=== 四张 Nature 风格图生成完毕 ===')
print(f'输出目录: {out_dir}')
