你是我的 MATLAB 算法与工程化助手。请基于我当前项目的 MIMO-OFDM ISAC 三维联合估计主流程进行“可运行、可验证、可扩展”的开发，不要只给思路。

【项目背景（固定上下文）】
- 主脚本：main.m
- 任务：三维联合估计（theta 俯仰角, phi 方位角, R 距离, v 速度）
- 数据流：generate_OFDM_signal -> simulate_radar_channel_3d -> local_ESPRIT_estimator_3d / ZTE_3D_estimator -> evaluate_estimation
- 当前关键参数：
  - fc = 28e9, c = 3e8, d = lambda/2
  - Rx阵列: Mx=8, My=8
  - OFDM慢时间符号数: K=256
  - 目标数: num_targets=2
  - 3GPP FR2: n_rb=264, n_sc_per_rb=12, delta_f=120kHz, T_cp=0.6us
  - 目标分辨率验收：0.1m，支持载波聚合扩展带宽
- 当前估计器模式：local_esprit（可切换 ZTE_3D）

【本次任务（已补全）】
请在不改变 main.m 外部调用方式的前提下，重构并增强 local_ESPRIT_estimator_3d，实现以下目标：
1. 在 SNR=0~10 dB 区间提升速度估计稳健性，降低 v 维 RMSE 波动；
2. 提升近距离双目标（如 R_true=[600.8, 600.2]）场景下的可分辨性，减少目标匹配错误；
3. 引入“粗到细”流程：先3D FFT/CFAR粗检，再局部ESPRIT精估计（角-距-速联合细化）；
4. 增加候选点质量评分与筛选机制（基于峰值强度、局部SNR、谱峰锐度）；
5. 保证输出接口兼容：[theta_est, phi_est, R_est, v_est, info]；
6. 保持 evaluate_estimation 可直接复用，并确保保存到 ZTE_3D_results.mat 的结构不变。

【硬性要求】
1. 必须给出具体代码改动，不只讲理论。
2. 保持与现有 main.m 接口兼容（输入输出变量名尽量不变）。
3. 每一步改动说明“改了什么、为什么、预期收益、潜在副作用”。
4. 给出最小可运行验证方案（含测试参数、运行命令、预期输出特征）。
5. 若涉及性能，提供复杂度/耗时优化点（如FFT点数、补零倍率、候选点筛选、NMS/CFAR开销）。
6. 若涉及 MATLAB Coder：
   - 标注 %#codegen
   - 明确输入类型与尺寸（coder.typeof / -args）
   - 替换不兼容函数
   - 给出 codegen 命令与测试脚本
7. 不破坏现有结果保存逻辑（ZTE_3D_results.mat 结构保持可读）。

【输出格式（严格按此）】
A. 方案概述（3-6条）
B. 具体修改文件清单（逐文件）
C. 关键代码片段（可直接粘贴）
D. 验证脚本与运行步骤
E. 风险与回退方案
F. 若可做C代码生成，附完整 codegen 配置与命令

【附加实现细节约束】
- 候选点数量上限：先粗检保留前15个，再二次筛选到前8个；
- 局部精估窗口建议：range方向 ±192 bins，doppler方向 ±24 bins（总采样约384×48）；
- 对速度估计增加相位差线性拟合+稳健回归（可与FFT峰值法融合）；
- 目标配对时优先最小化联合代价：角度误差归一化 + 距离误差归一化 + 速度误差归一化；
- 在 info 结构中新增中间结果字段（如 coarse_candidates、quality_score、refine_status、timing_breakdown），用于调试与可视化；
- 所有新增参数统一挂到 params.local_esprit 子结构，避免散落硬编码。

【验证场景（请按此至少跑3组）】
1. 基线场景：SNR=10 dB，当前默认真值参数；
2. 低信噪比场景：SNR=0 dB；
3. 近邻目标强化场景：保持角度接近、速度一正一负，距离间隔<=0.8m；
并输出每组的 rmse_theta、rmse_phi、rmse_R、rmse_v 与运行耗时。

【质量标准】
- 能直接在当前工程落地
- 结果可复现
- 与现有参数体系兼容
- 注释清晰，便于后续继续迭代