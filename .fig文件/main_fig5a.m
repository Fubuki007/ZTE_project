%% ------------------------------------------------------------------------------------------------
clear;
clc;
rng('shuffle');
%% --------------------------------simulation parameters--------------------------------------
%%test parameters
Ntest =5e2;
Nr_range_dB=7.5:2.5:20;
Nr_range=round( 10.^(0.1.*Nr_range_dB)  );
SNR=10^(0.1*10);
%%system parameters
para.mod_order=16;
para.c = 3*1e8;
para.fc=28*1e9;
para.Nt=16;
para.L=256;
para.dt=  para.c/para.fc/2;
para.dr=  para.c/para.fc/2;
para.Ns= 512;
para.delta_f= 120e3;
para.T_s=1/para.delta_f;
para.T_cp=0.59e-6;
para.T_s_cp=para.T_s+para.T_cp;

%%ISAC User parameters
para.K =1;
tpara.N=1;
%%noise paramters
para.sigma_s = sqrt(10^(    -90 /10  ) );
%%channel parameters
%% ------ target information -----------------------
a_zero_padding=1;
tpara.N_fft_v=a_zero_padding*para.L;
tpara.N_fft_d=a_zero_padding*para.Ns;
%%SNR plot preparation
SNRa=zeros(2,length(Nr_range));
SNRn=zeros(7,length(Nr_range));

SNRa_sum=zeros(2,length(Nr_range));
SNRn_sum=zeros(7,length(Nr_range));
for i_HChange=1:Ntest
    %% 随机产生ISAC目标 以及生成相应的信道信息
    tpara.thelta_du=-30 + (30+30).*rand(tpara.N,1);
    tpara.thelta_rad=tpara.thelta_du/180*pi;
    tpara.R=40 + (80-40).*rand(tpara.N,1);
    tpara.v=-50 + (50+50).*rand(tpara.N,1);
    true_adv=[tpara.thelta_du,tpara.R,tpara.v];
    user_a=tpara.thelta_rad;
    user_d=tpara.R;
    for i_Nr=1:length(Nr_range)
        para.Nr=Nr_range(i_Nr);
        
        tpara.N_fft_a=a_zero_padding*para.Nr;
        xianshi=['外层循环改变次数：',num2str(i_HChange),'Nr:',num2str(para.Nr)];
        disp(xianshi);
        %%视距信道
        H=zeros(para.Nt,para.K,para.Ns);
        for i=1:para.Ns
            for k=1:para.K
                H(:,k,i)= exp(1i*2*pi*(0:para.Nt-1).'*para.dt*sin(user_a(k) )*(para.fc)/para.c);
            end
        end
        %%归一化预编码矩阵（这能保证的是到目标时 各自的能量一样大）
        W=zeros(para.Nt,para.K,para.Ns);
        for i=1:para.Ns
            W(:,:,i)=H(:,:,i)/(H(:,:,i)'*H(:,:,i));
            W(:,:,i)=1/norm(W(:,:,i),'fro')*W(:,:,i);
        end
        %%发射数据流
        DATA=randi([0 para.mod_order-1],para.K,para.L,para.Ns);
        DATA2=reshape(DATA,[para.K*para.Ns,para.L]);
        S=zeros(para.K,para.L,para.Ns);
        modnum=1;
        for mod_type=1:modnum
            if mod_type==1
                for i=1:para.Ns
                    S(:,:,i)=qammod( DATA(:,:,i), para.mod_order,'UnitAveragePower',true);
                end
            else
                for i=1:para.Ns
                    S(:,:,i)=pskmod( DATA(:,:,i), para.mod_order);
                end
            end
            X0=pagemtimes(W,S);
            %%通信和感知接收信号
            [D_r0,SNRr0]=echo_generate(tpara,para,W,X0); %%感知回波和接收SNR
            para.sigma_beta= sqrt(SNR/SNRr0);   %%beta*Dr_0=Dr*twowayloss so, X=beta/twowaylos*X_0;
            D_r_nfree=para.sigma_beta*D_r0;
            %% -------------------- extended MS-based processing ---------------
            Noise=para.sigma_s*(randn(para.Nr,para.Ns,para.L)+1i*randn(para.Nr,para.Ns,para.L))/sqrt(2);
            D_r=D_r_nfree+Noise;
            [SNRa(mod_type,i_Nr),SNRn((mod_type-1)*3+1,i_Nr)]=SNR_of_my_proposed(para,tpara,D_r,X0);
            %% -------------- Comparisons ------------------
            %compa1
            [SNRn((mod_type-1)*3+2,i_Nr)]=SNR_of_compAlg_29(para,tpara,D_r);
            %compa2
            [SNRn((mod_type-1)*3+3,i_Nr)]=SNR_of_compAlg_28(para,tpara,D_r);
        end
        %LFMCW
        [SNRn(7,i_Nr)]=SNR_of_LFMCW(H,para,tpara,SNR);
    end
    SNRa_sum=SNRa_sum+SNRa;
    SNRn_sum=SNRn_sum+SNRn;
end
fSNRa=SNRa_sum/Ntest;
fSNRn=SNRn_sum/Ntest;

figure;
semilogx(Nr_range, 10*log10(fSNRn(7,:)),'o-k','linewidth',1.5); %%LFMCW黑色
hold on;
plot(Nr_range, 10*log10(fSNRn(3,:)),'v-','color','#096C28','linewidth',1.5); %%[28]绿色
plot(Nr_range, 10*log10(fSNRn(2,:)),'d-','color','#7D2E8D','linewidth',1.5);%%[29]紫色
plot(Nr_range, 10*log10(fSNRn(1,:)),'x-r','linewidth',1.5); %%提出 红色

xlabel('The number of receive antennas');
ylabel('Output-SNR (dB)');
legend('3D-DFT, LFMCW', ...
        'Successive [28]',...
        'Successive [29]',...
        'Proposed',...
    'Location','northwest');
grid on;

