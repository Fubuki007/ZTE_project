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
saved_snapshots = cell(1, Q);    % 保存空间快拍供后续干扰消除
kw_ura = 2 * pi * params.d / params.lambda;
mx_vec = (0:Mx-1).';
my_vec = (0:My-1).';

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
    [left,~,~]=svd(snapshots,'econ'); % 提取多用户空间快拍的主导方向用于测角。
    spatial_snap=reshape(left(:,1),Mx,My);
    saved_snapshots{detected+1}=spatial_snap;
    [theta_val,phi_val] = estimate_angle(spatial_snap,params);
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
    theta_est(detected) = theta_val;
    phi_est(detected)   = phi_val;
    R_est(detected)     = R_val;
    v_est(detected)     = v_val;
    selected_ir(detected) = ir;
    selected_iv(detected) = iv;
end
% ---- 4. 空间干扰消除 ----
num_refine = 2;  % 精化迭代次数
for refine_iter = 1:num_refine
    theta_prev = theta_est(1:detected);
    phi_prev   = phi_est(1:detected);
    for i = 1:detected
        y = saved_snapshots{i}(:);
        y_orig_norm = norm(y);
        for j = 1:detected
            if j == i, continue; end
            th_j = theta_prev(j);
            ph_j = phi_prev(j);
            u_j = sind(th_j) * cosd(ph_j);
            v_j = sind(th_j) * sind(ph_j);
            ax_j = exp(1j * kw_ura * mx_vec * u_j);
            ay_j = exp(1j * kw_ura * my_vec * v_j);
            a_j = ax_j * ay_j.';           % (Mx, My)
            a_j_vec = a_j(:);
            a_j_vec = a_j_vec / (norm(a_j_vec) + eps);
            y = y - a_j_vec * (a_j_vec' * y); % 从当前快拍中减去其他目标方向的投影分量。
        end
        if norm(y) < 0.1 * y_orig_norm
            y = saved_snapshots{i}(:);
        end
        spatial_nulled = reshape(y, Mx, My);
        [theta_est(i),phi_est(i)] = estimate_angle(spatial_nulled,params);
    end
end
estimate=[R_est(:),v_est(:),theta_est(:),phi_est(:)];
peak=P(sub2ind(size(P),selected_ir(1:detected),selected_iv(1:detected)));
info.locked=detected==Q && all(peak/max(median(P(:)),eps)>45); % 全部目标峰相对功率谱中位数超过门限，才进入精估计。
info.runtime=toc(t_baseline);
end

function [theta_val,phi_val] = estimate_angle(spatial_snap,params)
% 相邻阵元相位差，两处测角共用。
sx1 = spatial_snap(1:end-1, :);
sx2 = spatial_snap(2:end, :);
phi_x = angle(sum(conj(sx1(:)) .* sx2(:)));
sy1 = spatial_snap(:, 1:end-1);
sy2 = spatial_snap(:, 2:end);
phi_y = angle(sum(conj(sy1(:)) .* sy2(:)));
u_hat = -phi_x * params.lambda / (2 * pi * params.d);
v_hat = -phi_y * params.lambda / (2 * pi * params.d);
u_hat = max(min(u_hat, 1), -1); % 方向余弦限制在物理可行范围内。
v_hat = max(min(v_hat, 1), -1);
sin_theta = min(sqrt(u_hat^2 + v_hat^2), 1);
theta_val = asind(sin_theta);
phi_val   = atan2d(v_hat, u_hat);
end
