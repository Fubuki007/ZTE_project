function obs = prepare_ris_observation(initial,p,symbols,known_symbols)
% 精估计在整个带宽及观测时段抽取样本，投影基在精化过程中保持不变。

% ---- 1. 抽取覆盖整个带宽和观测时段的样本，生成已知通信符号 ----
obs.n=round(linspace(0,p.N-1,min(p.N,p.fine_n))).';
obs.time=symbols(:)*p.Ts; % 保留原始符号时刻，测速仍利用完整的时间跨度。
N=numel(obs.n); L=numel(obs.time); U=p.K_stream;
obs.n_grid=repmat(obs.n,L,1); obs.time_grid=repelem(obs.time,N); % 按子载波优先的顺序展开时频网格。
levels=[-3 -1 1 3]/sqrt(10);
if nargin<4
    obs.symbol=levels(randi(4,U,N*L))+1j*levels(randi(4,U,N*L));
else
    assert(isequal(size(known_symbols),[U,N*L]));
    obs.symbol=known_symbols; % 配对实验在共同采样时刻使用相同16QAM。
end

% ---- 2. 在粗位置附近构造回波模板及距离、速度变化方向 ----
g=channel_geometry(initial,p);
rr=g.rr; vr=g.vr; db=norm(p.ris_pos);
B=zeros(N*L,9*size(initial,1)*U); column=0;
xn=(obs.n-mean(obs.n))/max(std(obs.n),eps);
xl=(obs.time-mean(obs.time))/max(std(obs.time),eps);
for q=1:size(initial,1)
    distance=[2*initial(q,1),db+rr(q)+initial(q,1),2*(db+rr(q))];
    doppler=[2*initial(q,2),initial(q,2)+vr(q),2*vr(q)]/p.lambda;
    for a=1:3
        phase=exp(-1j*2*pi*p.delta_f/p.c*obs.n*distance(a)) ...
            *exp(1j*2*pi*obs.time.'*doppler(a));
        atoms=[phase(:),reshape(phase.*xn,[],1),reshape(phase.*xl.',[],1)]; % 基础相位及频率、时间加权项。
        for user=1:U
            B(:,column+(1:3))=atoms.*obs.symbol(user,:).'/sqrt(N*L); % 每个用户的已知符号进入投影基。
            column=column+3;
        end
    end
end
% ---- 3. 正交化投影基，去除重复方向并保持投影后的白噪声性质 ----
G=B'*B; G=(G+G')/2; [R,flag]=chol(G);
if flag==0 && rcond(R)>1e-4
    obs.B=B/R; obs.rank=size(B,2); % 正对角Cholesky给出固定、可复现的基相位。
else
    [V,E]=eig(G); e=real(diag(E)); keep=e>1e-8; % 基向量近似相关时，仅保留有效特征方向。
    obs.B=B*(V(:,keep)./sqrt(e(keep).')); obs.rank=sum(keep);
end
end

