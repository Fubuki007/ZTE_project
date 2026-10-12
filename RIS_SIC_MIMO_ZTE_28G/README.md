# RIS-SIC MIMO 企业配置验证

配置：28 GHz，B=1.52064 GHz，16 发（4x4），64 收（8x8），取 64 个代表性子载波，RIS 放在设备内部近场。

## 结论 A：一个 RIS 压完整 MIMO SI 矩阵效果有限

用 run_ris_sic_mimo_zte.m 或 sweep_mimo_ris.m 测试总 MIMO SI 目标：即使 N_ris 从 36 增至 256，单位模连续相位 RCG 的总 SI 抑制也只有约 0.4 - 1.4 dB。原因是 RIS 近场通道矩阵条件数很大，很多空间模式需要很大的等效幅度，单位模 RIS 无法提供。

## 结论 B：目标接收波束 + 码表坐标下降效果好

运行 run_mimo_ris_targetbeam_simple.m。当前 N_ris=144，d_sep=1.5 lambda，x_c=1.5 lambda：

| 方案 | 目标波束抑制 | 总 SI 抑制 |
|---|---:|---:|
| No RIS | 0.00 dB | 0.00 dB |
| Random phase | 0.83 dB | -0.17 dB |
| RCG continuous | 5.65 dB | 0.05 dB |
| NPP tau=2 | 3.24 dB | -0.08 dB |
| Codebook CD tau=2 | 15.49 dB | -0.18 dB |
| NPP tau=4 | 4.72 dB | -0.04 dB |
| Codebook CD tau=4 | 17.48 dB | -0.37 dB |
| NPP tau=8 | 5.04 dB | 0.04 dB |
| Codebook CD tau=8 | 18.94 dB | -0.47 dB |
| NPP tau=16 | 5.85 dB | 0.04 dB |
| Codebook CD tau=16 | 19.86 dB | -0.61 dB |

结论：单元素相位码表 + 坐标下降在目标波束指标上明显优于 RCG 和 NPP；tau=8 即可约 19 dB。总 MIMO SI 略升，说明 RIS 把 SI 从目标波束搬到了其他空间模式。若系统用目标波束接收 + 数字 SIC，这个结果可用；若 KPI 是 ADC 前总 SI，需要多 RIS 或联合接收波束设计。

## 码表方案

每个 RIS 单元候选相位：C = exp(1j * 2*pi*(0:tau-1)/tau)。

坐标下降：固定其他单元，遍历第 n 个单元的 tau 个候选相位，选目标波束残余 SI 最小者；对 n=1..N_ris 依次做，重复若干轮。复杂度 O(N_ris * tau * M * sweeps)。无 CSI 时可用已知导频测量每个候选下的目标波束 SI 功率，选最小者。

## 推荐文件

- run_mimo_ris_targetbeam_simple.m：目标波束 + 码表，推荐先跑这个
- run_ris_sic_mimo_zte.m：总 MIMO SI 目标，展示单 RIS 局限
- sweep_mimo_ris.m：RIS 尺寸/几何扫描
- generate_ris_mimo_channels.m：生成 H_direct, G_tx, G_rx
- build_mimo_ris_objective.m：展平 MIMO 目标
- zte_mimo_ris_targetbeam.csv：目标波束结果

## 对主项目的建议

1. 不要直接把论文 SISO 公式当 64 收 MIMO 目标；
2. 先用目标接收波束内的 SI 作为 RIS 优化目标；
3. 离散 RIS 用单元素码表 + 坐标下降，tau=8 起步；
4. 总 SI 若仍需下降，考虑多 RIS 面板、增大 RIS 孔径、与 design_precoder 的 nullspace/lagrange 联合优化、目标波束接收后数字 SIC。
