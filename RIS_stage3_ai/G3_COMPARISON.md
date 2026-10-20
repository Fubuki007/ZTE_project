# 六方法比较与三项 RMSE

日期：2026-10-20。本阶段实现冻结模型后的六方法配对比较、角度/距离/速度 RMSE、配对置信区间和固定迭代配置的实际耗时统计。正式全量 RMSE 尚未运行；相同时间预算扫描与后台服务器调度仍待完成。

## 比较链路

先检查训练已完成、选中权重哈希和数据集身份，随后只使用登记的新测试场景及旧固定场景。每个案例共用一个 DD 粗观测；六种方法的精观测使用相同噪声方差、噪声种子、分块大小、阵列与 CPI。每个案例的方法执行顺序用固定种子打乱，续跑时顺序不变。

| 方法 | 配置 |
|---|---|
| DD joint | 关闭 RIS；DD 全 CPI 初值与联合精估计，沿用原基线 |
| Original RIS | AO/SCA/相位扫描 3/3/2 |
| Short RIS | 1/1/1 |
| Untrained physics | 6 层初始步长网络 + 1/1/1 校正 |
| Learned physics | 验证集选出的冻结网络 + 同一 1/1/1 校正 |
| Extended RIS | 8/5/3，更长传统计算预算，不声称全局最优 |

RIS 方法共用粗估计；精估计器只接观测及已知发射配置，其 Config.truth 置为 NaN。真值仅在回波模拟和最后评分时使用。若选中初始模型，图中会明确标识，不能把未训练权重叫作训练提升。

全量共 2156 个配对案例：新场景 1056、旧场景 1100；每案例 6 种方法，总计 12936 个方法结果。本地冒烟只有两个案例、12 个方法结果，物理尺寸沿用已声明的 SMOKE 配置。

## 统计定义

每个方法、每个案例只做一次基于三维方向差的 Hungarian 目标匹配，距离、速度和角度共用这一匹配。方位角误差包裹到 [−180°,180°)。

- 角度 RMSE：对案例、两个目标、theta/phi 两分量的平方误差求均值再开方，单位度。
- 距离 RMSE：对案例、目标的距离平方误差求均值再开方，单位 m。
- 速度 RMSE：对案例、目标的基站径向速度平方误差求均值再开方，单位 m/s。

新场景按几何场景做 cluster bootstrap，同一场景的三个噪声重复不能当作三个独立场景；旧场景按 MC 试验重采样。方法、目标和三个指标保持配对。另给出各方法相对 Original RIS 的 RMSE 差值及配对区间。只有一个独立单位时不输出看似精确的置信区间。

不裁剪误差，不按真值丢掉离群点。物理/数值算法失败保留终态记录；基础设施异常会写失败日志并停止，续跑补算。只要某方法在该 SNR 的预期案例中存在失败或缺失，其主 RMSE 和 CI 就留空；成功样本的条件 RMSE 另列，明确成功数/失败数/缺失数。完成全部终态记录不代表所有算法都成功。

## 时间与文件

设计时间包含上下文构造、网络输入/输出传输、物理更新、约束校正、回退及最终审计，CUDA 同步后计时。模型加载单独记录，不预热；首个案例可能包含初始化成本。处理时间包含公共粗估计、设计和精估计，模拟回波生成耗时单列，不把仿真器耗时当成在线算法延迟。

当前仅比较固定迭代配置的实测耗时。不能据此声称完成相同时间预算比较；该扫描仍需单独实现。

每个“案例×方法”保存独立原子 JSON，包含噪声/案例身份、估计、统一匹配误差、设计审计与分段时间。粗观测记录另存并做 SHA256 关联；相位与波束/相位哈希保留，完整波束矩阵和巨大原始回波不持久化，可通过已冻结源码、权重、参数和种子重建。恢复只补缺失方法，并重新验证公共粗估计。每次写入更新实际方法数与完整配对案例数。

## 命令

本地从仓库根目录执行：

```powershell
.venv-stage3-ai/Scripts/python.exe -X utf8 -m RIS_stage3_ai.run_checks --suite comparison
.venv-stage3-ai/Scripts/python.exe -X utf8 -m RIS_stage3_ai.run_comparison --dataset RIS_stage3_ai/data_smoke_g3a --training RIS_stage3_ai/checkpoints_smoke_training_g3b_v2 --output RIS_stage3_ai/results_smoke_comparison_g3c --smoke --limit 2
.venv-stage3-ai/Scripts/python.exe -X utf8 -m RIS_stage3_ai.run_comparison --dataset RIS_stage3_ai/data_smoke_g3a --training RIS_stage3_ai/checkpoints_smoke_training_g3b_v2 --output RIS_stage3_ai/results_smoke_comparison_g3c --smoke
.venv-stage3-ai/Scripts/python.exe -X utf8 -m RIS_stage3_ai.aggregate --source RIS_stage3_ai/results_smoke_comparison_g3c --output RIS_stage3_ai/results_smoke_comparison_g3c/metrics
```

服务器正式比较命令（尚未执行）：

```bash
python -m RIS_stage3_ai.run_comparison --dataset RIS_stage3_ai/data_full_v1 --training RIS_stage3_ai/checkpoints_full_v1 --output RIS_stage3_ai/results_full_v1 --device cuda:0
python -m RIS_stage3_ai.aggregate --source RIS_stage3_ai/results_full_v1 --output RIS_stage3_ai/results_full_v1/metrics
```

未完成时，聚合默认拒绝，必须显式 `--partial` 才能查看部分记录；仍不会为缺失方法编造全样本 RMSE。输出包括审计 JSON、CSV，以及新/旧测试各三张 PNG/SVG 图。冒烟图全部标明“不作为科学结果”。

## 全尺寸耗时试运行

`profile_runtime.py` 在服务器保留所有物理尺寸，选择训练和验证各一个场景，分别重复测量连续训练步、量化训练步和验证校正。输出独立的“运行成本试验”，不产生可用于论文比较的正式模型。它登记源码、设备、参数、计时及 GPU 峰值分配显存，并按既定更新次数换算训练时长。

估计只覆盖抽取的几何场景和首个 SNR；最小/最大换算值不是置信区间。检查点 I/O、资源竞争和完整六方法精估计比较不在预测里。GPU 环境使用 `setup_server_env.sh` 建立独立 `.venv311`，原 Stage-3 环境不修改。部署使用独立 release 目录；不覆盖旧实验源码。
