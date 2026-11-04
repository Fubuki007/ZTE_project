# 论文启发FAS验证：运行状态

2026-11-04，北京时间。正式900/900组及全量汇总核验完成；按用户后续要求取回精选结果并分析，见`FINAL_RESULTS.md`。不主动轮询，不启动新仿真。

## 正式任务

- 不可变源码release：`f7addf80f5752d129a968cf251b177c3ccda84bd`，已推送GitHub并核对远端；41个执行源文件本地/服务器哈希逐项一致，见`evidence/release_source_hashes.json`。
- manifest：`188647ad2a7151d1aae13207b7a68e2d7c9ff31e7fca17bfe643157919c07a37`。
- 目录：`/home/jzm123/AAA_ZTEproject/RIS_stage3_matlab_fas/releases/f7addf80f5752d129a968cf251b177c3ccda84bd/code/fas/paper_scene/results_full`。
- 2026-11-04约13:23北京时间启动；监督PID252827，4个worker PID252831–252834。13:23:28核实36个逐样本断点及真实进程；结束上传轮次前，13:24:28已读取241/900、4个worker均RUNNING。此为历史启动记录，最终状态见下一条。
- 完成复核：900/900，三档各300；四个worker均COMPLETE、每个225组，最后样本北京时间13:27:43完成，最终state=COMPLETE、verification.complete=true、约束及指标重算通过。
- 完成后的只读分量审计覆盖900个MAT、7200条方法记录，PEB径向/角度重构最大相对误差4.33e-16；没有新抽样或优化。精选CSV、核验、配对统计和图已取回`server-results/matlab-fas/paper-scene/f7addf80f5752d129a968cf251b177c3ccda84bd/`。
- 完整尺寸数学检查：位置梯度误差5.13e-9、通信梯度1.09e-10、共位置空间场误差0；强RR且非零DD下PEB有限，纯LoS仅RR时不可定位，均通过。
- 三种完整尺寸pilot各约2.96/1.57/0.98秒，通信与控制检查通过；只用于验证和计时，不代替正式300MC统计。日志和原始MAT留服务器。
- 正式任务自动完成900组后汇总并重算约束/指标，验证成功才写COMPLETE；无人值守运行，不依赖对话持续开启。
- 用户需要时可运行：`tools/ris-paper-scene-server.ps1 status -Release f7addf80f5752d129a968cf251b177c3ccda84bd`；完成后用同一脚本的`fetch`取回精选数据，再运行`tools/summarize_paper_scene.py`生成摘要和图。未取得完整核验结果前不报告性能结论。

## 实现与验证

- 修改前备份：`codex/pre-paper-fas-20261104`，远端SHA `a2df9010d87017bfc2575afaaae544e2707b7236` 已核对。
- 本地仅缩小规模smoke：3/3、相同manifest断点续跑3/3均通过。逐样本功率、SINR、离散相位、端口网格、最小间距、接受步单调性和指标重算通过。
- 位置梯度相对误差5.45e-10，通信梯度1.05e-10，共位置空间场误差0；时频Gram与显式回波误差3.88e-14；独立物理回波差分Fisher信息误差1.15e-9。guard删除样本后同一设计PEB未变好。
- 初次服务器pilot暴露强RR/弱DD时FIM条件数过大，原1e-10特征值阈值误报Inf。已改为时频QR压缩与实数雅可比SVD求解，本地重跑通过；新增强RR下保留非零DD应可定位、纯LoS仅RR应不可定位的两项检查。旧pilot不作为正式性能结果，正式运行使用修复后的独立release。
- 加入额外固定布局优化对照，排除仅因FAS多做几轮RIS/波束更新而产生的假增益。smoke只用于代码检查，不报告其性能数字作研究结论。
- 900组=300几何×Rayleigh/Rician10dB/LoS。论文启发的增益归一化、完全已知信道/目标诊断；一目标、一用户、DD/RR两路径，项目完整阵列、子载波、CPI和Tx孔径。
- 指标为窄带雷达SNR、扣4符号的净能量及宽带扩展PEB；没有实际定位RMSE，也未验证真实链路预算或逐端口训练。具体假设见README。
- 不覆盖此前受控衰减实验。正式实验需源码单独release，记录manifest/种子、逐样本断点、日志和真实进度；900/900及verification通过之前不宣称完成。

备份只包含源码、必要脚本、文档及精选验证证据；凭据、运行环境、缓存、历史未选文件和大批原始数据不上传。
