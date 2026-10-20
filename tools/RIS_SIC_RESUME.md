# RIS/SIC 断点续跑说明

本次修复针对正在进行的 MC=60、SNR=[-25,-20,-15,-10,0,10,20] dB、6 个 RIS/SIC 方案，保持 12672 子载波、256 个 OFDM 符号、16 发射/64 接收阵元、beta_SI=0.1 和 pilot-LS SIC。正式运行默认 double 精度。

## 已确认的问题

- 旧作业已退出，无完整 MC 输出；旧保存粒度是整个 MC，未完成的 SNR/方案无法恢复。
- 原生日志有 malloc/free 堆错误，但本次复现显示主进程能在部分报错后继续完成计算，不能仅凭该信息断定内存耗尽或主进程死亡。单 worker 时服务器仍有约 38–39 GiB 可用内存。
- 已取得原生调用栈：许可管理模块 `libmwlmgrimpl.so` 的线程调用 `free` 时，glibc 检测到堆损坏并触发 `abort`；MATLAB 的信号处理函数再次进入 `malloc`，阻塞在分配器锁上。主线程等待运行时任务，因此 PID 仍存在却没有计算进度。该栈确定了停住的机制和堆错误被检测的位置，尚不能确定最初写坏内存的原因。证据位于服务器 `.jobs/diagnostics/smoke-abort-detail.txt`。
- 初版原子保存 helper 有 MATLAB 函数作用域错误，已通过显式 struct 保存修复。
- 聚合器文件名拼接语法错误已修复；旧聚合器无限等候的逻辑已替换。
- MATLAB shell 启动器与实际计算进程需作为完整进程组停止，否则会残留旧计算进程。

## 新机制

每完成一个 MC × SNR × 方案，就以临时 MAT 文件和同目录 rename 提交结果。每个 MC 文件只保存 6×SNR数量的结果切片及 completion mask。加载时核对配置、维度和有效完成数据；检测不到目标的 NaN RMSE 是合法结果，不等同于未完成。

checkpoint 目录与 worker 编号无关。停止全部 worker 后，可以改变 Workers 数量再恢复。精度、SNR 列表或模型参数变化会拒绝不兼容 checkpoint；更改实验时使用新的 RunTag。旧数据保留，新前缀为 `ris_sic_rmse_snr_mc60_resume_v3_double`。

后台 supervisor 使用独占锁避免重复写入；默认 4 个独立 MATLAB worker，每个进程使用 `-singleCompThread` 并限制原生线程。每个进程默认新完成 1 个方案后正常退出，随后用新进程继续；这减少运行时累积故障的影响，但不声称修复了 MATLAB 内部缺陷。

监护每 10 秒检查当前进程的日志：发现 malloc/free 等堆错误就终止整个 MATLAB 进程组，不再等待旧的 900 秒无进度超时。输出 BATCH_YIELD / FINAL_RESULT 后超过 60 秒仍未退出，也会回收进程。无报错但没有日志进度的兜底超时仍为 900 秒。TERM 后 10 秒进程组未退出则 KILL（即使启动器已经退出也继续检查子进程组），然后从最后已提交的方案恢复。

非零退出也会自动恢复。连续无新增已保存结果的失败最多重试 3 次，有已保存进展则重置重试预算；超过预算会明确标为 FAILED，而不会假报完成。所有 worker 输出最终结果并成功退出后才聚合，聚合进程另有 600 秒外部超时，并验证每个 MC 的全部 completion mask。COMPLETE 只在聚合成功后写入。

波形生成已将每次 12,672 个 qammod 工具箱调用替换为一次基础 MATLAB Gray 方形 QAM 映射。当前正式实验的 16-QAM 与 R2022b 官方 qammod 逐元素完全一致，不消耗 RNG；其他已测试阶数最大差异为 3.15e-16。Hann 窗仍使用原来的官方函数，避免将微小舍入差异引入已有断点。减少工具箱调用是代码优化和潜在触发因素的规避，尚不能证明它修复了底层堆损坏。

## Windows 本地使用

```powershell
# 上传、后台启动；相同参数重复执行可在停止后恢复
pwsh -NoProfile -File .\tools\ris-sic-server.ps1 run -McTotal 60 -Workers 4

# 可调每进程方案数和无进度超时（默认 1、900 秒）
pwsh -NoProfile -File .\tools\ris-sic-server.ps1 run -McTotal 60 -Workers 4 -CasesPerProcess 1 -StallTimeoutSeconds 900

# 查询状态与已保存进度
pwsh -NoProfile -File .\tools\ris-sic-server.ps1 status
pwsh -NoProfile -File .\tools\ris-sic-server.ps1 tail -Lines 40

# 停止整个作业进程组，保留 checkpoint
pwsh -NoProfile -File .\tools\ris-sic-server.ps1 stop

# 之后可换为 4 个 MATLAB worker 接着跑
pwsh -NoProfile -File .\tools\ris-sic-server.ps1 run -McTotal 60 -Workers 4
```

SSH 断开或关闭本地聊天不影响 nohup 后台作业。停止作业后，应先检查 STOPPED 且无遗留计算进程再恢复。服务器重启或断电后，需要重新执行 run；后台脚本不属于系统自启动服务。

MAT/CSV 与角度、距离、速度图沿用本实验既有统计方法；图中曲线是每次 MC 内目标 RMSE 的跨 MC 中位数，CSV 同时包含均值。新增恢复逻辑不改变该统计定义。

## 验证记录

- 本机 R2024a、服务器 R2022b：`test_ris_sic_resume` 均打印 CHECKPOINT_TESTS_PASSED，涵盖部分完成恢复、损坏文件拒绝、配置混用拒绝及保存不改变 RNG。
- 全尺寸、MC=1、SNR=-25 和 +20 dB 冒烟：实际停止后恢复，日志确认跳过已保存的前 3 个方案；修正后的停止脚本没有留下 MATLAB 进程，独占锁释放。
- 冒烟剩余计算的 12/12 个方案均已提交；从这些断点重新启动后，worker 跳过全部仿真，最终 shard、结果 MAT、CSV 和角度/距离/速度图全部输出，supervisor 状态为 COMPLETE。
- `tools/test-ris-sic-supervisor.sh` 在服务器打印 SUPERVISOR_RECOVERY_TEST_PASSED：故意让进程忽略 TERM 并卡住，监护 KILL 后自动恢复；短批次连续启动；所有计算进程退出且锁释放。
- 2026-10-08 20:14 左右，正式 `ris_sic_rmse_snr_mc60_resume_v3_double` 作业重新提交至服务器，2 个并行 worker，默认每进程 6 个新方案；最终完成时间以实际日志为准。
- 已确认的原生故障机制与未确定的内存损坏起因分开记录；不把仍未知的起因归结为 RIS 模型、并行数或内存耗尽。
- 2026-10-09：基础 MATLAB 空闲测试及 32 轮大数组分配/FFT 测试完成，无故障；这不能排除间歇性运行库故障。
- 2026-10-09：隔离目录中重新计算全尺寸 MC=1、SNR=-25 dB、无 RIS/SIC 的一组，角度/距离/速度 RMSE、检测数及 SIC 指标与旧 checkpoint 完全一致，打印 FULL_CASE_EQUIVALENCE_PASSED。
- 2026-10-09：新增堆错误快速回收、保存后退出超时及进程组检查后，恢复测试再次打印 SUPERVISOR_RECOVERY_TEST_PASSED。
- 2026-10-09 09:17：从 377/2520 个已保存方案恢复为四并行。四个 worker 的第一轮均完成并保存；实测每进程峰值约 10 GiB。资源观测记录位于服务器 `.jobs/diagnostics/four-workers-resources.jsonl`，正式任务持续运行。
- 至 09:23：四个 worker 各完成两轮并正常退出、续跑，进度 385/2520；此观测段没有原生堆错误或 watchdog 触发。09:17:21–09:21:14 的 47 次资源采样中，可用内存最低 11.85 GiB，四进程同时驻留内存峰值 32.44 GiB，单进程历史峰值最高 9.93 GiB。有限观测不等于长期无故障保证。
- 至 09:24：四个 worker 各完成三轮，12 个进程均正常保存并以退出码 0 结束，正式进度 389/2520，状态 RUNNING。新增结果覆盖六种 RIS/SIC 方案，已开始第四轮。

## 能承诺的稳定性边界

2026-10-10 09:37 验收：正式任务状态 COMPLETE，60/60 MC、2520/2520 方案均完成，最终 MAT、CSV、三项 RMSE 图及合并图已生成（2026-10-09 23:28 左右）。09:17 切换四并行后新增的 2143 个方案均已保存，2143 次 MATLAB 进程退出码均为 0；四个 shard 日志在此时段的原生堆错误和 watchdog 触发数均为 0。本地结果已取回至 `server-results/ris_sic_mc60_final/`。这证明本轮完整任务稳定完成，仍不能单凭一次成功运行确定原始堆损坏根因。

修复后可以从已提交方案恢复，并且已验证四并行实际计算。不能承诺旧版 MATLAB 的原生库永远不再发生堆错误。已观测到的原生堆错误检测位置为许可管理插件，最初破坏内存的位置仍未知；如果新配置再次复现，根治需要进一步验证当前 R2022b 基础发行版与服务器环境的兼容性、使用官方更新/修复安装，而不是仅继续增加内存或改动 RIS 数学模型。
