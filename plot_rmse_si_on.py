"""
plot_rmse_si_on.py
SI-ON RMSE 对比图: ZF vs Nullspace vs Lagrange
数据来源: mat数据/task5_rmse_vs_snr_si_results.mat
beta_SI = 10, kappa_SI = 100, n_mc = 3
"""
import h5py
import numpy as np
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt

# ============================================================
# 读取数据
# ============================================================
mat_path = r"D:\AA 学习项目\AAA 智能反射面辅助通信感知\AAA ZTE_project\mat数据\task5_rmse_vs_snr_si_results.mat"

f = h5py.File(mat_path, 'r')
snr = f['snr_list'][:].flatten()
rmse_R_med = f['rmse_R_med'][:]        # (10, 3): ZF, Nullspace, Lagrange
rmse_theta_med = f['rmse_theta_med'][:]
rmse_v_med = f['rmse_v_med'][:]
rmse_R_raw = f['rmse_R'][:]            # (3, 10, 3): prec × SNR × MC
n_mc = int(f['n_mc'][()].flatten()[0])

labels = ['ZF', 'Nullspace', 'Lagrange']
colors = ['#E64B35', '#4DBBD5', '#00A087']
markers = ['o', 's', '^']
styles = ['-', '--', '-.']

print("=== SI-ON 数据摘要 ===")
print(f"SNR: {snr}")
print(f"MC trials: {n_mc}")
print(f"\n距离 RMSE (m):")
print(f"{'SNR':>6s}  {'ZF':>10s}  {'Nullspace':>10s}  {'Lagrange':>10s}")
for i, s in enumerate(snr):
    print(f"{s:+6.0f}  {rmse_R_med[i,0]:10.2f}  {rmse_R_med[i,1]:10.2f}  {rmse_R_med[i,2]:10.2f}")

# 计算对比指标
# 找出 nullspace 正常工作的 SNR
ns_working = rmse_R_med[:, 1] < 2.0
zf_failing = rmse_R_med[:, 0] > 100
lg_failing = rmse_R_med[:, 2] > 100

print(f"\n=== 关键指标 ===")
print(f"ZF: 在所有 SNR 点 RMSEd = {rmse_R_med[0,0]:.1f}m (完全失效)")
print(f"Nullspace: SNR >= {snr[ns_working][0]:+.0f} dB 时 RMSEd ≈ {np.mean(rmse_R_med[ns_working, 1]):.3f}m")
print(f"Lagrange: 在所有 SNR 点 RMSEd = {rmse_R_med[0,2]:.1f}m (完全失效, 高κ导致)")

# ============================================================
# 中文字体
# ============================================================
plt.rcParams['font.family'] = 'sans-serif'
plt.rcParams['font.sans-serif'] = ['SimHei', 'Microsoft YaHei', 'DejaVu Sans']
plt.rcParams['axes.unicode_minus'] = False
plt.rcParams.update({
    'font.size': 9, 'axes.titlesize': 11, 'axes.labelsize': 10,
    'xtick.labelsize': 8, 'ytick.labelsize': 8, 'legend.fontsize': 8,
    'figure.dpi': 300, 'savefig.dpi': 300,
    'savefig.bbox': 'tight', 'savefig.pad_inches': 0.08,
    'axes.linewidth': 0.6, 'xtick.major.width': 0.5, 'ytick.major.width': 0.5,
})

out_dir = r"D:\AA 学习项目\AAA 智能反射面辅助通信感知\AAA ZTE_project\png图片结果"

# ============================================================
# 图 1: 距离 RMSE 主图 (log 纵轴)
# ============================================================
fig1, ax1 = plt.subplots(figsize=(5.5, 3.8))

for i, (label, c, m, ls) in enumerate(zip(labels, colors, markers, styles)):
    y = rmse_R_med[:, i]
    valid = ~np.isnan(y) & (y > 0)
    ax1.plot(snr[valid], y[valid],
             color=c, marker=m, linestyle=ls,
             linewidth=1.5, markersize=6, markerfacecolor=c,
             markeredgewidth=0.5, markeredgecolor='white',
             label=label, clip_on=True, zorder=5-i)

# 距离分辨率参考线
range_res = 0.099
ax1.axhline(y=range_res, color='gray', linestyle=':', linewidth=0.8, alpha=0.5)
ax1.text(snr[-1]+0.3, range_res*1.5, f'距离分辨率 ΔR={range_res}m',
         fontsize=7, color='gray', ha='right', va='bottom')

# 标注关键区域
# ZF/Lagrange 失效区
ax1.annotate('ZF & Lagrange\n完全失效 (SI淹没目标)',
             xy=(5, 600), fontsize=8, color='#E64B35',
             ha='center', va='center',
             bbox=dict(boxstyle='round,pad=0.3', facecolor='#FFEEEE', edgecolor='#E64B35', alpha=0.7))

# Nullspace 工作区
ax1.annotate('Nullspace\n正常工作',
             xy=(5, 0.5), fontsize=8, color='#4DBBD5',
             ha='center', va='center',
             bbox=dict(boxstyle='round,pad=0.3', facecolor='#EEF8FF', edgecolor='#4DBBD5', alpha=0.7))

ax1.set_yscale('log')
ax1.set_xlabel('SNR (dB)', fontsize=11)
ax1.set_ylabel('距离 RMSE (m)', fontsize=11)
ax1.set_title('自干扰下距离估计 RMSE 对比\n(ZF vs Nullspace vs Lagrange, beta_SI=10, kappa=100)',
              fontweight='bold')
ax1.grid(True, alpha=0.12, linewidth=0.3)
ax1.legend(frameon=True, edgecolor='#cccccc', loc='lower left', fontsize=9)

# Y轴科学计数法
ax1.set_ylim(0.05, 2000)

fig1.tight_layout()
fig1.savefig(f'{out_dir}/rmse_distance_si_on.png')
plt.close(fig1)
print(f"\n✓ 图1 已保存: png图片结果/rmse_distance_si_on.png")

# ============================================================
# 图 2: 三合一 (距离 + 角度 + 速度)
# ============================================================
fig2, axes = plt.subplots(1, 3, figsize=(12, 3.5))

titles = ['距离 RMSE', '角度 RMSE', '速度 RMSE']
ylabels = ['距离 RMSE (m)', '角度 RMSE (°)', '速度 RMSE (m/s)']
datasets = [rmse_R_med, rmse_theta_med, rmse_v_med]
refs = [0.099, None, None]

for ax_idx, (ax, title, ylabel, dat, ref) in enumerate(
        zip(axes, titles, ylabels, datasets, refs)):

    for i, (label, c, m, ls) in enumerate(zip(labels, colors, markers, styles)):
        y = dat[:, i]
        valid = ~np.isnan(y) & (y > 0)
        ax.plot(snr[valid], y[valid],
                color=c, marker=m, linestyle=ls,
                linewidth=1.1, markersize=4, markerfacecolor=c,
                markeredgewidth=0.3, markeredgecolor='white',
                label=label if ax_idx == 0 else None, clip_on=True)

    ax.set_yscale('log')
    ax.set_xlabel('SNR (dB)', fontsize=9)
    ax.set_ylabel(ylabel, fontsize=9)
    ax.set_title(title, fontweight='bold', fontsize=10)
    ax.grid(True, alpha=0.12, linewidth=0.3)
    ax.tick_params(labelsize=7)

    if ref is not None:
        ax.axhline(y=ref, color='gray', linestyle=':', linewidth=0.6, alpha=0.5)

# 统一图例
handles, labs = axes[0].get_legend_handles_labels()
fig2.legend(handles, labs, loc='upper center', ncol=3,
            frameon=True, edgecolor='#cccccc', fontsize=9,
            bbox_to_anchor=(0.5, 1.08))

fig2.suptitle('自干扰下三维估计 RMSE 对比 (beta_SI=10, kappa=100)',
              fontweight='bold', fontsize=11, y=1.18)

fig2.tight_layout(pad=0.8)
fig2.savefig(f'{out_dir}/rmse_3in1_si_on.png', dpi=300)
plt.close(fig2)
print(f"✓ 图2 已保存: png图片结果/rmse_3in1_si_on.png")

# ============================================================
# 图 3: 距离 RMSE 带误差棒 (展示 MC 方差)
# ============================================================
fig3, ax3 = plt.subplots(figsize=(5.5, 3.8))

for i, (label, c, m, ls) in enumerate(zip(labels, colors, markers, styles)):
    y_med = rmse_R_med[:, i]
    # 计算 std (跨 MC trials)
    y_std = np.zeros(len(snr))
    for j in range(len(snr)):
        vals = rmse_R_raw[i, j, :]
        y_std[j] = np.nanstd(vals) if np.sum(~np.isnan(vals)) > 1 else 0

    valid = ~np.isnan(y_med) & (y_med > 0)
    ax3.errorbar(snr[valid], y_med[valid], yerr=y_std[valid],
                 color=c, marker=m, linestyle=ls,
                 linewidth=1.3, markersize=5, markerfacecolor=c,
                 markeredgewidth=0.5, markeredgecolor='white',
                 capsize=3, capthick=0.8, elinewidth=0.8,
                 label=label, clip_on=True)

ax3.set_yscale('log')
ax3.set_xlabel('SNR (dB)', fontsize=11)
ax3.set_ylabel('距离 RMSE (m)', fontsize=11)
ax3.set_title('距离 RMSE 含 MC 方差 (n_mc=3)\nZF & Lagrange 被 SI 淹没, Nullspace 稳定',
              fontweight='bold')
ax3.grid(True, alpha=0.12, linewidth=0.3)
ax3.legend(frameon=True, edgecolor='#cccccc', loc='lower left', fontsize=9)
ax3.set_ylim(0.05, 2000)

fig3.tight_layout()
fig3.savefig(f'{out_dir}/rmse_distance_si_on_errorbar.png')
plt.close(fig3)
print(f"✓ 图3 已保存: png图片结果/rmse_distance_si_on_errorbar.png")

f.close()
print(f"\n=== 三张图全部生成完毕 ===")
print(f"输出目录: {out_dir}")
