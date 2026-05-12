function tx_signal = generate_OFDM_signal(params)
% =========================================================================
% GENERATE_OFDM_SIGNAL  OFDM 基带通信符号生成 (论文 s_i[l])
% -------------------------------------------------------------------------
% 严格对齐作者源代码 (主文件 main_snr_rmse_quicklook.m) 中 S 的生成方式:
%     DATA = randi([0 M-1], K_stream, L, Ns);
%     S(:,:,i) = qammod(DATA(:,:,i), M, 'UnitAveragePower', true);
% 对应论文 "A Novel Joint Angle-Range-Velocity Estimation Method for
% MIMO-OFDM ISAC Systems" (IEEE TSP 2024) 式 (2): x_i[l] = W_i · s_i[l]。
%
% 本函数输出的是 s_i[l] 部分, 发射端预编码 W_i 在本工程中退化为 1
% (单流等效标量), 因此 x_i[l] = s_i[l]。如需完整 MIMO 预编码, 可在外
% 层自行计算 pagemtimes(W, reshape(tx_signal,[1,L,Ns])).
%
% 与作者源代码一致的关键点:
%   1) M-QAM 调制, 默认 M = 16 (论文 Table II 中 mod_order = 16)
%   2) 使用 qammod 的 'UnitAveragePower' 选项, 每个符号平均功率为 1,
%      避免事后再做一次整体归一化 (这一步老版本会破坏 |s|^2 = 1 的假设)
%   3) 不插入任何固定导频
%      —— 原因: 论文 Step 2 的缩放因子 α_{na_x, na_y} (式 23) 依赖
%         "通信符号随机" 的假设, 固定幅值的导频会在该子载波位置引入
%         能量偏差, 使 |a^H(u,v)·x|^2 的分子/分母比例失真
%
% 输入 (params):
%   N           子载波数 Ns
%   K           OFDM 符号数 L (一个 CPI 内)
%   mod_order   调制阶数 M (默认 16; 兼容 4/16/64/256, 必须是 4 的整数次幂)
%
% 输出:
%   tx_signal   (Ns, L) 复数矩阵, tx_signal(i, l) = s_i[l]
%
% 兼容性说明:
%   - 旧字段 params.pilot_spacing 已不再使用, 保留为静默忽略, 不报错;
%     若必须复现旧行为, 可显式设置 params.legacy_pilot = true 并同时
%     提供 params.pilot_spacing, 此时会按 (1+1j)/sqrt(2) 插入单位功率
%     导频, 但这会偏离论文假设, 不建议启用。
%   - 输出维度仍为 (Ns, L), 与 simulate_radar_channel_3d.m 和
%     joint_angle_range_velocity_estimator.m 的接口保持一致。
% =========================================================================

% -------------------------- 参数解析 --------------------------------------
N = params.N;   % 子载波数 Ns
L = params.K;   % OFDM 符号数 (注意: 工程约定 params.K 存放的是 L)

if isfield(params, 'mod_order') && ~isempty(params.mod_order)
    M = params.mod_order;
else
    M = 16;     % 默认 16-QAM, 对齐论文 Table II
end

log2M = log2(M);
if M < 2 || abs(log2M - round(log2M)) > eps
    error('mod_order 必须是 2 的正整数次幂, 例如 4, 16, 64, 256');
end

% -------------------------- 核心: M-QAM 随机符号 --------------------------
% DATA 形状 (Ns, L), 与作者按子载波切片调用 qammod 等价 (qammod 逐元素操作)
DATA = randi([0, M - 1], N, L);

if exist('qammod', 'file') == 2
    % 通信工具箱路径: 单位平均功率, 与作者一致
    tx_signal = qammod(DATA, M, 'UnitAveragePower', true);
else
    % 无通信工具箱的手写回退: 构造 sqrt(M) x sqrt(M) 方形星座, 再归一化
    %   星座点: (2k - sqrt(M) + 1) / sqrt( (2/3) * (M-1) ),  k = 0..sqrt(M)-1
    mside = sqrt(M);
    if abs(mside - round(mside)) > eps
        error('回退路径仅支持方形 QAM (M = 4, 16, 64, 256)');
    end
    mside = round(mside);
    norm_factor = sqrt((2/3) * (M - 1));   % 单位平均功率归一化系数
    levels = (2*(0:mside-1) - (mside - 1)) / norm_factor;
    i_idx = mod(DATA, mside) + 1;
    q_idx = floor(DATA / mside) + 1;
    tx_signal = levels(i_idx) + 1j * levels(q_idx);
end

% -------------------------- 可选: 旧版导频回退 ----------------------------
if isfield(params, 'legacy_pilot') && params.legacy_pilot && ...
   isfield(params, 'pilot_spacing') && ~isempty(params.pilot_spacing) && ...
   params.pilot_spacing > 0
    warning('generate_OFDM_signal:legacyPilot', ...
        ['已启用 legacy_pilot 路径, 将插入固定导频。', ...
         '这会破坏论文式 (23) 的能量守恒假设, 仅用于复现旧版结果。']);
    pilot_positions = 1:params.pilot_spacing:N;
    tx_signal(pilot_positions, :) = (1 + 1j) / sqrt(2);
end
end
