function [z,info] = refine_ris_parameters(y,obs,design,initial,p)
% 精估计：以粗估计为初值，通过拟合多路径回波修正目标参数。
% y仅堆叠两组RIS配置的投影回波；各配置共享每个目标的四个路径复系数。
% initial为粗估计；输出z每行是[距离,速度,俯仰角,方位角]。
% 几何建模 → 路径模板 → 幅度拟合 → 参数增量 → 步长更新。

% ---- 1. 粗估计初始化：确定目标参数及局部估计区间U_q ----
betas=2.^-(0:11); % 从1开始逐次减半。
z = initial;
Q = size(z,1);
scale = repmat([.05 1 .2 .2],Q,1); % 缩放系数,帮助稳定求解, 平衡距离、速度和角度的不同数值尺度。
limit = repmat([max(.6,2*p.resolution), ...
    max(10,p.lambda/(p.K*p.Ts)),15,30],Q,1); % 防止迭代偏离粗估计太远, 距离、速度和两角度相对粗估计的允许偏移。

% 固定迭代轮数，每轮更新模板、幅度与目标参数。
for iteration = 1:p.fine_iterations
    % ---- 2. 由共同几何参数构造全部目标的路径模板D ----
    [D,derivatives] = path_dictionary(z,obs,design,p,true); % D=[D_1,...,D_Q]，同时计算参数导数。

    % ---- 3. 固定目标参数，最小二乘拟合路径复幅度 ----
    inverse = pinv(D,1e-8); % 文档中的D伪逆。
    alpha = inverse*y; % 各目标各路径的复系数alpha。
    residual = y-D*alpha; % 残差e=y-D*alpha。
    cost = norm(residual)^2;

    % ---- 4. 构造有效雅可比，消去幅度变化对参数修正的影响 ----
    J = zeros(numel(y),4*Q); % 固定alpha时，预测回波对目标参数的导数。
    for q = 1:Q
        count=size(D,2)/Q; columns=(q-1)*count+(1:count); % 取当前目标的全部路径列。
        for parameter = 1:4
            j = q+(parameter-1)*Q; % 参数列按全部距离、全部速度、两类角度排列。
            J(:,j)=derivatives{q,parameter}*alpha(columns)*scale(q,parameter);
        end
    end
    J = J-D*(inverse*J); % J_eff：去除可由路径幅度变化解释的导数分量。

    % ---- 5. 最小化线性化残差，求距离、速度和角度增量 ----
    Jreal = [real(J);imag(J)]; % 堆叠实部、虚部，参数增量取实数。
    ereal = [real(residual);imag(residual)];
    step = lsqminnorm(Jreal,ereal); % 稳定求解文档中的实数最小二乘。
    dz = reshape(step,Q,4).*scale; % 恢复为各目标的实际参数增量。

    % ---- 6. 搜索步长：更新参数、重估幅度，保留残差更小的结果 ----
    % 超出局部区间或残差未下降时减小步长，无改善则保留原参数。
    current=z;
    for beta = betas
        candidate = current+beta*dz;
        if any(abs(candidate-initial)>limit,'all') || ...
                any(candidate(:,1)<1) || any(candidate(:,3)<.01 | candidate(:,3)>89.99)
            continue;
        end
        Dnew = path_dictionary(candidate,obs,design,p,false);
        new_residual = y-Dnew*(pinv(Dnew,1e-8)*y); % 用新模板重估幅度，比较实际拟合误差。
        if norm(new_residual)^2 < cost
            z = candidate;
            break; % 接受首个使实际残差下降的步长。
        end
    end
end

% ---- 7. 输出精估计参数z及最终拟合残差 ----
D=path_dictionary(z,obs,design,p,false);
info=struct('iterations',iteration,'residual',norm(y-D*(pinv(D,1e-8)*y))^2,'num_paths',4);
end


function [D,derivatives] = path_dictionary(z,obs,design,p,compute_derivatives)
% D：每个目标的四路径共享同一组距离、速度和角度。
% 两组RIS配置使用实际发送符号，共同构造四路径模板。
Q=size(z,1); M=p.Mx*p.My;
% ---- 模板排列：按目标分组，每组为DD、RD、DR、RR ----
C=4; % 每个目标仅含DD、RD、DR、RR四个路径复系数。
rows=M*sum(cellfun(@(o) o.rank,obs));
D=zeros(rows,C*Q); % 按目标分组，每组依次为DD、RD、DR、RR。
derivatives=cell(Q,4);
for q=1:Q
    for j=1:4
        derivatives{q,j}=zeros(rows,C);
    end
end
epsilon=[1e-5 1e-4 1e-5 1e-5]; % 距离、速度和两角度的中心差分步长。
receive=[1 1 2 2]; % 四路径分别从目标、目标、RIS、RIS方向到达接收阵列。
% ---- 根据实际符号、RIS配置和观测时刻构造预测回波 ----
first=0;
for s=1:2
    o=obs{s}; d=design{s};
    frequencies=1:3; % RD与DR共用时延和多普勒。
    ix=first+(1:M*o.rank); first=first+M*o.rank; % 当前配置在堆叠观测中的行位置。

    for q=1:Q
        a=path_coefficients(z(q,:),d,p); % 共同几何参数确定各路径时延、多普勒和空间响应。
        illumination=a.illumination*o.symbol; % 采用本配置实际发送的多用户符号。
        % 频率维相位描述传播时延，时间维相位描述多普勒。
        pn=exp(-1j*2*pi*p.delta_f/p.c*o.n*a.distance(frequencies));
        pl=exp(1j*2*pi*o.time*a.doppler(frequencies));
        phase=reshape(reshape(pn,numel(o.n),1,[]).* ...
            reshape(pl,1,numel(o.time),[]),[],numel(frequencies));
        base=path_waves(phase,illumination);
        ratio=a.response/d.scale(q); % RIS响应的参考幅度由alpha吸收。
        w=[1 ratio ratio ratio^2]; % DD无反射，RD/DR一次反射，RR两次反射。
        waves=zeros(size(o.symbol,2),C*(1+4*compute_derivatives));
        waves(:,1:C)=base.*w;
        ds=zeros(M,2,4); % 接收阵列响应对四类参数的导数。
        
        % 模板求导：几何量作中心差分，再合成各路径导数。
        if compute_derivatives
            for j=1:4
                plus=z(q,:); minus=plus;
                plus(j)=plus(j)+epsilon(j); minus(j)=minus(j)-epsilon(j);
                ap=path_coefficients(plus,d,p); am=path_coefficients(minus,d,p);
                ds(:,:,j)=(ap.space-am.space)/(2*epsilon(j));
                dn=-1j*2*pi*p.delta_f/p.c* ...
                    (ap.distance(frequencies)-am.distance(frequencies))/(2*epsilon(j));
                dt=1j*2*pi*(ap.doppler(frequencies)-am.doppler(frequencies))/(2*epsilon(j));
                dp=phase.*(o.n_grid*dn+o.time_grid*dt); % 时延和多普勒变化引起的相位导数。
                di=(ap.illumination-am.illumination)/(2*epsilon(j))*o.symbol;
                dr=(ap.response-am.response)/(2*epsilon(j)*d.scale(q));
                dw=[0 dr dr 2*ratio*dr]; % 四路径反射权重的导数。
                waves(:,C*j+(1:C))=(path_waves(dp,illumination) ...
                    +path_waves(phase,di)).*w+base.*dw;
            end
        end
        projected=o.B'*waves; % 将模板及其导数投影到与接收数据相同的观测域。
        
        % 组合空间与时频响应，得到路径列d_a,q。
        for path=1:C
            block=a.space(:,receive(path))*projected(:,path).';
            D(ix,C*(q-1)+path)=block(:);
            if compute_derivatives
                for j=1:4
                    block=a.space(:,receive(path))*projected(:,C*j+path).' ...
                        +ds(:,receive(path),j)*projected(:,path).';
                    derivatives{q,j}(ix,path)=block(:); % 同时包含时频波形和接收方向变化的贡献。
                end
            end
        end
    end
end
end

function a = path_coefficients(z,design,p)
% 计算单个目标的路径长度、多普勒、阵列响应及RIS反射系数。
g=channel_geometry(z,p);
a.space=[g.receive,g.from_ris]; % 两类接收方向：目标和RIS。
a.illumination=[g.transmit';g.to_ris']*design.W; % 两类发射照射：直达目标和经过RIS。
a.distance=g.distance;
a.doppler=g.doppler;
a.response=design.phase.'*g.V; % 叠加当前RIS相移下的阵元响应。
end

function waves=path_waves(phase,illumination)
% DD直达、RD发射经RIS、DR接收经RIS、RR双程经RIS。
direct=illumination(1,:).'; waves=phase(:,1).*direct;
reflected=illumination(2,:).';
waves=[waves,phase(:,2).*reflected,phase(:,2).*direct,phase(:,3).*reflected];
end

