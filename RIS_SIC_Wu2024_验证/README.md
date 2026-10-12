# RIS-SIC Wu 2024 独立验证

本文件夹是对论文 Wu et al., RIS-Based Self-Interference Cancellation for Full-Duplex Broadband Transmission, arXiv:2407.12534 的独立 MATLAB 验证，不修改 ZTE_project 主流程。

## 1. 目录内容

| 文件 | 作用 |
|---|---|
| ris_sic_params.m | 论文仿真参数、几何、RIS 硬件约束 |
| nearfield_xi_cells.m | 论文式(3)近场功率增益的向量化实现 |
| generate_ris_si_channels.m | 生成直达 SI 与 RIS 级联 SI 信道 |
| rcg_phase_optimize.m | 连续相位 RCG 优化（复圆流形） |
| phase_quantize_npp.m | 离散相位最近点投影 NPP |
| codebook_coordinate_descent.m | 单元素相位码表 + 坐标下降 |
| codebook_random_search.m | 全局随机配置码表搜索 |
| eval_sic_performance.m | 残余 SI、抑制 dB、论文式(20) SIC capability |
| run_ris_sic_main.m | 主验证脚本，输出 .mat/.csv/.png |

## 2. 运行方法

在 MATLAB 中先切换到本目录，然后运行：

    run_ris_sic_main

命令行方式：

    E:\Matlab R2024a\bin\matlab.exe -batch "run_ris_sic_main; exit(0);"

## 3. 当前模型

第一版按论文做 SISO 全双工设备内部 RIS：

- 载频 5.8 GHz，带宽 20 MHz，子载波数 128；
- RIS 单元数 36（6x6），反射效率 eta=0.8；
- 收发天线坐标：(正负 0.02, 0, 0.04) m；
- 直达 SI 与 RIS 级联 SI 都用论文式(1)-(10)的近场模型；
- RIS 相位在全部子载波上共用，符合论文不同子载波同一相移的假设；
- 对比方案：
  - No RIS：RIS 关闭；
  - Random phase：随机单位模相位；
  - RCG continuous：论文连续相位算法；
  - NPP tau：连续解投影到离散码表；
  - Codebook CD tau：单元素码表 + 坐标下降；
  - Random codebook tau,K：全局随机配置码表。

## 4. 当前运行结果

最近一次运行结果：

| 方案 | 残余 SI (dB) | 抑制 (dB) | SIC capability (dB) |
|---|---:|---:|---:|
| No RIS | 0.00 | 0.00 | 21.07 |
| Random phase | -0.43 | 0.43 | 21.51 |
| RCG continuous | -46.39 | 46.39 | 56.80 |
| NPP tau=2 | -10.15 | 10.15 | 31.21 |
| Codebook CD tau=2 | -10.21 | 10.21 | 31.27 |
| NPP tau=4 | -12.71 | 12.71 | 33.77 |
| Codebook CD tau=4 | -29.29 | 29.29 | 49.56 |
| NPP tau=8 | -28.13 | 28.13 | 48.68 |
| Codebook CD tau=8 | -40.65 | 40.65 | 56.01 |
| NPP tau=16 | -23.51 | 23.51 | 44.40 |
| Codebook CD tau=16 | -44.58 | 44.58 | 56.64 |
| RCG from CD tau=16 | -46.39 | 46.39 | 56.80 |
| Random codebook tau=4, K=256 | -4.57 | 4.57 | 25.64 |
| Random codebook tau=8, K=256 | -3.17 | 3.17 | 24.24 |

结论：

1. 连续相位 RCG 在当前模型下可达到约 46 dB 的传播域 SI 抑制；
2. 离散相位单独做 NPP 会明显退化；
3. 单元素码表 + 坐标下降能显著恢复离散 RIS 性能，tau=8 时约 40.6 dB，tau=16 时约 44.6 dB；
4. 全局随机配置码表在 36 个单元、K=256 时只有约 4-5 dB，说明不能只靠随机码表暴力搜索；
5. 实际可落地的码表方案更适合码表 + 坐标下降/分层搜索，而不是全局随机码表。

## 5. 码表方案怎么弄

### 5.1 最直接：单元素相位码表 + 坐标下降

每个 RIS 单元的候选相位预先定义为：

    C = exp(1j * 2*pi*(0:tau-1)/tau);

然后：

1. 初始化所有单元相位；
2. 固定其余 N_ris-1 个单元，遍历第 n 个单元的 tau 个候选相位；
3. 选择使残余 SI 最小的相位；
4. 对 n=1,...,N_ris 依次执行；
5. 重复扫描直到不再改善。

优点：

- 复杂度 O(N_ris * tau * M * sweeps)，远低于全局穷举 tau^N_ris；
- 不需要连续相位解，也不需要 RCG；
- 如果 CSI 已知，可直接算目标函数；
- 如果没有 CSI，可以用已知导频测量每个候选下的接收 SI 功率，同样是最小化。

本文件夹里的 codebook_coordinate_descent.m 就是这一版。

### 5.2 分层/分组码表

当 N_ris 很大时，可以先把 RIS 分成若干组：

- 第 1 层：每组用一个块码字，粗调组间相位；
- 第 2 层：在选中的粗码字附近，对组内单元做单元素坐标下降；
- 第 3 层：必要时再做局部随机扰动。

这本质上是分层码本 + 局部搜索，复杂度可以从 O(N_ris * tau) 降到 O(G * tau + N_ris * tau_local)，其中 G 是分组数。

### 5.3 全局配置码表

全局码表大小为 K，每个码字对应一个 RIS 配置，选择使残余 SI 最小的码字。

但当前结果表明：36 单元时 K=256 远远不够，性能只有约 4-5 dB。全局码表更适合：

- N_ris 较小（例如 4-8）；
- 或者结合先验构造而不是随机撒点；
- 或者作为初值，再进入坐标下降。

### 5.4 推荐落地顺序

1. 先做单元素码表 + 坐标下降，验证离散 RIS 能否复现连续相位的大部分增益；
2. 如果控制周期/导频开销允许，直接用这个方案；
3. 如果 RIS 单元很多，改成分组分层码表；
4. 全局随机码表只作为 baseline，不建议作为主方案。

## 6. 与主项目 ZTE_project 的关系

当前文件夹只做 SISO、宽带 SI 验证，原因是：

- 主项目是 28 GHz、16 发 64 收、1.52064 GHz 聚合带宽的 MIMO-ISAC；
- 论文是 5.8 GHz、SISO 全双工通信；
- 直接套论文式(20)/(31)/(47) 到 MIMO-ISAC 需要重新定义目标函数。

后续如果要接入主项目，建议：

1. 把 H_SI_eff(phi) = H_direct + G_r * diag(phi) * G_t 加进 simulate_radar_channel_3d.m；
2. 把 codebook_coordinate_descent.m 的离散码表搜索思路接到 design_precoder.m 外层；
3. 评估指标同时看 pre-SIC SI 功率与 post-SIC residual / RMSE；
4. 先做中心子载波，再扩展到多子载波；全 1.52 GHz 带宽下，公共相位 RIS 的性能预计会下降，需要考虑子带 RIS 或延时 RIS。

## 7. 已知限制

- 当前只验证 SISO，且只考虑传播域 SI 对消，没有加入数字 SIC；
- 直达信道和 RIS 级联信道都按论文近场模型生成，未加入随机 CSI 误差；
- 没有加入目标回波经过 RIS 的二次路径；
- 连续相位 RCG 有局部最优问题，已用多次随机重启，但不同随机种子结果会有小幅波动。

