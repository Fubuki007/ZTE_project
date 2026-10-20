# 交付清单

本包仅包含当前自干扰主流程的最小运行集合。

## 运行文件

- `main.m`
- `build_default_params.m`
- `generate_HSI.m`
- `generate_mimo_ofdm_waveform.m`
- `design_precoder.m`
- `simulate_radar_channel_3d.m`
- `joint_estimator_fast.m`
- `evaluate_estimation.m`

## 文档文件

- `README.md`
- `MANIFEST.md`
- `CHANGELOG.md`
- `VERSION.txt`
- `SHA256SUMS.txt`

## 明确排除

- `task_*`、`test_*`、`check_*`、`diag_*` 等实验或诊断脚本；
- 扫参、绘图和论文出图脚本；
- `.mat`、`.fig`、`.png`、`.eps`、`.csv` 等结果；
- `.log`、`.out`、`.err`、`.pid` 等运行痕迹；
- 历史压缩包、论文资料、第三方参考工程；
- 独立原型 `SIC.m`（正式实现已集成到回波仿真函数）。

