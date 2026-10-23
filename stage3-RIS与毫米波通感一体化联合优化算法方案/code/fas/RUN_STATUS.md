# MATLAB RIS + FAS 仿真运行记录

2026-10-23，北京时间。正式实验已在服务器启动，尚未完成。

## 基准、备份与代码

- 基准：用户指定 `stage3-RIS与毫米波通感一体化联合优化算法方案/code` 的MATLAB实现。
- 修改前备份：`codex/pre-matlab-fas-20261023`，远端已核验
  `8dcf95f25fd70e948e347b12f6d25b660e164f90`。
- 实现分支：`codex/matlab-fas-20261023`。
- 正在运行的源码release：`aafa68081d27ee7b0fb379f4823c9fb48ea06194`。
- 本地及服务器MATLAB源码集合SHA256一致：
  `6851ee8fe45e298798647e35f4d61fadb2349be526d2a95eb8e86d0857e7f845`。
- 备份选择了原MATLAB源码、绘图脚本、README及原方案PDF；未上传凭据、环境、
  缓存和未选择的旧仿真数据。新增提交只选择实现、说明及小型测试/部署证据。

## 已完成验证

1. 本地 MATLAB R2024a：10类数学/接口检查通过，见 `test_evidence.json`。
2. 本地冒烟：2个SNR点×2MC，四组主方法及0/4/16符号开销均跑通。
   未锁定样本保留；可锁定样本确实发生了端口移动，且满足通信约束。
3. 独立读取MAT断点核算位置RMSE，和MATLAB CSV最大绝对差约4.45e-15；
   四个断点二次运行全部复用，见 `smoke_evidence.json`。
4. 服务器 MATLAB R2022b：同一套数学/接口检查通过，见 `evidence/server_test.json`。
5. 服务器完整尺寸验证：一个10dB样本，使用正式阵列、RIS、子载波、CPI与迭代次数，
   四组估计、断点和图表汇总均完成。见 `evidence/pilot_manifest.json` 和
   `evidence/pilot_progress.json`。这个单样本只验证部署，不是正式统计结论。

## 正式实验

- 目录：`/home/jzm123/AAA_ZTEproject/RIS_stage3_matlab_fas/releases/aafa68081d27ee7b0fb379f4823c9fb48ea06194/code/fas/results_full_mc300_20261023`。
- 实验身份：`65a63a2aa5f639006337eaaaa9d5b26c7a4dee035595d0208b12fdaacac23341`。
- 12672子载波，16Tx/64Rx，256RIS，2用户；粗256＋精256符号。
- 沿用原粗测角384×64及精估计256×64抽样；没有将精估计改成全网格处理。
- SNR=-50:5:10，每点300MC，共3900个配对样本，2个worker、每进程2个计算线程。
- 启动核验快照已完成9/3900，两个worker仍在运行；详见
  `evidence/formal_launch.json` 的实际时间和阶段。该数字仅为启动时快照。
- 完整参数及逐文件源码哈希见 `evidence/formal_manifest.json`。
- 每个样本独立保存参数、种子、四组设计/端口、8组估计及失败标志。
  工作者状态JSON逐阶段更新；失败会保留已有断点并给出错误，不制造完成进度。

在仓库根目录查询：

```powershell
tools/ris-fas-matlab-server.ps1 status -Release aafa68081d27ee7b0fb379f4823c9fb48ea06194 -RunName full_mc300_20261023
```

完成后取回图表（运行中取回会明确标注INCOMPLETE）：

```powershell
tools/ris-fas-matlab-server.ps1 fetch -Release aafa68081d27ee7b0fb379f4823c9fb48ea06194 -RunName full_mc300_20261023
```

正式样本尚未跑完，暂不报告FAS增益百分比。对端口范围、最小间距、理想校准、
互耦忽略和切换预算的限定见README；这些仿真不等同于流体器件实测。
