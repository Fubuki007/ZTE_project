function [initial,info]=uav_coarse(p,d,seed)
% Stage-3 DD acquisition with a fixed thermal noise floor, not per-case SNR.
rng(seed,'twister'); N=p.N; L=p.K; U=p.K_stream; M=p.Mx*p.My;
levels=[-3 -1 1 3]/sqrt(10);
S=levels(randi(4,U,N*L))+1j*levels(randi(4,U,N*L));
g=channel_geometry(p.truth,p); echo=zeros(N*L,p.Q);
for q=1:p.Q
    phase=exp(-1j*4*pi*p.delta_f*(0:N-1).'*p.R_true(q)/p.c) ...
        *exp(1j*4*pi*p.Ts*(0:L-1)*p.v_true(q)/p.lambda);
    echo(:,q)=p.alpha(q)*((g.transmit(:,q)'*d.W)*S).'.*phase(:);
end
md=ceil(M/2);
noise=sqrt(p.noise_power/2)*(randn(N,L)+1j*randn(N,L));
data.rd=reshape(echo*g.receive(md,:).',N,L)+noise;
data.n=round(linspace(1,N,min(N,p.coarse_n)));
data.l=round(linspace(1,L,min(L,p.coarse_l)));
index=data.n(:)+(data.l(:).'-1)*N;
sub=g.receive*echo(index(:),:).';
for m=1:M
    if m==md
        same=data.rd(data.n,data.l); sub(m,:)=same(:).';
    else
        sub(m,:)=sub(m,:)+sqrt(p.noise_power/2)*(randn(1,numel(index))+1j*randn(1,numel(index)));
    end
end
data.sub=reshape(sub,p.Mx,p.My,numel(data.n),numel(data.l));
data.symbol=S; data.symbol_sub=S(:,index(:)); data.W=d.W;
[initial,info]=joint_estimator_fast(data,p);
info.input_snr_db=10*log10(mean(abs(echo*g.receive(md,:).').^2)/p.noise_power);
end
