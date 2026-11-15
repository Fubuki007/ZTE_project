function [D,derivatives] = pr_dictionary(z,obs,design,p,compute_derivatives)
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
