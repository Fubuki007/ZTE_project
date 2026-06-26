"""
RMSEd (距离估计 RMSE) vs SNR 对比图
三种预编码方案: ZF / Nullspace / Lagrange
从 task5_rmse_vs_snr_results.mat 读取数据
"""
import h5py
import numpy as np
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
import matplotlib.ticker as ticker

# ============================================================
# 读取数据
# ============================================================
mat_path = r"D:\AA 学习项目\AAA 智能反射面辅助通信感知\AAA ZTE_project\mat数据\task5_rmse_vs_snr_results.mat"

f = h5py.File(mat_path, 'r')
snr_all = f['snr_list'][:].flatten()          # (12,)  -50:5:5 dB
rmse_R_med = f['rmse_R_med'][:]                # (12, 3) — [ZF, Nullspace, Lagrange]
rmse_theta_med = f['rmse_theta_med'][:]        # (12, 3)
rmse_v_med = f['rmse_v_med'][:]                # (12, 3)
n_mc = int(f['n_mc'][()].flatten()[0])

# 列顺序: ZF, Nullspace, Lagrange (与 task5 中 precoders 数组一致)
labels = ['ZF', 'Nullspace', 'Lagrange']

print(f"SNR range: {snr_all[0]:+.0f} to {snr_all[-1]:+.0f} dB, {len(snr_all)} points")
print(f"Monte Carlo: {n_mc} trials per point")
print(f"\n=== 距离 RMSE (m) ===")
print(f"{'SNR(dB)':>8s}  {'ZF':>10s}  {'Nullspace':>10s}  {'Lagrange':>10s}")
for i, snr in enumerate(snr_all):
    print(f"{snr:+8.0f}  {rmse_R_med[i,0]:10.4f}  {rmse_R_med[i,1]:10.4f}  {rmse_R_med[i,2]:10.4f}")

# ============================================================
# 分析：找到过渡区
# ============================================================
# 定义"正常工作"阈值 (距离RMSE < 2m, 即20倍分辨率)
threshold = 2.0
for i_prec, label in enumerate(labels):
    working = rmse_R_med[:, i_prec] < threshold
    if np.any(working):
        first_snr = snr_all[np.where(working)[0][0]]
        print(f"\n{label} 首次正常工作的 SNR: {first_snr:+.0f} dB")
    else:
        print(f"\n{label} 在所有 SNR 点均未正常工作")

# ============================================================
# 绘图设置
# ============================================================
# 中文字体
plt.rcParams['font.family'] = 'sans-serif'
plt.rcParams['font.sans-serif'] = ['SimHei', 'Microsoft YaHei', 'DejaVu Sans']
plt.rcParams['axes.unicode_minus'] = False

# Nature 风格
plt.rcParams.update({
    'font.size': 9,
    'axes.titlesize': 10,
    'axes.labelsize': 9,
    'xtick.labelsize': 8,
    'ytick.labelsize': 8,
    'legend.fontsize': 8,
    'figure.dpi': 300,
    'savefig.dpi': 300,
    'savefig.bbox': 'tight',
    'savefig.pad_inches': 0.05,
    'axes.linewidth': 0.6,
    'xtick.major.width': 0.5,
    'ytick.major.width': 0.5,
})

colors = ['#E64B35', '#4DBBD5', '#00A087']   # 红/蓝/绿
markers = ['o', 's', '^']
line_styles = ['-', '--', '-.']

# ============================================================
# 图1: 全 SNR 范围 (log 纵轴)
# ============================================================
fig1, ax1 = plt.subplots(figsize=(4.5, 3.2))

for i, label in enumerate(labels):
    y = rmse_R_med[:, i]
    valid = ~np.isnan(y) & (y > 0)
    ax1.plot(snr_all[valid], y[valid],
             color=colors[i], marker=markers[i], linestyle=line_styles[i],
             linewidth=1.3, markersize=5, markerfacecolor=colors[i],
             markeredgewidth=0.5, markeredgecolor='white',
             label=label, clip_on=True)

ax1.set_yscale('log')
ax1.set_xlabel('SNR (dB)')
ax1.set_ylabel('距离 RMSE (m)')
ax1.set_title('距离估计 RMSE 对比: ZF vs Nullspace vs Lagrange', fontweight='bold')

# 标注分辨率线
range_res = 0.099  # 距离分辨率
ax1.axhline(y=range_res, color='gray', linestyle=':', linewidth=0.8, alpha=0.7)
ax1.text(snr_all[-1]+0.5, range_res*1.3, f'ΔR={range_res}m', fontsize=7,
         color='gray', ha='right', va='bottom')

ax1.grid(True, alpha=0.15, linewidth=0.3)
ax1.legend(frameon=True, edgecolor='#cccccc', loc='upper right')
ax1.set_ylim(bottom=0.03)

fig1.tight_layout()
fig1.savefig(r"D:\AA 学习项目\AAA 智能反射面辅助通信感知\AAA ZTE_project\png图片结果\rmse_distance_vs_snr.png")
plt.close(fig1)
print("\n✓ 图1 已保存: png图片结果/rmse_distance_vs_snr.png")

# ============================================================
# 图2: 放大过渡区 (-40 to -15 dB, 线性纵轴)
# ============================================================
fig2, ax2 = plt.subplots(figsize=(4.5, 3.2))

# 只取 SNR >= -40 的数据
mask = snr_all >= -40
snr_focus = snr_all[mask]

for i, label in enumerate(labels):
    y = rmse_R_med[mask, i]
    valid = ~np.isnan(y) & (y > 0)
    ax2.plot(snr_focus[valid], y[valid],
             color=colors[i], marker=markers[i], linestyle=line_styles[i],
             linewidth=1.5, markersize=6, markerfacecolor=colors[i],
             markeredgewidth=0.5, markeredgecolor='white',
             label=label, clip_on=True)

# 标注关键数值
# 在 SNR=-30 处标注对比
snr_neg30 = -30
idx_neg30 = np.where(np.isclose(snr_all, snr_neg30))[0][0]
for i, label in enumerate(labels):
    val = rmse_R_med[idx_neg30, i]
    if val < 10:
        ax2.annotate(f'{val:.2f}m',
                     xy=(snr_neg30, val),
                     xytext=(snr_neg30+1, val*1.5 if val < 1 else val*1.3),
                     fontsize=7, color=colors[i],
                     arrowprops=dict(arrowstyle='->', color=colors[i], lw=0.8),
                     )

ax2.set_xlabel('SNR (dB)')
ax2.set_ylabel('距离 RMSE (m)')
ax2.set_title('过渡区放大: SNR -40 ~ +5 dB', fontweight='bold')
ax2.grid(True, alpha=0.15, linewidth=0.3)
ax2.legend(frameon=True, edgecolor='#cccccc', loc='upper right')

fig2.tight_layout()
fig2.savefig(r"D:\AA 学习项目\AAA 智能反射面辅助通信感知\AAA ZTE_project\png图片结果\rmse_distance_zoom.png")
plt.close(fig2)
print("✓ 图2 已保存: png图片结果/rmse_distance_zoom.png")

# ============================================================
# 图3: 三合一 (距离/角度/速度 RMSE)
# ============================================================

fig3, axes = plt.subplots(1, 3, figsize=(10, 3))

titles = ['距离 RMSE', '角度 RMSE', '速度 RMSE']
ylabels = ['距离 RMSE (m)', '角度 RMSE (°)', '速度 RMSE (m/s)']
data = [rmse_R_med, rmse_theta_med, rmse_v_med]
resolutions = [0.099, None, None]  # 距离分辨率参考线

for ax_idx, (ax, title, ylabel, dat, res) in enumerate(
        zip(axes, titles, ylabels, data, resolutions)):

    for i, label in enumerate(labels):
        y = dat[:, i]
        valid = ~np.isnan(y) & (y > 0)
        ax.plot(snr_all[valid], y[valid],
                color=colors[i], marker=markers[i], linestyle=line_styles[i],
                linewidth=1.0, markersize=3.5, markerfacecolor=colors[i],
                markeredgewidth=0.3, markeredgecolor='white',
                label=label if ax_idx == 0 else None, clip_on=True)

    ax.set_yscale('log')
    ax.set_xlabel('SNR (dB)', fontsize=8)
    ax.set_ylabel(ylabel, fontsize=8)
    ax.set_title(title, fontweight='bold', fontsize=9)
    ax.grid(True, alpha=0.12, linewidth=0.3)
    ax.tick_params(labelsize=7)

    if res is not None:
        ax.axhline(y=res, color='gray', linestyle=':', linewidth=0.6, alpha=0.6)

# 统一图例
handles, labs = axes[0].get_legend_handles_labels()
fig3.legend(handles, labs, loc='upper center', ncol=3,
            frameon=True, edgecolor='#cccccc', fontsize=8,
            bbox_to_anchor=(0.5, 1.05))

fig3.tight_layout(pad=0.8)
fig3.savefig(r"D:\AA 学习项目\AAA 智能反射面辅助通信感知\AAA ZTE_project\png图片结果\rmse_3in1_vs_snr.png", dpi=300)
plt.close(fig3)
print("✓ 图3 已保存: png图片结果/rmse_3in1_vs_snr.png")

print("\n=== 三张图全部生成完毕 ===")
print("输出目录: png图片结果/")
