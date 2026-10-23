function [data,noise_power] = simulate_radar_channel_3d(p)
% 多用户粗估计阶段：原始DD回波、独立16QAM、公共总功率ZF。
% 合成RD通道和空间子网格；同一采样点共享同一噪声。

% ---- 1. 已知通信信道、ZF及各用户符号 ----
N=p.N; L=p.K; U=p.K_stream; M=p.Mx*p.My;
users=[p.user_R(:),zeros(U,1),p.user_theta(:),p.user_phi(:)];
user=channel_geometry(users,p);
H=user.transmit;
W=H/(H'*H); W=W/norm(W,'fro'); % 零迫预编码，并保持所有数据流的总功率为1。
levels=[-3 -1 1 3]/sqrt(10); % 16QAM实部、虚部电平，平均符号功率归一化。
S=levels(randi(4,U,N*L))+1j*levels(randi(4,U,N*L));
target=channel_geometry(p.truth,p);
At=target.transmit;
A=target.receive;

% ---- 2. 实际发射回波 a_q^H W S ----
echo=zeros(N*L,p.Q);
for q=1:p.Q
    phase=exp(-1j*4*pi*p.delta_f*(0:N-1).'*p.R_true(q)/p.c) ...
        *exp(1j*4*pi*p.Ts*(0:L-1)*p.v_true(q)/p.lambda);
    waveform=(At(:,q)'*W)*S; % 计算实际照射到该目标的多用户叠加波形。
    echo(:,q)=p.alpha(q)*waveform(:).*phase(:);
end
power=real(sum(sum((A'*A).*(echo'*echo))))/(M*N*L);
noise_power=power/10^(p.SNR/10); % 按直达回波功率和感知输入SNR标定噪声。
md=ceil(M/2);
noise=sqrt(noise_power/2)*(randn(N,L)+1j*randn(N,L));
data.rd=reshape(echo*A(md,:).',N,L)+noise; % 用一个接收阵元的完整时频回波进行RD检测。

% ---- 3. 空间子网格与RD通道共享原始样本 ----
data.n=round(linspace(1,N,min(N,p.coarse_n)));
data.l=round(linspace(1,L,min(L,p.coarse_l)));
index=data.n(:)+(data.l(:).'-1)*N; % 将选中的子载波和符号位置转换为线性索引。
sub=A*echo(index(:),:).';
for m=1:M
    if m==md
        same=data.rd(data.n,data.l); sub(m,:)=same(:).'; 
    else
        z=sqrt(noise_power/2)*(randn(numel(data.n),numel(data.l))+1j*randn(numel(data.n),numel(data.l)));
        sub(m,:)=sub(m,:)+z(:).';
    end
end
data.sub=reshape(sub,p.Mx,p.My,numel(data.n),numel(data.l));
data.symbol=S; data.symbol_sub=S(:,index(:)); data.W=W;
end

