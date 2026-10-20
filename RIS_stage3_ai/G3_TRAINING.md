# G3 训练与验证选模

日期：2026-10-20。本阶段完成全量训练脚本和本地冒烟，尚未运行服务器正式训练。六方法精估计比较与 RMSE/置信区间现已实现，见 G3_COMPARISON.md；服务器全尺寸成本试验见 RUNTIME_ESTIMATE.md。相同时间预算扫描与后台调度仍待完成。

## 现在接通了什么

```text
完整、校验通过的训练/验证粗输入数据集
    ↓ 固定输入哈希，按场景使用既定划分
粗估计 + 已知通信模型 → 无真值 DesignContext
    ↓ 6 层物理梯度更新，学习 12 个有界步长
训练集：连续相位预热 → 2 bit 量化感知训练
    ↓ 每轮训练后，用验证集逐样本评估
硬量化候选 → 同预算物理校正 → 全频点约束检查
    ↓ 按预先声明的验证指标选模
冻结模型、权重哈希和选择证据 → 后续六方法比较器
```

训练器不把目标真值作为输入或监督标签，也不读取测试集回波或 RMSE。使用粗估计构造的物理目标进行无监督优化。验证也只看粗输入下的设计效果；目标真值只留在数据生成侧的审计注册表。

## 预先声明的完整训练预算

`training_v1.json` 独立记录训练超参数，避免每次调整训练器都改变已经生成的数据身份。超参数、数据文件哈希、源码、Python/NumPy/SciPy/PyTorch 版本、设备及确定性设置共同决定训练身份；更换这些内容必须新建输出目录。

| 设置 | 全量 | 本地 SMOKE |
|---|---:|---:|
| 网络层数 / 可学习标量 | 6 / 12 | 6 / 12 |
| 总训练轮数 | 20 | 2 |
| 连续相位轮数 | 前 5 轮 | 第 1 轮 |
| 量化感知轮数 | 后 15 轮 | 第 2 轮 |
| 训练 / 验证样本 | 384 / 96 | 2 / 1 |
| Adam 更新总数 | 7680 | 4 |
| 验证样本处理总数（含初始模型） | 2016 | 3 |
| 每步样本数 | 1 | 1 |
| Adam 学习率 / 梯度范数裁剪 | 0.01 / 5 | 0.01 / 5 |

全量保留 12672 个子载波、原阵列和 CPI，不抽样频点，不以冒烟样本代替正式数据。网络、物理模型均使用双精度。训练时对展开过程求导；量化感知阶段的前向为四档相位，反向采用直通估计，这是有偏近似。

每轮用模型种子和轮次确定训练样本顺序；续跑不会重新洗牌或遗漏同一轮未处理的样本。禁用 TF32，开启 PyTorch 确定性运算。跨 CPU/GPU、版本或设备的逐位一致性没有经过验证；恢复要求训练身份一致。CUDA 高阶梯度的显存与运行速度必须在服务器全尺寸试运行后确认。

## 验证集到底选什么

首先验证未训练的初始模型，之后每个 epoch 都验证全部验证样本。所有验证候选均使用硬量化，接同一个 1/1/1 校正预算；失败回退预算为旧算法 3/3/2。原始、量化、校正审计及回退原因/耗时保存在逐样本事件里。

模型排序规则为：先比较物理失败样本数，失败少的优先；失败数相同时，比较所有验证样本的“校正后最弱目标照射”平均值，越高越好。失败样本以 0 分保留在分母中；回退得到可行结果的样本使用其实际结果并单独记录回退次数。完全相同时保留更早的模型。

因此初始模型也可能胜出。输出会明确记录 `best_epoch=0`、`selected_weights_changed=false`，不能将它包装成训练带来的提升。`current_weights_changed=true` 只说明训练更新过参数，也不能证明选中模型更好。

**验证指标不是 RMSE。** 照射增强是否带来角度、距离、速度精度改善，必须在冻结模型后用独立测试集和相同噪声的六方法比较回答。物理校正与回退耗时也必须纳入后续比较。

## 断点恢复与审计

每个训练或验证样本结束后保存模型、Adam 状态、Python/NumPy/PyTorch/CUDA 随机状态、当前轮次/位置、验证统计和最优权重。

保存顺序是：写完整检查点文件并校验 → 写事件副本 → 原子替换 `latest.json`。检查点记录上一个已提交检查点的指针。只有从 `latest.json` 沿父指针能够追溯到的事件才算有效训练记录；`committed_events()` 会验证这条链。中断留下的孤立文件不会被当成新的训练步骤。

失败时保存异常和样本信息，再停止。重启从最近一次有效提交继续；若中断发生在 Adam 更新之后、检查点提交之前，该步会从上一个已保存的优化器状态重算。输入损坏、代码/参数变化、模型校验失败、设备不可用不会静默降级或混入已有实验。

`load_selected()` 只接受训练与验证计数完整的检查点，并核对推理物理代码和权重哈希；默认拒绝冒烟模型。供冒烟比较调用时必须显式 `allow_smoke=True`。

目录内容：

- `manifest.json`：数据身份、输入哈希、参数、源码与运行环境。
- `checkpoints/`：不可变的逐样本模型/优化器快照与父指针；保留历史，服务器需预留磁盘空间。
- `events/`：逐样本损失、梯度、验证审计、用时和 CUDA 峰值分配显存的便于查看副本；统计时通过提交链排除孤立副本。
- `latest.json`：最近一次有效提交的位置和文件 SHA256。
- `progress.json` / `state.json`：进度快照和进程/当前样本信息；被强制终止后状态文字可能过时。
- `failures/`：历史失败记录，续跑成功也保留。

`--status` 会校验最新检查点后报告真实的已提交训练更新数、验证处理数和选模情况。它不宣称进程仍在运行；服务端进程状态在后续运行管理脚本中处理。

## 本地冒烟命令

从仓库根目录执行，使用已创建的独立环境和完整冒烟数据集：

```powershell
.venv-stage3-ai/Scripts/python.exe -X utf8 -m RIS_stage3_ai.run_checks --suite training
.venv-stage3-ai/Scripts/python.exe -X utf8 -m RIS_stage3_ai.train --dataset RIS_stage3_ai/data_smoke_g3a --output RIS_stage3_ai/checkpoints_smoke_training_g3b_v2 --smoke --limit 2
.venv-stage3-ai/Scripts/python.exe -X utf8 -m RIS_stage3_ai.train --dataset RIS_stage3_ai/data_smoke_g3a --output RIS_stage3_ai/checkpoints_smoke_training_g3b_v2 --smoke
.venv-stage3-ai/Scripts/python.exe -X utf8 -m RIS_stage3_ai.train --output RIS_stage3_ai/checkpoints_smoke_training_g3b_v2 --status
```

`--limit` 统计本次新增的训练或验证样本操作，包括初始模型的验证。上例先做 1 次初始验证和 1 次训练更新，然后停止；总预期值保持 4 次更新、3 次验证。第二条训练命令补齐剩余工作。再次运行会验证并加载完整结果，不重新训练。

## 服务器全量命令（尚未执行）

```bash
python -m RIS_stage3_ai.train --dataset RIS_stage3_ai/data_full_v1 --output RIS_stage3_ai/checkpoints_full_v1 --device cuda:0 --limit 2
python -m RIS_stage3_ai.train --dataset RIS_stage3_ai/data_full_v1 --output RIS_stage3_ai/checkpoints_full_v1 --device cuda:0
python -m RIS_stage3_ai.train --output RIS_stage3_ai/checkpoints_full_v1 --status
```

正式训练要求全量数据集 480 个样本都已校验完成，且运行在 Linux 服务器 jzm。第一条进行完整尺寸的初始验证和训练步试运行，用真实耗时/显存决定后续安排。调用方应保存标准输出日志；自动后台运行、进程管理与完整实验串联仍待后续实现。

本地 7 项检查覆盖真实参数更新、训练/验证隔离、精确断点恢复、提交失败后的重算及孤立事件排除、文件损坏/身份冲突、冒烟/不完整模型限制、验证选模和失败处理。证据为 `evidence/g3_training_checks.json`。本阶段不提供正式模型性能结论。
