# AI 正式服务器实验

2026-10-20 13:41（Asia/Shanghai）已启动正式流水线。此文件记录启动事实，不是自动刷新的运行面板；后续真实进度要执行 `status.py` 核对。

- 服务器：jzm，SSH 使用现有 jzm123 连接配置。
- 发布源码：`/home/jzm123/AAA_ZTEproject/RIS_stage3_ai/releases/full_20261020_g3d_72403b7`
- 代码提交：`72403b7dc087ef6514c38d68fbdae519108b45de`，已推送 GitHub。
- 独立解释器：`/home/jzm123/AAA_ZTEproject/RIS_stage3_ai/.venv311/bin/python`
- 正式输出：`/home/jzm123/AAA_ZTEproject/RIS_stage3_ai/runs/full_20261020_g3d`
- 启动 runner PID：2413170；初始数据子进程 PID：2413300。进程启动身份保存在状态文件；不要仅凭 PID 判断后续存活。
- 后台 `nohup` 执行，关闭本地聊天或断开 SSH 不会终止它。服务器重启后需要同版本续跑。
- 只启动一个计算 worker，4 个 CPU 线程；后续训练和推理使用 cuda:0。

顺序为 480 份数据 → 20 轮训练与验证 → 2156 案例 × 6 方法 → RMSE 汇总 → 同案例 × 3 方法 × 3 时间预算 → 预算 RMSE 汇总。参数、种子、逐样本断点、失败记录及日志均保存于各阶段目录。

正式数据维持 12672 子载波、Tx 4×4 / Rx 8×8 / RIS 8×8、2 bit、128+128 符号、双精度。SNR −30 到 20 dB，间隔 5 dB；测试样本数未缩减。之前本地/服务器的小规模输出均在独立 smoke 目录，不混入正式结果。

查看状态：

```bash
cd /home/jzm123/AAA_ZTEproject/RIS_stage3_ai/releases/full_20261020_g3d_72403b7
/home/jzm123/AAA_ZTEproject/RIS_stage3_ai/.venv311/bin/python -m RIS_stage3_ai.status \
  --output /home/jzm123/AAA_ZTEproject/RIS_stage3_ai/runs/full_20261020_g3d
```

失败后先查看 `pipeline_state.json` 中的日志及 `failures`，排除原因后在同一 release 用以下命令续跑。已经完成的样本只验证、不重算，不要删除锁文件，也不要换源码复用原输出目录。

```bash
bash RIS_stage3_ai/run_server.sh \
  /home/jzm123/AAA_ZTEproject/RIS_stage3_ai/.venv311/bin/python \
  /home/jzm123/AAA_ZTEproject/RIS_stage3_ai/runs/full_20261020_g3d cuda:0
```

全尺寸成本试验外推约 7.9 小时准备数据、2.7 小时训练加验证，另加 IO/资源竞争。全部六方法和时间预算 RMSE 评估需额外时间，目前没有可靠的整套完成 ETA。训练完成前不能把冒烟网络当正式模型；所有正式比较结束、数量与失败情况审计后，才能得出提升结论。

验证证据：`evidence/g3_*final.json`、`evidence/server_pipeline_smoke_audit_20261020.json`、`evidence/server_budget_checks_20261020.json` 和 `evidence/server_formal_launch_20261020.json`。部署包哈希和真实启动快照记录于后者。
