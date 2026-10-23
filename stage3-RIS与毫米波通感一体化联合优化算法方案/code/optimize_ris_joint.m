function design = optimize_ris_joint(z,p,phase_code,warm)
% 原方案 max min Jq：SCA更新W，逐阵元枚举离散相位。

% ---- 1. 根据粗位置初始化RIS离散相位和多用户信道 ----
U=p.K_stream; Nt=p.Ntx*p.Nty; Q=size(z,1);
gamma=10.^(p.comm_sinr_db/10); noise=p.comm_noise;
g=channel_geometry(z,p);
gd=g.transmit/sqrt(Nt);
gr=g.to_ris/sqrt(Nt);
levels=exp(1j*2*pi*(0:2^p.ris_bits-1)/2^p.ris_bits);
V=g.V;
weights=exp(1j*phase_code*(0:Q-1)); % 两组配置使用不同的目标相位权重。
angle0=angle(sum(conj(V)./max(abs(V),eps).*weights,2));
phase=exp(1j*2*pi/2^p.ris_bits*round(angle0*2^p.ris_bits/(2*pi)));
if nargin>=4 && ~isempty(warm), phase=warm.phase; end
c=phase.'*V; % 将各RIS阵元的反射响应叠加到目标方向。
users=[p.user_R(:),zeros(U,1),p.user_theta(:),p.user_phi(:)];
user=channel_geometry(users,p);
carrier=exp(-1j*2*pi*p.fc/p.c*(norm(p.ris_pos)+user.rr-p.user_R(:).'));
user.V=user.V.*carrier;
H=user.transmit+user.to_ris*conj(phase.'*user.V); % 合并用户的直达与RIS反射通信信道。

% ---- 2. 用ZF预编码初始化发射波束，再交替优化波束和RIS相位 ----
W=H/(H'*H); W=W/norm(W,'fro'); % 零迫抑制用户间干扰，并归一化总发射功率。
if nargin>=4 && ~isempty(warm), W=warm.W; end
options=optimoptions('coneprog','Display','none','ConstraintTolerance',1e-7, ...
    'OptimalityTolerance',1e-7,'LinearSolver','normal','MaxIterations',200);
n=Nt*U;
solver_flags=[];
for outer=1:p.outer_iterations
    [cones,Aeq]=communication_cones(H,gamma*(1+1e-4),noise);
    % 从不可行初值恢复时先解纯可行性问题，不能以照射能量拒绝可行解。
    if norm(W,'fro')>1+1e-6 || any(sinr_value(H'*W,noise)<gamma)
        [xf,~,ff]=coneprog(zeros(2*n+1,1),cones,[],[],Aeq,zeros(U,1),[],[],options);
        solver_flags(end+1)=ff;
        if ~isempty(xf)
            candidate=reshape(xf(1:n)+1j*xf(n+(1:n)),Nt,U);
            if norm(candidate,'fro')<=1+1e-6 && all(sinr_value(H'*candidate,noise)>=gamma)
                W=candidate;
            end
        end
    end

    % 固定RIS相位，将最弱目标照射能量的优化转化为逐次凸近似问题。
    for iteration=1:p.sca_iterations
        for k=1:U
            W(:,k)=W(:,k)*exp(-1j*angle(H(:,k)'*W(:,k))); 
        end
        A=zeros(Q,2*n+1); b=zeros(Q,1);
        for q=1:Q
            Sq=gd(:,q)*gd(:,q)'+abs(c(q))^2*(gr*gr');
            gradient=Sq*W; % 在当前发射波束处线性化目标照射能量。
            A(q,:)=[-2*real(gradient(:)).',-2*imag(gradient(:)).',1];
            b(q)=-real(sum(conj(W(:)).*gradient(:)));
        end
        f=zeros(2*n+1,1); f(end)=-1; % 最小化负的公共能量下界，即提高最弱目标的照射能量。
        [x,~,flag]=coneprog(f,cones,A,b,Aeq,zeros(U,1),[],[],options);
        solver_flags(end+1)=flag;
        if isempty(x) || ~ismember(flag,[1 -7])
            continue;
        end
        candidate=reshape(x(1:n)+1j*x(n+(1:n)),Nt,U);
        if norm(candidate,'fro')>1+1e-6 || any(sinr_value(H'*candidate,noise)<gamma)
            continue; % 数值求解未满足约束时保留上一可行波束。
        end
        old=min(energy(W,gd,gr,c)); new=min(energy(candidate,gd,gr,c)); %更新发射波束前后，照射最弱的那个目标有没有改善。
        if new>=old
            W=candidate; 
        end
    end

    if isfield(p,'ris_enabled') && ~p.ris_enabled, continue; end
    % 固定发射波束，逐阵元枚举量化相位，保留满足通信SINR且提升目标能量的相位。
    for index=1:numel(phase)
        selected=phase(index); best=min(energy(W,gd,gr,c));
        for value=levels
            delta=value-phase(index); trial=c+delta*V(index,:);
            Hnext=H+user.to_ris*conj(delta*user.V(index,:));
            score=min(energy(W,gd,gr,trial));
            if score>best && all(sinr_value(Hnext'*W,noise)>=gamma)
                selected=value; best=score;
            end
        end
        delta=selected-phase(index);
        c=c+delta*V(index,:); H=H+user.to_ris*conj(delta*user.V(index,:));
        phase(index)=selected;
    end
end
design=struct('W',W,'phase',phase, ...
    'sinr',sinr_value(H'*W,noise),'solver_flags',solver_flags, ...
    'illumination',energy(W,gd,gr,c));
design.feasible=norm(W,'fro')<=1+1e-6 && all(design.sinr>=gamma);
end


function value=energy(W,gd,gr,c)
% 计算每个目标的直达与RIS辅助照射能量之和。
value=sum(abs(gd'*W).^2,2).'+abs(c).^2*sum(abs(gr'*W).^2);
end


function value=sinr_value(Y,noise)
% 对角项是用户期望信号，其余列是其他用户的数据流干扰。
desired=abs(diag(Y)).^2;
value=desired./(sum(abs(Y).^2,2)-desired+noise);
end

function [cones,equality]=communication_cones(H,gamma,noise)
% 将总功率约束和用户SINR约束写成二阶锥，发射波束用实部、虚部表示。
[Nt,U]=size(H); n=Nt*U; nv=2*n+1;
A=[speye(2*n),sparse(2*n,1)]; d=zeros(nv,1);
cones=secondordercone(A,zeros(2*n,1),d,-1); % 约束所有波束的总功率不超过1。
equality=zeros(U,nv);
for u=1:U
    realpart=zeros(U,nv); imagpart=zeros(U,nv);
    for j=1:U
        ix=(j-1)*Nt+(1:Nt);
        realpart(j,ix)=real(H(:,u)).'; realpart(j,n+ix)=imag(H(:,u)).';
        imagpart(j,ix)=-imag(H(:,u)).'; imagpart(j,n+ix)=real(H(:,u)).';
    end
    other=[1:u-1,u+1:U];
    A=[realpart(other,:);imagpart(other,:);zeros(1,nv)];
    b=zeros(size(A,1),1); b(end)=-sqrt(noise(u));
    d=realpart(u,:).'/sqrt(gamma(u));
    cones(u+1)=secondordercone(A,b,d,0);
    equality(u,:)=imagpart(u,:); % 令期望信号虚部为零，便于表示SINR锥约束。
end
end

