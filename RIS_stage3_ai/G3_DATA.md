# G3 数据生成：已实现的链路与使用方法

日期：2026-10-20。本文记录 G3 数据部分；训练选模及六方法比较现已另行实现，见 G3_TRAINING.md、G3_COMPARISON.md。服务器只完成全尺寸成本试验，尚无正式曲线或新 AI 正式训练任务。

## 输入数据从哪里来

```text
按几何场景划分：训练 / 验证 / 独立测试
    ↓ 仿真器可见场景真值
原模型、原 DD-ZF 波束、全 CPI 的参考回波功率
    ↓ 按 SNR 确定噪声方差
前半 CPI 的 DD 回波 + 固定种子的复高斯噪声
    ↓ 粗估计器看观测，真值字段置为 NaN
两个目标的粗距离 / 粗速度 / 粗角度
    ↓ 保存输入文件
粗估计 + 已知用户角度 → DesignContext → 后续训练器
```

SNR 的噪声标定与旧实验相同：每个场景用 DD-ZF 的整个 CPI 平均回波功率作为参考；RIS 方案不能重新把自己的较强回波归一化掉。不同方法的后半 CPI 使用同一个 `fine_seed` 和相同分块大小，保证同一噪声 realization。这里登记该种子，后半 CPI 和精估计将在比较脚本中接入。

训练输入来自真实模拟观测的粗估计，不用真值加随机扰动来替代。低 SNR 粗估计错误不会按真值筛除。非有限值或程序异常会中止并留下失败记录，不会伪造输入或算作完成。

## 全量与冒烟的区别

| 项目 | 全量 | 本地 SMOKE |
|---|---:|---:|
| 子载波 | 12672 | 512 |
| 发射阵列 | 4×4 | 4×4 |
| 接收阵列 | 8×8 | 4×4 |
| RIS | 8×8，2 bit | 8×8，2 bit |
| 粗 / 精 CPI 符号数 | 128 / 128 | 32 / 32 |
| 精估计迭代上限（本数据阶段未调用） | 12 | 2 |
| 训练场景 | 128 | 2 |
| 验证场景 | 32 | 1 |
| 训练/验证 SNR | −30、−5、20 dB | 20 dB |
| 粗输入样本数 | 384 + 96 = 480 | 2 + 1 = 3 |

频率、噪声、通信门限、反射模型和双精度沿用协议。全量使用每个子载波和配置内的每个天线、符号；128 点分块只是控制内存，不做子载波抽样。全量单个粗回波临时文件约 1.66 GB，逐样本处理后删除；崩溃遗留的 work 临时目录可能仍占空间，需要检查后清理。

数据集只保留粗输入和审计数据，原始回波可根据参数、种子、源码与 NumPy/SciPy 版本再生成。种子由场景、SNR、噪声重复序号和粗/精块名确定，运行顺序或断点续跑不会改变它。几何按目标排序再计算身份；训练、验证、新测试和旧固定场景不会重复使用同一组目标空间坐标。

## 本地只运行冒烟

在仓库根目录执行（已有独立环境）：

```powershell
.venv-stage3-ai/Scripts/python.exe -X utf8 -m RIS_stage3_ai.run_checks --suite dataset
.venv-stage3-ai/Scripts/python.exe -X utf8 -m RIS_stage3_ai.generate_dataset --smoke --output RIS_stage3_ai/data_smoke_g3a --limit 1
.venv-stage3-ai/Scripts/python.exe -X utf8 -m RIS_stage3_ai.generate_dataset --smoke --output RIS_stage3_ai/data_smoke_g3a
.venv-stage3-ai/Scripts/python.exe -X utf8 -m RIS_stage3_ai.generate_dataset --output RIS_stage3_ai/data_smoke_g3a --status
```

第一条生成命令最多新增 1 个样本，状态为 `PAUSED_LIMIT`，仍显示总量 3，不能显示为完成。第二条跳过已校验的第一个样本，补齐其余两个；再执行不会重新生成已经保存的样本。

同一输出目录不接受不同的协议、相关源码或数据生成环境版本；需要继续时保留原代码/环境，或为新实验使用新目录。后续新建训练文件不会改变数据生成源码清单；修改清单内文件会改变数据身份。

## 服务器全量命令（尚未部署执行）

服务器独立 AI 环境创建后，从部署仓库根目录运行：

```bash
python -m RIS_stage3_ai.generate_dataset --output RIS_stage3_ai/data_full_v1 --prepare-only
python -m RIS_stage3_ai.generate_dataset --output RIS_stage3_ai/data_full_v1 --limit 1
python -m RIS_stage3_ai.generate_dataset --output RIS_stage3_ai/data_full_v1
python -m RIS_stage3_ai.generate_dataset --output RIS_stage3_ai/data_full_v1 --status
```

第一步只注册配置，不做仿真，因此本地也允许检查全量清单。正式计算会核对 Linux 主机名 `jzm`；命令行没有本地绕过选项。第二步是服务器的全尺寸单样本试运行，执行后应结合 CPU/内存/磁盘和耗时决定后续资源安排。当前为单进程、每进程 4 个 BLAS 线程，独占输出目录；不要在同一目录启动多个写进程。

这些命令仅生成数据。需要等比较/服务管理脚本完成和完整链路冒烟通过，才会按计划部署并启动服务器正式实验。

## 保存了什么，怎样判断真的完成

- `manifest.json`：全协议、场景真值审计表、待生成训练/验证清单、所有噪声种子、相关源码哈希和生成环境版本；整个身份做 SHA256。
- `inputs/样本ID.json`：只有数据集 ID、样本 ID、粗估计和已知用户角度，没有目标真值。
- `samples/样本ID.json`：成功提交标记，带输入文件哈希、样本/数据集身份、参考功率、噪声方差、实际观测尺寸与分段计时；自身也做校验。
- `failures/时间戳_PID.json`：异常类型、调用栈、样本身份和进程信息；成功续跑后仍保留历史失败。
- `progress.json`：逐样本落盘后更新的完成数、预期数和失败尝试数。
- `state.json`：当前样本、进程/主机、更新时间及运行/限量停止/失败/完成状态。被强制杀进程后可能停留在旧状态，不能只凭 `RUNNING` 判断进程仍存活。

`--status` 会重新检查样本身份、输入哈希和真实文件数；孤立的输入文件不算完成，损坏或身份冲突会报错，不会悄悄覆盖。只有全部预期记录通过检查才显示 `complete=True`。这表示粗输入数据集完成，并不表示训练或 RMSE 比较完成。

## 本阶段验证

8 项数据检查通过：正式场景/样本数与种子隔离；全量尺寸/服务器限制；纯注册不触发计算；真实回波与 NaN 真值粗估计、续跑和输入隔离；注入磁盘故障后保留记录并续跑；锁与清单身份；孤立/损坏输入处理；不同波束/RIS 的配对 AWGN。

核心算法的 9 项检查也重新通过。证据见 `evidence/g3_dataset_checks.json` 和 `evidence/g2_regression_after_dataset.json`，内含实际测试、耗时、版本和源码 SHA256。本阶段没有 RMSE 提升或训练加速的实测结论。
