"""Build a Chinese, source-linked PPT brief from completed RIS experiments."""
from pathlib import Path
import csv
import json
import shutil
import zipfile

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'server-results' / 'ris_report_20261010'
OUT.mkdir(parents=True, exist_ok=True)


def read_csv(path):
    with path.open(encoding='utf-8-sig', newline='') as f:
        return list(csv.DictReader(f))


mc100 = read_csv(ROOT / 'server-results/ris_rmse_snr_mc100/ris_rmse_snr_mc100_summary.csv')
mc60 = read_csv(ROOT / 'server-results/ris_sic_mc60_final/ris_sic_rmse_snr_mc60_resume_v3_double_summary.csv')
pooled = read_csv(OUT / 'recomputed_rms_across_mc.csv')
no_si = read_csv(ROOT / 'ris_isac_no_interference_summary.csv')
smoke = read_csv(ROOT / 'ris_isac_si_mc_smoke_summary.csv')
meta = json.loads((OUT / 'completed_experiment_metadata.json').read_text(encoding='utf-8'))
assert len(mc100) == 42 and len(mc60) == 42
assert meta['mc100']['finite_theta_count'] == 4200
assert meta['mc60']['finite_theta_count'] == 2520
assert meta['no_si']['mode'] == 'full' and meta['smoke_si']['n_mc'] == 2


def row(data, snr, scheme, experiment=None):
    return next(r for r in data if float(r['snr_dB']) == snr and r['scheme'] == scheme
                and (experiment is None or r.get('experiment') == experiment))


def fmt(x):
    return f'{float(x):.6g}'


def table(headers, rows):
    return '\n'.join(['| ' + ' | '.join(headers) + ' |',
                      '| ' + ' | '.join(['---'] * len(headers)) + ' |'] +
                     ['| ' + ' | '.join(str(x) for x in r) + ' |' for r in rows])


def link(label, path):
    return f'[{label}](<{path.as_posix()}>)'


def copy_asset(src, group):
    dest = OUT / group / src.name
    dest.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(src, dest)
    return dest


assets = {}
for name in ['angle', 'range', 'velocity']:
    assets['mc100_' + name] = copy_asset(
        ROOT / 'server-results/ris_rmse_snr_mc100' / f'ris_{name}_rmse_vs_snr_mc100.png', 'figures')
    assets['mc60_' + name] = copy_asset(
        ROOT / 'server-results/ris_sic_mc60_final' /
        f'ris_sic_rmse_snr_mc60_resume_v3_double_{name}_rmse_vs_snr.png', 'figures')
assets['mc60_all'] = copy_asset(ROOT / 'server-results/ris_sic_mc60_final/ris_sic_rmse_snr_mc60_resume_v3_double_all.png', 'figures')
assets['no_si'] = copy_asset(ROOT / 'ris_isac_no_interference_results.png', 'figures')
source_files = [
    ROOT / 'ris_isac_no_interference_summary.csv',
    ROOT / 'ris_isac_si_mc_smoke_summary.csv',
    ROOT / 'server-results/ris_rmse_snr_mc100/ris_rmse_snr_mc100_summary.csv',
    ROOT / 'server-results/ris_rmse_snr_mc100/ris_rmse_snr_mc100_results.mat',
    ROOT / 'server-results/ris_sic_mc60_final/ris_sic_rmse_snr_mc60_resume_v3_double_summary.csv',
    ROOT / 'server-results/ris_sic_mc60_final/ris_sic_rmse_snr_mc60_resume_v3_double_results.mat',
    ROOT / 'RIS_SIC_Wu2024_验证/ris_sic_summary.csv',
    ROOT / 'RIS_SIC_MIMO_ZTE_28G/zte_ris_mimo_summary.csv',
    ROOT / 'RIS_SIC_MIMO_ZTE_28G/zte_mimo_ris_targetbeam.csv',
]
sources = [copy_asset(p, 'data') for p in source_files]

parts = [r'''# RIS 辅助通感精度：已完成实验结果汇总与 PPT 输入稿

整理日期：2026-10-10。用途：作为其他 AI 制作今晚汇报 PPT 的事实来源。数据来自当前项目已保存的 CSV、MAT 和原始图，未重新运行感知仿真。

## 0. 给制作 PPT 的 AI

请基于本文制作 10～12 页中文科研阶段汇报，主题建议为“RIS 辅助全双工通感：精度增益与 SIC 对照实验”。按“问题—模型—实验配置—结果—解释—限制—下一步”组织，突出数字与曲线，每页只讲一个主要结论。

- 以已完成的 MC100 和 MC60 为主要证据；无干扰单次验证和 MC2 冒烟只作辅助。
- 所有图、数字都必须标明 SI 是否开启、SIC 是否开启、βSI、MC 次数和统计口径。
- 本文“标准汇总 RMSE”和“跨 MC 的中位 RMSE”是两种统计，不能混用。已有 PNG 曲线是中位数曲线；如重画标准 RMSE，使用随附复算 CSV。
- βSI=10、100、1000 的 MC50 扫描尚未完成，不可编造该扫描的最终结果或画成已完成曲线。
- “RIS 增强目标回波”与“RIS 反射路径相消 SI”是不同实验，不能把后一类的 dB 抑制量写成前一类的感知精度收益。
- 这是当前固定几何、理想目标几何信息和仿真模型下的阶段结果，不是实测硬件精度或普适提升倍数。

## 1. 可以直接用于汇报的核心结论

**加入 RIS 后，当前仿真中的角度、距离和速度估计都有明显改善；这一结论在关闭 SIC 和开启 SIC 时都成立。MC60 的同组配对对照表明，βSI=0.1 时主要收益来自 RIS，当前 pilot-LS SIC 的额外收益很小。**

按更能反映大误差样本的标准汇总 RMSE，在 MC60、βSI=0.1、SNR=0 dB、SIC 关闭时：
''']

headline = []
for key, label in [('rms_theta_deg', '俯仰角 θ（°）'), ('rms_range_m', '距离 R（m）'), ('rms_velocity_mps', '速度 v（m/s）')]:
    a = float(row(pooled, 0, 'No RIS (SIC off)', 'mc60')[key])
    b = float(row(pooled, 0, 'RIS continuous (SIC off)', 'mc60')[key])
    headline.append([label, fmt(a), fmt(b), f'{a/b:,.1f} 倍', f'{100*(1-b/a):.4f}%'])
parts += [table(['指标', '无 RIS', '连续相位 RIS', 'RMSE 缩小倍数', 'RMSE 降低比例'], headline), r'''

可直接口述：

> 在当前 28 GHz、16 发 64 收、64 单元 RIS 的固定场景中，MC60 结果显示，SNR=0 dB 时，即使关闭 SIC，加入 RIS 后标准角度 RMSE 也从约 35.44° 降至 0.0287°，距离从约 132.46 m 降至 1.16 cm，速度从约 137.71 m/s 降至 0.226 m/s。开启现有 SIC 后，RIS 的优势仍然存在，但额外改善很小。

同时需要讲清：在 −20 dB 附近，中位数已经很好，但标准汇总 RMSE 仍较大，说明存在少数严重失配；不能据中位数就宣称全部试验稳定达到厘米级。更高 SNR 下，两种统计均支持明显收益。

## 2. 已完成和未完成的实验清单

| 编号 | 实验 | SI / SIC | 采样与方案 | 完成状态与用途 |
| --- | --- | --- | --- | --- |
| A | 无自干扰、只加入 RIS | SI 关闭；SIC 关闭；βSI=0 | SNR=10 dB；一次完整尺寸验证；7 种相位方案 | 2026-10-02 完成；证明 RIS 接入与当前模型中的精度改善，不能代替 MC 统计 |
| B | 有 SI 的低 MC 冒烟 | SI 开启；SIC 关闭；βSI=0.001、0.1 | SNR=10 dB；MC=2；无 RIS、连续 RIS、四相位 RIS | 2026-10-02 完成；仅验证流程与趋势 |
| C | 无 SIC 的完整 SNR 扫描 | SI 开启；SIC 关闭；βSI=0.1；点散射 SI 模型 | SNR=−45:5:20 dB；MC=100；3 个方案；4200 个方案单元 | 2026-10-04 完成；已有三项中位 RMSE 曲线 |
| D | 同组配对 RIS × SIC 对照 | SI 开启；βSI=0.1；矩阵 Rician SI；有／无 SIC | SNR=[−25,−20,−15,−10,0,10,20] dB；MC=60；6 个方案；2520 个方案单元 | MAT 时间戳 2026-10-09 23:27:34；完整数据已取回并核验 |
| E | 强 SI 对照 | SI 开启；βSI=10、100、1000；有／无 SIC | 同 D 的 7 个 SNR 点；MC=50；4 个方案；共 4200 个方案单元 | 整理时仍在运行；2026-10-10 12:08 查询为 300/4200，完整 MC=0/50；不纳入最终性能结论 |

C 与 D 的 SI 模型、MC 数及随机样本不同。比较 SIC 的作用应使用 D 内部的同组配对结果，不能把 C 与 D 直接相减归因于 SIC。

## 3. 主感知实验配置与模型

| 项目 | 设置 |
| --- | --- |
| 载频 / 总带宽 | 28 GHz / 1.52064 GHz |
| 子载波数 / 间隔 | 12672 / 120 kHz |
| CPI | 256 个 OFDM 符号 |
| 发射 / 接收阵列 | 4×4=16 / 8×8=64 |
| 波形与空间流 | 16-QAM；单空间流 |
| 发射预编码 | ZF；固定几何下指向目标 1 的通信波束；各方案共用同一发射波形 |
| RIS | 8×8=64 单元；反射效率 η=0.8；单元边长 λ/5 |
| RIS 与 Tx 的几何 | RIS 位于发射阵列后方；中心间隔 1.5λ，约 1.61 cm |
| 相位控制 | 连续相位；或 τ=4 四个离散相位状态，即 2 bit，不是 4 bit |
| 目标数 | 2 |
| 距离搜索门 | 20～600 m |
| 计算 | 完整尺寸；主正式结果使用 double；服务器独立 MATLAB 进程并行 |

| 目标 | 俯仰角 θ（°） | 方位角 φ（°） | 距离（m） | 速度（m/s） | 反射幅度 α |
| --- | --- | --- | --- | --- | --- |
| 1 | 60.83 | 28.51 | 200.6 | 15.1 | 1.0 |
| 2 | 15.94 | 11.53 | 210.4 | −5.4 | 0.8 |

### 3.1 RIS 在当前代码中的作用

在原目标回波中加入单次反射的 Tx→RIS→目标路径：每个子载波上的有效发射系数等于“原直接路径系数 + RIS 各单元反射贡献”。相位设计增强两个目标的加权回波功率，权重为 α²，使用同一组相位覆盖子载波；没有为每个子载波独立设置 RIS 相位。接收侧沿用原目标导向向量、距离／速度估计链。

**本轮主感知实验中的 RIS 没有改变或主动相消 SI 信道。** 所以不能把主实验称作“RIS 已实现几十 dB 自干扰消除”。它验证的是 RIS 增强目标路径后对估计精度的影响。

RIS 相位使用已知目标几何进行设计，当前没有闭环目标发现、CSI 误差和相位硬件误差验证。它是已知几何下的性能验证。

### 3.2 比较的公平性与 βSI 的含义

同一次 MC 中，RIS 和无 RIS 共用发射波形及配对噪声；噪声功率固定参照该 MC 的无 RIS、无 SI 目标回波，避免 RIS 增益被噪声重新归一化抵消。MC60 还对有／无 SIC 使用同一 SI 信道、导频和配对噪声。

βSI 在代码中乘到 SI 的**幅度**上，不是直接的“干扰功率比”或 dB 值。固定其它条件，βSI 乘 10 对应 SI 功率乘 100，即增加 20 dB；但实际 SI／目标功率比还受信道、预编码和归一化影响。不能把 βSI=0.1 直接解释为 SI 比目标弱 10 dB。

### 3.3 SIC 的实现

MC60 使用 128 长度导频、带热噪声的 LS 估计：G=βSI·H_SI，Ĝ=(G·X_p+Z_p)·X_p 的右逆，随后 y_SIC=y−Ĝx。未用真实信道进行理想消除；未人为固定一个很好的估计 NMSE。矩阵 SI 为 URA Rician 模型，κSI=10。

## 4. 统计口径：汇报时必须区分

每次 MC 内，估计点与两个真值按归一化角度、距离和速度代价做贪心匹配，再计算目标 RMSE：

```text
r_m = sqrt(mean_q(error_mq^2))
中位 RMSE = median_m(r_m)                 ← 历史 PNG 和 CSV 的 median 列
平均 RMSE = mean_m(r_m)                   ← 历史 CSV 的 mean 列
标准汇总 RMSE = sqrt(mean_mq(error_mq^2))  ← 本次从保存的逐次数据复算
```

复核已完成 MAT：MC100 为 3×14×100，4200 个角度 RMSE 均有效；MC60 为 6×7×60，2520 个角度 RMSE 均有效；两组每次输出目标数均为 2。由于每次均匹配两个目标，标准汇总 RMSE 可以等价由 `sqrt(mean_m(r_m^2))` 复算。复算程序对角度、方位、距离、速度的全部逐次 RMSE 都检查了有限值。

中位数适合展示典型试验；标准汇总 RMSE 对少数严重错误更敏感。平均 RMSE 也不等于标准汇总 RMSE。输出两个估计点不等于两个目标均正确检出，本次没有据此推断正确峰命中率或检测概率。

## 5. 结果 A：完全无 SI 时，只加入 RIS 有没有用？

SNR=10 dB；SI/SIC 均关闭；完整尺寸；**单次验证**。以下为该次输出，不能理解为 100 次平均。
''']
parts += [table(['方案','总目标功率增益（dB）','θ RMSE（°）','φ RMSE（°）','距离 RMSE（m）','速度 RMSE（m/s）'],
    [[r['method'],fmt(r['target_gain_dB']),fmt(r['rmse_theta_deg']),fmt(r['rmse_phi_deg']),fmt(r['rmse_range_m']),fmt(r['rmse_velocity_mps'])] for r in no_si]), r'''

连续相位 RIS 的总目标回波功率增益为 **2.2125 dB，约 1.66 倍功率**；目标 1 和目标 2 的相对增益分别为 **1.5696 dB、52.4961 dB**。四相位 RIS 的总增益为 **1.9995 dB**，相对连续相位仅差 **0.2130 dB**。

**解释边界：** 第二目标相对增益很大，提示原直接波束在该方向的有效系数很弱。发射波束固定指向目标 1，RIS 增加另一条目标路径，可能改善目标 2 的照射和可辨识性；目前不能仅凭这些数据把具体机制断定为某一个精确零陷。

关键对照：即使完全无 SI，无 RIS 也出现 θ≈31.74°、R≈6.93 m、v≈19.55 m/s 的大误差。这说明主实验中无 RIS 的高 SNR 误差地板**不能全部归因于 SI**，还应检查固定波束、弱目标照射和估计峰匹配。

可以说“在当前无干扰场景中，RIS 也改善了估计”；不能说“已证明所有无干扰场景都获得同样倍数”。τ=8 在这一次的角度数值略优于连续方案，也不代表离散相位理论上优于连续相位；优化目标是回波功率，且这里是单次含噪估计。

## 6. 结果 B：有 SI、MC=2 冒烟

SNR=10 dB；SI 开启、SIC 关闭；点散射 SI 模型；以下是两次 MC 内 RMSE 的算术平均。
''']
parts += [table(['βSI','方案','θ 平均RMSE（°）','距离平均RMSE（m）','速度平均RMSE（m/s）'],
    [[r['beta_SI'],r['scheme'],fmt(r['rmse_theta_deg']),fmt(r['rmse_range_m']),fmt(r['rmse_velocity_mps'])] for r in smoke]), r'''

这组只用来证明全尺寸链路能运行、两种 RIS 方案均可获得改善。MC=2 不适合得出精确门限、置信区间或鲁棒性结论。

## 7. 结果 C：MC100，无 SIC 的完整 SNR 扫描

条件：βSI=0.1；SI 开启、SIC 关闭；点散射 SI；每个 SNR 100 次 MC。表中是**中位 RMSE**，对应原始三张 PNG；连续 RIS 与无 RIS 比较。
''']
snrs100 = meta['mc100']['snr_list']
parts += [table(['SNR（dB）','无RIS θ（°）','连续RIS θ（°）','无RIS R（m）','连续RIS R（m）','无RIS v（m/s）','连续RIS v（m/s）'],
    [[snr]+[fmt(row(mc100,snr,s)[key]) for key in ['median_theta_deg','median_range_m','median_velocity_mps'] for s in ['No RIS','RIS continuous']] for snr in snrs100])]
gains=[]
for snr in [0,20]:
    for key,label in [('median_theta_deg','θ'),('median_range_m','距离'),('median_velocity_mps','速度')]:
        a=float(row(mc100,snr,'No RIS')[key]); b=float(row(mc100,snr,'RIS continuous')[key])
        gains.append([snr,label,f'{a/b:,.2f} 倍',f'{100*(1-b/a):.4f}%'])
parts += ['\n\n'+table(['SNR（dB）','指标','中位 RMSE 缩小倍数','降低比例'],gains), r'''

趋势：−45 dB 时三方案几乎重合；−35～−25 dB 开始改善，但误差仍大；−20 dB 附近中位数突降；−15 dB 及更高 SNR 下，RIS 达到较小误差。提高 SNR 后，无 RIS 的角度误差仍约 31.74°，提示存在噪声以外的模型／照射／估计问题。

0 dB 时，上表支持此前口头结论：“无 SIC 加 RIS，角度中位 RMSE 缩小约 1383 倍，距离约 8998 倍，速度约 450 倍”。这些倍数指的是**RMSE 之比**，不是功率增益、定位概率或 SI 消除量。

## 8. 结果 D：MC60，同组比较有／无 SIC 和有／无 RIS

条件：βSI=0.1；矩阵 Rician SI；128 导频 pilot-LS SIC；6 方案、60 次 MC。以下三表采用**标准汇总 RMSE**，由完整 MAT 逐次数据复算，适合作为本次严谨汇报的主定量结果。为便于看清 SIC 的额外作用，主表列四种连续相位组合，τ=4 在后文单列。
''']
schemes60=['No RIS (SIC off)','RIS continuous (SIC off)','No RIS (SIC on)','RIS continuous (SIC on)']
headers=['SNR（dB）','无RIS / 无SIC','连续RIS / 无SIC','无RIS / 有SIC','连续RIS / 有SIC']
for key,label in [('rms_theta_deg','8.1 俯仰角 θ 标准汇总 RMSE（°）'),('rms_range_m','8.2 距离标准汇总 RMSE（m）'),('rms_velocity_mps','8.3 速度标准汇总 RMSE（m/s）')]:
    parts += [f'\n\n### {label}\n\n', table(headers,[[snr]+[fmt(row(pooled,snr,s,'mc60')[key]) for s in schemes60] for snr in meta['mc60']['snr_list']])]
parts += [r'''

### 8.4 为延续此前曲线：0 dB 和 20 dB 的中位 RMSE
''']
parts += [table(['SNR','方案','θ 中位RMSE（°）','距离中位RMSE（m）','速度中位RMSE（m/s）'],
    [[snr,s]+[fmt(row(mc60,snr,s)[k]) for k in ['median_theta_deg','median_range_m','median_velocity_mps']] for snr in [0,20] for s in schemes60]), r'''

同一 MC60 的 0 dB 中位数对照：关闭 SIC 时，加 RIS 后 θ、距离、速度分别缩小约 **1420、8375、584 倍**；开启 SIC 后分别约 **1331、8637、599 倍**。与第 1 节标准 RMSE 的倍数不同，是统计定义不同，不是数据矛盾。

## 9. 开启 SIC 之后，RIS 之外还增加了多少收益？

下面只比较“已经有连续相位 RIS”时，开启 SIC 的额外变化。采用 MC60 的标准汇总 RMSE；正数表示误差降低，负数表示误差增加。
''']
increment=[]
for snr in [-20,-15,-10,0,10,20]:
    values=[]
    for k in ['rms_theta_deg','rms_range_m','rms_velocity_mps']:
        a=float(row(pooled,snr,'RIS continuous (SIC off)','mc60')[k]); b=float(row(pooled,snr,'RIS continuous (SIC on)','mc60')[k])
        values.append(f'{100*(1-b/a):+.3f}%')
    increment.append([snr]+values)
parts += [table(['SNR（dB）','θ RMSE 降低','距离 RMSE 降低','速度 RMSE 降低'],increment), r'''

0 dB 及以上，SIC 在 RIS 已有收益之外的变化很小，且并非所有指标都改善；−20 dB 的部分变化受到少数大误差样本影响。未进行置信区间和配对显著性检验，不能把几个百分点甚至更小的差异宣称为统计显著的提升。

### 9.1 本轮 SIC 是否真的抑制了 SI？

代码记录的抑制量定义为 `10·log10(SI消除前功率 / SI消除后残差功率)`，不把额外数据 AWGN 算入此残差指标。正值表示 SI 净降低，负值表示估计误差形成的残差大于原 SI。MC60 的各 RIS 方案具有相同的该指标：
''']
parts += [table(['SNR（dB）','SIC 抑制量中位数（dB）','SIC 抑制量均值（dB）'],
    [[snr,fmt(row(mc60,snr,'No RIS (SIC on)')['median_sic_suppression_db']),fmt(row(mc60,snr,'No RIS (SIC on)')['mean_sic_suppression_db'])] for snr in meta['mc60']['snr_list']]), r'''

**这一轮所有 SNR 的净 SI 抑制量中位数都为负，不能说 SIC 已有效消除了 SI。** 在当前弱 SI／带噪导频配置下，LS 估计误差残差超过原 SI，是与实现公式及记录一致的解释。精度曲线仍相近，说明此误差未成为高 SNR 的主要感知限制，不能反过来证明 SIC 的抑制性能好。

更准确的结论是：“在 βSI=0.1 的本轮配置中，RIS 有效；当前 pilot-LS SIC 未体现明显额外精度收益，也未实现正的净 SI 抑制。强 SI 条件下两者能否形成互补，仍待正式扫描验证。”

## 10. 四相位、2 bit RIS 是否足够？

以下沿用 MC60 的**中位 RMSE**，对比连续与 τ=4，列出 0、10、20 dB。角度代价为 `(τ=4误差/连续误差−1)×100%`。
''']
quant=[]
for sic in ['off','on']:
    for snr in [0,10,20]:
        a=row(mc60,snr,f'RIS continuous (SIC {sic})'); b=row(mc60,snr,f'RIS tau=4 (SIC {sic})')
        quant.append([snr,sic,fmt(a['median_theta_deg']),fmt(b['median_theta_deg']),f'{100*(float(b["median_theta_deg"])/float(a["median_theta_deg"])-1):.2f}%',fmt(a['median_range_m']),fmt(b['median_range_m']),fmt(a['median_velocity_mps']),fmt(b['median_velocity_mps'])])
parts += [table(['SNR','SIC','连续 θ（°）','τ=4 θ（°）','角度误差增加','连续 R（m）','τ=4 R（m）','连续 v（m/s）','τ=4 v（m/s）'],quant), r'''

当前场景中，2 bit RIS 保留了大部分感知收益；高 SNR 的角度中位误差通常比连续相位高约 5%～13%，距离和速度基本接近。不能把这个 RMSE 差值直接称为“损失 5%～13% 的功率增益”，也不能推广到所有几何和单元数量。

## 11. 低 SNR 的中位数陷阱：−20 dB 不能称为全面稳定

MC100、SIC 关闭、连续相位 RIS、SNR=−20 dB：
''']
parts += [table(['指标','跨MC中位RMSE','跨MC平均RMSE','标准汇总RMSE'],
    [[label,fmt(row(mc100,-20,'RIS continuous')[mk]),fmt(row(mc100,-20,'RIS continuous')[ak]),fmt(row(pooled,-20,'RIS continuous','mc100')[pk])] for label,mk,ak,pk in [
        ('θ（°）','median_theta_deg','mean_theta_deg','rms_theta_deg'),
        ('距离（m）','median_range_m','mean_range_m','rms_range_m'),
        ('速度（m/s）','median_velocity_mps','mean_velocity_mps','rms_velocity_mps')]]), r'''

距离典型样本约 1.54 cm，但标准汇总 RMSE 约 40.19 m；速度典型样本约 0.311 m/s，但标准汇总约 47.33 m/s。说明大部分和少数失败样本的表现差别很大。MC60 在 −20 dB 也有类似现象。

因此，可说“−20 dB 左右出现典型性能跃迁，−15 dB 及更高 SNR 的已有样本表现更好”；不要说“−20 dB 已保证所有目标稳定厘米级”。若后续论文需要可靠性结论，应增加正确峰命中率、误差分位数、失败率和多几何统计。

## 12. 早期 RIS 相消 SI 的探索结果：与主感知实验分开汇报

这些文件也是已有 RIS 数据，但优化目标是 SI 能量或接收波束内 SI，不是角度／距离／速度 RMSE。适合作为背景或备份页。

### 12.1 论文启发的 SISO 验证

配置：5.8 GHz、20 MHz、128 子载波、36 单元 RIS、固定近场几何，优化 RIS 相位以相消 SI。独立验证配置借鉴论文，并非逐项等同论文所有仿真设置。
''']
legacy=read_csv(ROOT / 'RIS_SIC_Wu2024_验证/ris_sic_summary.csv')
selected=['No RIS','Random phase','RCG continuous','NPP tau=4','Codebook CD tau=4','Codebook CD tau=8','Codebook CD tau=16']
parts += [table(['方法','SI 抑制量（dB）'],[[r['method'],fmt(r['suppression_dB'])] for r in legacy if r['method'] in selected]),r'''

这说明在该 SISO、固定几何下，相位优化能获得较深相消；也说明离散相位需要针对离散集合优化，简单最近点量化不一定好。这里约 46.39 dB 的数字不能直接迁移到 16 发 64 收感知系统。

### 12.2 迁移到 28 GHz MIMO 后，全阵列 SI 抑制很有限

配置：16 发、64 收、64 单元 RIS，完整 1.52064 GHz 带宽内选 64 个代表子载波，优化全阵列 SI 能量。连续相位的 SI 抑制量仅 **0.4498 dB**；τ=4 的离散坐标优化约 **0.4170 dB**，τ=16 约 **0.4475 dB**。这不是全 12672 子载波的感知 MC 实验。

另一次 144 单元 RIS、64 个代表子载波的“目标接收波束内 SI”优化中，τ=4 可在该波束内抑制约 **17.48 dB**，但全阵列 SI 反而增加约 **0.372 dB**；τ=16 波束内抑制约 **19.86 dB**，全阵列 SI 增加约 **0.609 dB**。连续方案对应波束内 **5.65 dB**、全阵列 **0.054 dB**。连续优化是有限迭代局部解，不能将这些结果当作全局最优排序。

这说明“接收波束内 SI 更小”和“全阵列 SI 能量更小”不是同一目标；优化目标、RIS 自由度和宽带约束会显著影响结果。早期 rank-1 端到端输出还曾记录 10.62 dB SI 改善，但它属于另一人造信道构型，不能作为当前主感知配置的定量证据。

### 12.3 文献对代码的价值

参考文献为 Wu 等的《RIS-Based Self-Interference Cancellation for Full-Duplex Broadband Transmission》，arXiv:2407.12534。可借鉴近场 RIS 路径、反射效率、连续／离散相位集合、宽带统一相位约束，以及相位与功率优化的思路。

但原文主要研究全双工宽带通信的 SIC 能力和容量，不直接证明本项目的角度、距离、速度精度。当前主感知链路只加入目标辅助 RIS 路径，未完整实现论文的双 RIS、联合功率分配与 RIS 相消 SI 系统。汇报宜写“受文献启发的模型与验证”，不写“论文算法已完整复现并直接证明本项目精度”。

## 13. 为什么提升很大？哪些还不能确定？

已观测事实：无 SI 时也有改善；总回波功率只增加约 2.21 dB，但第二目标相对直接路径增益约 52.50 dB；主感知 RIS 不修改 SI 信道；加 RIS 后多项误差同时下降。

由此支持的机制解释是：RIS 增加目标路径，可能显著改善原来照射很弱的目标，使估计器更容易找到正确峰并匹配目标。总功率的小幅增加可以伴随弱目标很大的相对改善，因此估计精度不必按总回波功率比例线性变化。

仍未完成的验证：逐目标直接波束方向图及峰值身份审计、不同几何、不同预编码／RIS 联合设计、RIS 单元数扫描、估计失配统计。当前证据不允许把全部大幅改善都归因于 SI，也不能排除原基线对目标 2 不利造成较大的相对收益。

距离约 1.16 cm、速度约 0.222 m/s 的平台是当前已观测数值；不能直接认定为硬件极限、CRB 或唯一由某一插值步骤造成的极限。距离分辨率约 0.099 m 与参数估计 RMSE 是不同概念，不能把厘米级 RMSE 写成厘米级两目标分辨率。

本模型尚未加入 RF 前端饱和、ADC 动态范围、非线性 SI、时变信道、RIS 相位误差、目标几何误差或完整传播损耗实测标定；不能据此保证真实强 SI 硬件场景下的效果。

## 14. 今晚适合汇报的结论与下一步

**可以支持：** 当前固定几何、全尺寸仿真中，RIS 对三项估计精度有明显价值；效果不依赖于开启现有 SIC；2 bit RIS 接近连续相位；极低 SNR 下收益有限；低 SNR 需要同时报告中位数与标准汇总 RMSE。

**尚未支持：** RIS 在 βSI=10／100／1000 下仍能保持同样精度；现有 SIC 能稳定带来正 SI 抑制；RIS 能替代 SIC；所有部署位置都能得到上千倍改善；低 SNR 下输出两个估计点就代表两个目标正确检测。

下一步按优先级：

1. 完成 βSI=10、100、1000，MC50、四方案配对的角度扫描；主图采用标准汇总 RMSE，辅助中位数、失败率和 SIC 抑制量。
2. 检查目标 2 在无 RIS 下的有效发射系数、逐目标功率与峰匹配，区分弱照射改善和 SI 缓解。
3. 扩展无 SI 的多 SNR、多 MC 对照，再扫描目标几何、RIS 位置和单元数。
4. 引入 CSI／相位误差与残余 SI 灵敏度，评价实际 SIC 估计质量和 RIS/SIC 互补区间。

强 SI 扫描已经在服务器按断点机制继续计算，但未完成数据不用于今晚最终性能图。系统运行故障的诊断和修复不属于 RIS 算法性能证据；若被问及进度，说明已增加逐方案原子保存和重试即可。

## 15. 建议 PPT 页序和讲述重点

| 页 | 建议标题 | 一句话结论 | 建议素材 |
| --- | --- | --- | --- |
| 1 | RIS 辅助全双工通感：阶段结果 | 已完成精度收益验证，强 SI 鲁棒性继续验证 | 标题＋本文结论 |
| 2 | 研究问题与两种 RIS 作用 | 目标回波增强与 SI 相消是两个不同目标 | Tx→目标 / Tx→RIS→目标路径示意；SI 单独标出 |
| 3 | 全尺寸仿真配置与对照设计 | 配对波形、噪声与固定参考功率确保可比 | 第 2～4 节配置和实验清单 |
| 4 | 无自干扰时，RIS 是否有用？ | 单次全尺寸验证中也有改善，提示弱目标照射机制 | 第 5 节表格；注明单次 |
| 5 | MC100：宽 SNR 区间的表现 | 极低 SNR 无明显收益，约 −20 dB 典型性能跃迁 | 三张 MC100 原始图；标明中位数 |
| 6 | MC60：关闭 SIC，RIS 仍有明显收益 | 0 dB 标准 RMSE：35.44°→0.0287°；132.46m→1.16cm；137.71→0.226m/s | 第 1 节数字卡片和第 8 节表格 |
| 7 | 开启 SIC 后的变化 | 当前 βSI=0.1 下，额外收益很小，净 SI 抑制量为负 | 第 9 节对照与抑制量表；不夸大 SIC |
| 8 | 低比特 RIS 的代价 | τ=4 即 2 bit，大部分精度收益得以保留 | 第 10 节；适当放大角度曲线差异 |
| 9 | 为什么不能只看中位数？ | −20 dB 仍有严重失败样本 | 第 11 节三种统计对照 |
| 10 | 机制、适用边界与阶段结论 | 当前收益主要与目标路径改善一致，尚非普适性证明 | 第 13～14 节 |
| 11 | 强 SI 验证与后续计划 | βSI=10／100／1000 还没有最终结果 | 实验 E 设置；明确“运行中” |
| 备份页 | 文献 RIS-SIC 验证与 MIMO 迁移 | SISO 的深相消不能直接外推到宽带 MIMO 感知 | 第 12 节 |

## 16. 图表文件与可追溯来源

下列原始 PNG **都不是标准汇总 RMSE 图**，其中 MC100/MC60 均画中位 RMSE；插图时应补充图注“跨 MC 的中位 RMSE”。若用复算数据重画，应改图注为“标准汇总 RMSE”，不能沿用旧图标题口径。
''']

for key,label in [('mc100_angle','MC100：角度中位 RMSE'),('mc100_range','MC100：距离中位 RMSE'),('mc100_velocity','MC100：速度中位 RMSE'),('mc60_all','MC60：六方案三指标中位 RMSE 合并图'),('mc60_angle','MC60：角度中位 RMSE'),('mc60_range','MC60：距离中位 RMSE'),('mc60_velocity','MC60：速度中位 RMSE'),('no_si','无 SI 单次验证：功率增益、距离和角度柱图')]:
    parts.append('\n- '+link(label,assets[key]))
parts.append('\n\n数值和复算证据：\n')
for src in sources:
    parts.append('\n- '+link(src.name,src))
parts.append('\n- '+link('本次复算标准汇总 RMSE CSV', OUT/'recomputed_rms_across_mc.csv'))
parts.append('\n- '+link('直接从原始 MAT 导出的配置与完整性元数据',OUT/'completed_experiment_metadata.json'))
parts.append(r'''

原始图和 CSV 保持不变。本次通过 `tools/export_ris_report_evidence.m` 只读原始 MAT 并复算汇总统计，再由 `tools/build_ris_ppt_brief.py` 生成本文的数字表；没有通过平滑、挑选 MC 或改写结果提高性能。表中为便于 PPT 使用保留约六位有效数字，完整精度见 CSV/MAT。

## 17. 汇报问答速查

**问：加入 RIS 有没有明显提升？** 有。当前固定模型在中高 SNR 下，关闭或开启 SIC 都观察到明显下降；给数字时必须同时说 βSI=0.1、MC60、SNR 和统计口径。

**问：关闭 SIC 能提升多少？** MC60、0 dB 的标准汇总 RMSE：角度约缩小 1234 倍，距离约 11401 倍，速度约 610 倍；对应历史中位数倍数为约 1420、8375、584。

**问：开启 SIC 后 RIS 是否还有用？** 有。同一组 MC60、0 dB 的标准汇总 RMSE：无 RIS／有 SIC 为 35.67°、135.78 m、141.48 m/s；连续 RIS／有 SIC 为 0.02846°、0.01161 m、0.22592 m/s，分别约缩小 1253、11694、626 倍。但 SIC 相对“已有 RIS”的额外收益很小。

**问：能否说 RIS 在强 SI 下也很好？** 暂时不能。βSI=10、100、1000 的 MC50 扫描还未完成。

**问：为什么总回波只多约 2 dB，RMSE 却改善几个数量级？** RMSE 不与总功率线性对应；原直接路径对第二目标很弱，RIS 对该目标的相对增益远大于总回波增益，可能帮助估计器从失配转向正确峰。需进一步逐目标验证。

**问：这是 RIS 消除了 SI 吗？** 主感知实验不是；它只增强目标路径。早期 RIS 相消 SI 验证是另一套目标与配置，不能混用数字。

**问：2 bit 是否足够？** 当前场景保留大部分收益；中高 SNR 角度中位误差通常比连续方案高约 5%～13%，距离和速度接近，但不是所有场景的保证。

**问：检测目标数一直是 2，是否说明检测完美？** 不能。估计器输出两个候选点不等于两个正确目标峰，本轮没有用正确峰命中率作定量结论。

**问：今晚最稳妥的最终表述？** “已验证 RIS 在当前全尺寸固定几何模型下显著改善目标参数估计，且不依赖现有 SIC；下一步重点是强 SI、弱目标照射机制及多几何鲁棒性验证。”
''')

content='\n'.join(parts)
report=OUT/'RIS实验结果汇总_PPT输入稿.md'
report.write_text(content,encoding='utf-8')
archive=OUT/'RIS汇报素材包_20261010.zip'
with zipfile.ZipFile(archive,'w',zipfile.ZIP_DEFLATED) as z:
    portable=content.replace(OUT.as_posix()+'/', '')
    z.writestr(report.name,portable.encode('utf-8'))
    for folder in ['data','figures']:
        for p in sorted((OUT/folder).iterdir()):
            z.write(p,p.relative_to(OUT).as_posix())
    for name in ['completed_experiment_metadata.json','recomputed_rms_across_mc.csv']:
        z.write(OUT/name,name)
print(f'REPORT={report}')
print(f'ZIP={archive}')
print(f'CHARACTERS={len(content)}, LINES={len(content.splitlines())}')
