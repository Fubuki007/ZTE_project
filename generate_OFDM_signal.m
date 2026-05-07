function tx_signal = generate_OFDM_signal(params)
    % 生成OFDM发射信号
    % 输入: params - 系统参数
    % 输出: tx_signal - 发射信号 (N×K)
    
    N = params.N; % 子载波数
    K = params.K; % OFDM符号数
    
    % 生成QPSK调制符号
    if params.mod_order == 4 % QPSK
        bits = randi([0, 1], N, K, 2);
        tx_signal = (1 - 2*bits(:, :, 1)) + 1j*(1 - 2*bits(:, :, 2));
        tx_signal = tx_signal / sqrt(2);
    else % BPSK
        tx_signal = 1 - 2*randi([0, 1], N, K);
    end
    
    % 添加导频
    pilot_spacing = params.pilot_spacing;
    pilot_positions = 1:pilot_spacing:N;
    tx_signal(pilot_positions, :) = 1 + 1j;
    
    % 功率归一化
    tx_signal = tx_signal / sqrt(mean(abs(tx_signal(:)).^2));
end