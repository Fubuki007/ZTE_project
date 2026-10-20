# 同时间预算实验与服务器执行

## 固定协议

`budget_design.py` / `run_budget.py` / `aggregate_budget.py` 组成额外的预算实验，复用正式六方法实验的全部 2156 个配对测试案例。传统、未训练、训练后共三种方法，各从头运行 0.5、2、8 秒预算，共 19404 个终端记录。没有减少子载波、阵列、CPI、测试场景或 MC 数。方法及预算顺序按案例种子随机排列。

计时从上下文构造开始，包括共同的几何可行初值、AI 输入/输出传输、网络梯度更新、量化、通信/功率投影、原优化更新和候选的最终复制/审计。模型加载不计入单案例在线时间。CUDA 同步；不另做预热。无目标真值输入或按测试误差选解。

全部方法先产生几何可行配置。AI 方法再尝试网络+投影配置；之后各自执行相同的 1/1/1 AO 小块，按最弱目标照射指标保留已完成且合法的最好配置。此预算策略不同于六方法主实验的固定迭代策略，不能把两组算法名字或结果混为一谈。

**预算的精确定义是“截止时刻前已就绪的最佳合法配置”，不是硬实时可中断求解器。** 单次 SCA、整段网络或相位遍历可能跨过截止时间，其结果不能入选，停止耗时及原子步骤超时单独保存。若截止前无合法配置，记 `DEADLINE_MISS`。该实验可回答相同可用计算时间下解质量如何；不能用来声称进程能在该时间内硬中断。

预算外的回波合成和精估计沿用全部物理尺寸，并使用主实验完全相同的粗回波、精回波随机种子、噪声方差和 CPI。真值仅用于回波合成和最终误差评分。角度按 theta/phi 两维平方误差平均后开根号；三项指标共享 3D 方向匹配。

每案例每方法每预算保存原子检查点、源码/模型身份、配对信息、截止候选时刻和真实停止耗时。已保存结果只校验不重算。中断中的单个结果重算；服务器墙钟时间不同可能导致该未提交结果选中的迭代次数不同，这正是测时实验的限制。

汇总保留截止失败、算法失败、缺失数量。只要某方法/SNR/预算存在任一失败或缺失，就不报告该组完整主 RMSE，只单列条件成功 RMSE。新场景按场景、旧场景按 MC 进行配对 bootstrap，2000 次；差值基准为同预算传统方法。不能通过只画成功曲线忽略截止失败。

## 启动、资源与恢复

完整顺序：`data → training → comparison → metrics → budget → budget_metrics`。`server_pipeline.py` 只启动一个计算子进程、4 个 BLAS 线程；指定一张 GPU。正式启动要求 jzm/Linux、至少 12 GiB 可用 RAM、50 GiB 磁盘、指定 GPU 至少 6000 MiB 空闲且利用率不超过 20%。资源检查是启动快照，不能保证其他用户之后不占用资源。全尺寸 GPU 成本试验已经完成；当前不增加并行 worker。

Linux 后台启动（在不可变 release 根目录）：

```bash
bash RIS_stage3_ai/run_server.sh \
  /home/jzm123/AAA_ZTEproject/RIS_stage3_ai/.venv311/bin/python \
  /home/jzm123/AAA_ZTEproject/RIS_stage3_ai/runs/full_20261020_g3d cuda:0
```

`nohup` 支持断开 SSH 后继续执行；它不是开机自启服务。服务器重启或进程退出后，在原 release 用同命令续跑。全局资源锁及逐目录写锁阻止同组目录中的重复 runner；锁文件不可手动删除。已有日志不覆盖，每次子进程启动建立新日志。失败后停止后续阶段，保留失败记录，不无限自动重试。

```bash
/home/jzm123/AAA_ZTEproject/RIS_stage3_ai/.venv311/bin/python -m RIS_stage3_ai.status \
  --output /home/jzm123/AAA_ZTEproject/RIS_stage3_ai/runs/full_20261020_g3d
```

`status.py` 返回进程存活检查、心跳更新时间、当前阶段、子进程和实际保存进度。Linux 通过 boot ID、进程启动 tick 和 PID 区分 PID 复用。每 5 秒更新心跳；单个大案例内部没有伪造百分比。阶段完成要读取并审计检查点数量，不只看退出码。`COMPLETE` 表示所有预期终端记录已处理，不代表所有物理案例成功，更不代表 AI 一定有提升。

本地完整链路只能用 `--smoke --device cpu`：

```powershell
.venv-stage3-ai/Scripts/python.exe -X utf8 -m RIS_stage3_ai.server_pipeline --output RIS_stage3_ai/results_smoke_pipeline_g3d --smoke --device cpu
```

之前全尺寸成本试验外推数据约 7.9 小时、训练加验证约 2.7 小时；未含检查点 IO 和竞争。六方法比较和额外 19404 个预算结果均需大量精估计，不能把约 11–12 小时说成全部实验完成时间。实际进度和后续完整案例耗时才可用于估算比较阶段。
