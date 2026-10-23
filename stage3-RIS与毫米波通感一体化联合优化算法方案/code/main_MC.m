%% 蒙特卡洛
clear; close all; clc;
rng('shuffle');
root=fileparts(mfilename('fullpath')); addpath(root);
folder=fullfile(root,'results');
if ~exist(folder,'dir')
    mkdir(folder); 
end
NMC=300; Nsnr=50; Nrepeat=50;
p0=build_default_params();
methods={'无RIS','RIS辅助'}; 

% ---- 1. 接收天线数与输入SNR ----
for M=[4 16]
    for snr=-50:5:10
        p=p0; p.N=3168; p.Mx=sqrt(M); p.My=sqrt(M); p.SNR=snr;
        p.B=p.N*p.delta_f; p.fref=p.fc-floor(p.N/2)*p.delta_f;
        p.resolution=p.c/(2*p.B);
        rmse=measure_rmse(p,NMC);
        save(fullfile(folder,sprintf('rx_%d_snr_%d.mat',M,snr)),'p','NMC','methods','rmse');
        fprintf('接收天线%d，SNR=%g dB，完成%d次\n',M,snr,NMC);
    end
end

% ---- 2. 观测符号数与输入SNR ----
for L=[16 64 256]
    for snr=-60:5:10
        p=p0; p.Mx=4; p.My=4; p.K=L; p.SNR=snr;
        rmse=measure_rmse(p,NMC);
        save(fullfile(folder,sprintf('cpi_%d_snr_%d.mat',L,snr)),'p','NMC','methods','rmse');
        fprintf('符号数%d，SNR=%g dB，完成%d次\n',L,snr,NMC);
    end
end

% ---- 3. 输出SNR ----
NMC=Nsnr;
for M=[9 25 49 100 196 400]
    p=p0; p.Mx=sqrt(M); p.My=sqrt(M); p.SNR=10;
    snr=measure_snr(p,NMC);
    save(fullfile(folder,sprintf('snr_rx_%d.mat',M)),'p','NMC','methods','snr');
    fprintf('输出SNR：接收天线%d\n',M);
end
for L=[16 32 64 128 256 512 1024]
    p=p0; p.K=L; p.SNR=10;
    snr=measure_snr(p,NMC);
    save(fullfile(folder,sprintf('snr_cpi_%d.mat',L)),'p','NMC','methods','snr');
    fprintf('输出SNR：符号数%d\n',L);
end

% ---- 4. 三类阵列规模的运行时间 ----
values={[4 9 16 25 36],[9 16 25 36 49 64],[4 16 64 256 1024]};
prefix={'runtime_tx','runtime_rx','runtime_ris'};
for group=1:3
    for value=values{group}
        p=p0; p.SNR=10; side=sqrt(value);
        if group==1, p.Ntx=side; p.Nty=side; end
        if group==2, p.Mx=side; p.My=side; end
        if group==3, p.ris_side=side; end
        ris_sensing(p); % 先预热，再记录处理与观测时间。
        times=zeros(Nrepeat,2);
        for m=1:Nrepeat
            data=simulate_radar_channel_3d(p);
            [~,coarse]=joint_estimator_fast(data,p);
            result=ris_sensing(p);
            times(m,:)=[coarse.runtime+p.K*p.Ts,result.latency];
        end
        latency=mean(times,1);
        save(fullfile(folder,sprintf('%s_%d.mat',prefix{group},value)),'p','Nrepeat','methods','latency');
        fprintf('%s：%d\n',prefix{group},value);
    end
end
run(fullfile(root,'plot_figures','plot_results.m'));

function rmse=measure_rmse(p,NMC)
squared=zeros(2,4);
for m=1:NMC
    result=ris_sensing(p);
    coarse=evaluate_estimation(result.coarse,p);
    fine=evaluate_estimation(result.estimate,p);
    squared=squared+[coarse.rmse.^2;fine.rmse.^2];
end
rmse=sqrt(squared/NMC); % 行：两种方法；列：距离、速度、俯仰角、方位角。
end

function snr=measure_snr(p,NMC)
% 相同抽样和投影域内，以各目标无噪声回波能量/噪声功率定义输出SNR。
power=zeros(1,2);
for m=1:NMC
    [data,np]=simulate_radar_channel_3d(p);
    initial=joint_estimator_fast(data,p);
    times=round(linspace(0,p.K-1,min(p.K,p.fine_l)));
    for s=1:2
        o=prepare_ris_observation(initial,p,times(s:2:end));
        d=optimize_ris_joint(initial,p,(s-1)*pi);
        for q=1:p.Q
            g=channel_geometry(p.truth(q,:),p); % 真值仅用于构造无噪声信号，统计输出功率。
            phase=exp(-1j*2*pi*p.delta_f/p.c*o.n_grid*g.distance ...
                +1j*2*pi*o.time_grid*g.doppler);
            direct=(g.transmit'*data.W*o.symbol).';
            Y=p.alpha(q)*g.receive*(phase(:,1).*direct).';
            power(1)=power(1)+norm(Y*conj(o.B),'fro')^2/np;
            signal=([g.transmit';g.to_ris']*d.W*o.symbol).';
            c=(d.phase.'*g.V)*exp(-1j*2*pi*p.fref/p.c ...
                *(norm(p.ris_pos)+g.rr-p.truth(q,1)));
            wave=[phase(:,1).*signal(:,1)+c*phase(:,2).*signal(:,2), ...
                c*phase(:,2).*signal(:,1)+c^2*phase(:,3).*signal(:,2)];
            Y=p.alpha(q)*[g.receive,g.from_ris]*wave.';
            power(2)=power(2)+norm(Y*conj(o.B),'fro')^2/np;
        end
    end
end
snr=10*log10(power/(NMC*p.Q)); % 两组观测能量相加，目标与试验在线性域取均值。
end
