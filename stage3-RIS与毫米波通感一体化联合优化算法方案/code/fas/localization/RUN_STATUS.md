# 定位导向FAS参考搜索：运行状态

2026-11-03，北京时间。**全量实验已启动，尚未完成，目标继续保持进行中。**

## 已验证

- 本地仅运行smoke：回波重建误差2.17e-15；物理导数误差3.33e-8；Fisher信息误差1.40e-9；log(PEB)控制梯度误差1.14e-10；约束梯度误差2.99e-10。
- 本地完整smoke链路、逐样本保存、汇总和断点续跑通过，2/2。粗估计失败样本也保留。
- 服务器MATLAB R2022b数学检查通过。
- 服务器3个完整尺寸几何、固定/FAS共6项，与2026-11-02独立回波差分诊断比较：FIM相对差不超过3.05e-6，PEB相对差不超过1.46e-6。
- 完整尺寸pilot（MC0，10dB）完成，含实际定位及双方真值辅助搜索，耗时124.16秒。实际设计的固定/FAS搜索分别29.01/26.83秒。
- pilot用于验证与计时，不能作为总体性能结论。单例FAS对定位优化固定阵列的PEB改善约2%，仍需全量验证。
- 新搜索模块在冒烟时发现局部循环变量`round`遮蔽MATLAB取整函数，已改名并重新通过测试；这不是原正式实验的代码问题。

## 正式运行

- 启动时间：2026-11-03约12:55，北京时间。
- 正式源码release：`554ff78b42b720939272c60e0d9f0cc37acd82a9`，已推送并核验远端。
- 正式manifest：`cf61e890580211c181c88b89fed9638d6bbf0b03f69f3390040bfb1805919b0c`。
- 服务器目录：`/home/jzm123/AAA_ZTEproject/RIS_stage3_matlab_fas/releases/554ff78b42b720939272c60e0d9f0cc37acd82a9/code/fas/localization/results_full`。
- 输入：原aafa6808 release的完整300MC×13SNR断点，复用相同几何、粗估计和噪声/符号种子。
- 4个worker，每个最多2个计算线程，各负责975个样本；监督PID223537，初始worker PID223541–223544。后续必须核对真实进程和日志，不以记录的PID或状态文件单独认定仍在运行。
- 正式比较6种结果：旧固定能量设计、旧FAS能量设计guard0/4、新固定定位设计、新FAS定位设计guard0/4。
- 10dB下全部300个几何另保存双方同等真值先验的参考设计与PEB。
- 原始正式模型、孔径、功率、SINR、阵列、子载波和CPI保持；近似、设计先验和搜索预算见README。
- 预计约半天至一天，受样本难度和并行开销影响；应以实际断点数量和耗时重新估计。

## 后续必须完成

1. 核对任务是否真实存活；如失败，读取具体报错，先修复验证，再按manifest规则处理续跑，保留已有结果。
2. 等全部3900个新样本及300个oracle参考完成并汇总，确认`state=COMPLETE`且`progress.complete=true`，核对各SNR300次。
3. 取回精选CSV、图表、参数和进度；分析新FAS对新固定定位设计的配对区间，区分波束目标改变收益与天线位置收益。
4. 检查搜索的实际位移、收敛、可行性、量化损失和连续参考值。如信息增益与实际定位不一致，进一步定位模型、算法或实现原因，不能直接宣布方向可行。
5. 如发现明显FAS收益，补充合理的固定非均匀阵列对照，以判断是否需要在线位置自适应；如收益仍小，给出当前模型下的止损建议，不能把参考搜索当作经证明的理论上界。
6. 写最终结论与限制，推送阶段成果；只有全部需求有证据满足才将用户goal标为complete。

## 运行期间的追加核查（2026-11-03）

- 试跑记录中部分SQP步骤用满40次迭代，但末尾变化很小，因此补做固定与FAS双方都增加至160次迭代、2轮RIS搜索的对照。预先指定MC0、1、2，10dB，分别检查粗估计设计和oracle设计；这3例只用于收敛诊断，不替代300MC正式统计。
- 收敛核查脚本 `tools/loc_convergence_audit.m`，执行版本 `5de7e529c55cb4a07bdb26963686db9335c33201`。
  服务器目录 `/home/jzm123/AAA_ZTEproject/RIS_stage3_matlab_fas/audits/convergence_20261103_5de7e52/`，初始PID225258。
  `results/progress.json`记录真实阶段，每个几何单独保存MAT/JSON；未生成的正式输入会等待，不重算、不替换原正式结果。
- MC0追加预算后，固定/FAS粗估计目标分别再改善0.200%/0.062%，相对增益由1.974%变为1.839%；oracle相对增益由1.871%变为1.802%。其余两例仍需完成和核查。
- 修正新汇总器的边界情况：`Inf` PEB表示不可辨识，必须保留在均值并单独计数，只有未进行信息计算的`NaN`可排除。原正式运行的不可变release仍使用原汇总器，**完成后必须执行修正版重新汇总，再取回最终结果**。该修正不需要重跑定位或改动原始断点；是否实际出现Inf需从全量结果确认。
- `tools/test_loc_aggregation.m`用本地smoke复制件注入一个Inf进行验证，检查Inf保留、奇异计数和缺失信息区分，测试已通过。注入数据仅存在于`tmp/localization_inf_smoke`，不用于性能结论。
- 重新汇总使用 `tools/finalize_loc_aggregation.m` 与修正后的 `aggregate_localization.m`，放在独立服务器目录；调用 `finalize_loc_aggregation(original_code, run)`。它要求全量及300个oracle完成，先保存旧汇总到`summary_before_peb_fix/`，再汇总并写`aggregation_revision.json`记录实际聚合代码哈希。部署目录在后续记录中补充；不可覆盖正在运行release的源码。

## 操作

项目根目录PowerShell：

```powershell
tools/ris-localization-server.ps1 status -Release 554ff78b42b720939272c60e0d9f0cc37acd82a9
tools/ris-localization-server.ps1 fetch -Release 554ff78b42b720939272c60e0d9f0cc37acd82a9
```

fetch在汇总完成后运行；原始逐样本MAT保留服务器。运行代码位于独立release，后续本地文档修改不影响正在执行的源码。源码、脚本、文档与精选检查证据进入Git；环境、凭据、缓存、历史未跟踪文件和大批原始结果排除。
