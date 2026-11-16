function [estimate, info] = joint_estimator_fast(rx_cube, params)
% 粗估计
% 输入为原始接收样本。
% ---- 1. 参数 ----
t_baseline=tic;
Mx=params.Mx; My=params.My; Ns=params.N; L=params.K;
Q = params.Q;
delta_f = params.B / Ns;
Rmax = params.c / (2 * delta_f);
% 沿用二期峰值抑制与候选数设置。
nms_r=max(2,ceil(0.35/(params.c/(2*params.B)))); nms_v=2;
num_candidates=max(2*Q,8);
% ---- 2. 去相位后作RD检测 ----
U=size(rx_cube.symbol,1); P=zeros(Ns,L);
for k=1:U
    S=reshape(rx_cube.symbol(k,:),Ns,L);
    phase=conj(S./abs(S)); % 消除当前用户已知符号的相位，保留回波传播相位。
    y=rx_cube.rd.*phase;
    RD=fft(y,Ns,1);
    RD=fftshift(fft(RD,L,2),2);
    P=P+abs(RD).^2; % 合并各用户的距离-多普勒功率谱。

end

P=P/U;
[~,idx]=maxk(P(:),min(num_candidates*4,numel(P)));
nr_vec = (0 : Ns - 1).';
nv_vec = (-floor(L/2) : (ceil(L/2) - 1)).';
esprit_n_vec = rx_cube.n(:)-1;
esprit_l_vec = rx_cube.l(:)-1;
theta_est = zeros(1, Q);
phi_est   = zeros(1, Q);
R_est     = zeros(1, Q);
v_est     = zeros(1, Q);
detected  = 0;
selected_ir = zeros(1, Q);
selected_iv = zeros(1, Q);
saved_snapshots = cell(1, Q);

% ---- 3. 相位聚焦、角度估计和距离/速度插值 ----
for ii = 1:numel(idx)
    if detected >= Q
        break;
    end
    [ir, iv] = ind2sub([Ns, L], idx(ii));
    nr = nr_vec(ir);   % 0-based 距离 bin
    nv = nv_vec(iv);   % 多普勒 bin (已 shift)
    % 抑制已选目标附近的重复峰，避免将同一目标重复计数。
    if detected > 0
        if any(abs(ir - selected_ir(1:detected)) <= nms_r & ...
               abs(iv - selected_iv(1:detected)) <= nms_v)
            continue;
        end
    end
    omega_r = 2 * pi * nr / Ns;
    omega_v = 2 * pi * nv / L;
    phase_n = exp(-1j * esprit_n_vec * omega_r);
    phase_l = exp(-1j * esprit_l_vec * omega_v);
    W_focus = phase_n * phase_l.';   % 按实际采样位置构造聚焦权重
    snapshots=zeros(Mx*My,U);
    for k=1:U
        weights=conj(rx_cube.symbol_sub(k,:)./abs(rx_cube.symbol_sub(k,:))).'.*W_focus(:);
        snap=reshape(rx_cube.sub,Mx*My,[])*weights;
        snapshots(:,k)=snap(:);
    end
    saved_snapshots{detected+1}=snapshots;
    nr_frac = double(nr); % 由相邻三个功率点插值，细化距离FFT峰的位置。
    ir_left  = mod(ir - 2, Ns) + 1;
    ir_right = mod(ir, Ns) + 1;
    Pl = P(ir_left, iv);
    Pc = P(ir, iv);
    Pr = P(ir_right, iv);
    denom_interp = Pl - 2*Pc + Pr;
    if abs(denom_interp) > eps
        delta_r = 0.5 * (Pl - Pr) / denom_interp;
        delta_r = max(min(delta_r, 0.5), -0.5);
        nr_frac = nr_frac + delta_r;
    end
    R_val = mod(-params.c * nr_frac / (2 * Ns * delta_f), Rmax);
    % 多普勒FFT功率峰值的三点插值。
    nv_frac = double(nv);
    if iv > 1 && iv < L
        Pl = P(ir, iv-1);
        Pc = P(ir, iv);
        Pr = P(ir, iv+1);
        denom_interp = Pl - 2*Pc + Pr;
        if abs(denom_interp) > eps
            delta_v = 0.5 * (Pl - Pr) / denom_interp;
            delta_v = max(min(delta_v, 0.5), -0.5);
            nv_frac = nv_frac + delta_v;
        end
    end
    v_val = params.c * nv_frac / (2 * L * params.Ts * params.fc);
    detected = detected + 1;
    R_est(detected)     = R_val;
    v_est(detected)     = v_val;
    selected_ir(detected) = ir;
    selected_iv(detected) = iv;
end
% 距离-多普勒已分离的快拍直接用全阵列匹配，避免相邻相位的噪声乘积及投影偏差。
[angles,angle_info]=coarse_array_angles(saved_snapshots(1:detected),params);
theta_est(1:detected)=angles(:,1); phi_est(1:detected)=angles(:,2);
estimate=[R_est(:),v_est(:),theta_est(:),phi_est(:)];
peak=P(sub2ind(size(P),selected_ir(1:detected),selected_iv(1:detected)));
info.locked=detected==Q && all(peak/max(median(P(:)),eps)>45); % 全部目标峰相对功率谱中位数超过门限，才进入精估计。
info.runtime=toc(t_baseline);
info.angle_snapshots=saved_snapshots(1:detected);
info.angle_fit=angle_info;
end
