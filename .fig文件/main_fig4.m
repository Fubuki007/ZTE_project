%%-------------------------------------------------------------------------
clear;
clc;
rng('shuffle');
%% simulation parameters---------------------------------------------------
%%test parameters
Ntest =5e2;                 %%the number of channel changes
N_trial=10;                 %%the number of AWGN trials in each channel condition
SNR_dB_range=-60:5:40;      %% dB range of sensing receive SNR
range_L=[16,64,256];        %% range of CPI length
%%system parameters
para.mod_order=16;          %%QAM modulation order
para.Nr=16;                 %%number of BS receive antennas
para.Nt=16;                 %%number of BS transmit antennas
para.Ns= 512;               %%number of OFDM subcarriers
para.c = 3*1e8;             %%speed of light
para.fc=28*1e9;             %%carrier frequency
para.dt=  para.c/para.fc/2; %% transmit anttenna spacing
para.dr=  para.c/para.fc/2; %% receive anttenna spacing
para.delta_f= 120e3;        %%subcarrier spacing
para.T_s=1/para.delta_f;    %%OFDM symbol duration
para.T_cp=0.59e-6;          %%OFDM CP duration
para.T_s_cp=para.T_s+para.T_cp;%%OFDM total symbol duration

%%ISAC User parameters
para.K =1;      %%number of ISAC users (ISAC user means that the communication user is also the sensing target)
tpara.N=para.K; %%number of targets
%%noise paramters
para.sigma_c = sqrt( 10^(   -90 /10  ) );%%communication AWGN power
para.sigma_s = sqrt(10^(    -90 /10  ) );%%sensing AWGN power
%%target information
a_zero_padding=1;                       %%zero-padding parameter
tpara.N_fft_a=a_zero_padding*para.Nr;   %%Number of angular bins (DFT-point in the spatial domain)
tpara.N_fft_d=a_zero_padding*para.Ns;   %%Number of range bins (DFT-point in the fast-time domain)
%%RMSE plot preparation
RMSE_sum=zeros(6*length(range_L),3,length(SNR_dB_range));
%%Main loop (channel variation)
for i_HChange=1:Ntest
    RMSE=zeros(6*length(range_L),3,length(SNR_dB_range));
    %%Random generation of ISAC user
    tpara.thelta_du=-30 + (30+30).*rand(tpara.N,1); %%Target angle (degree)
    tpara.thelta_rad=tpara.thelta_du/180*pi;        %%Target angle (rad)
    tpara.R=40 + (80-40).*rand(tpara.N,1);          %%Target range (m)
    tpara.v=-50 + (50+50).*rand(tpara.N,1);         %%Target velocity (m/s)
    true_adv=[tpara.thelta_du,tpara.R,tpara.v];     
    user_a=tpara.thelta_rad;    %%angle of user LoS channel                  
    user_d=tpara.R;             %%range of user LoS channel
    %%second loop (CPI length variation)
    L_num=length(range_L);
    for i_L=1:L_num
        para.L=range_L(i_L);
        tpara.N_fft_v=a_zero_padding*para.L;
        %%LoS channel generation
        H=zeros(para.Nt,para.K,para.Ns);
        for i=1:para.Ns
            for k=1:para.K
                H(:,k,i)= exp(1i*2*pi*(0:para.Nt-1).'*para.dt*sin(user_a(k) )*(para.fc)/para.c);
            end
        end
        %%normalized precoding matrix
        W=zeros(para.Nt,para.K,para.Ns);
        for i=1:para.Ns
            W(:,:,i)=H(:,:,i)/(H(:,:,i)'*H(:,:,i));
            W(:,:,i)=1/norm(W(:,:,i),'fro')*W(:,:,i);
        end
        %%dada stream generation
        DATA=randi([0 para.mod_order-1],para.K,para.L,para.Ns);
        DATA2=reshape(DATA,[para.K*para.Ns,para.L]);
        S=zeros(para.K,para.L,para.Ns);
        for i=1:para.Ns
            S(:,:,i)=qammod( DATA(:,:,i), para.mod_order,'UnitAveragePower',true);
        end
        X0=pagemtimes(W,S);
        %%noise-free echo generation
        [D_r0,SNRr0]=echo_generate(tpara,para,W,X0);            %%obtained echo and the relavent receive SNR
        %%noise-free echo processing
        [Y_nfree1_0,sigma_n1]=my_proposed(para,tpara,D_r0,X0);          %%our proposed algorithm
        [Y_nfree2_0,sigma_n2]=proposed_woscaling(para,tpara,D_r0,X0);%%without scaling method
        [Y_nfree3_0,SNRr1]=LFMCW(H,para,tpara);                 %%LFMCW
        %%third loop (SNR variation)
        for i_SNR=1:length(SNR_dB_range)
            xianshi=['Outerloop：',num2str(i_HChange),'SNR:',num2str(SNR_dB_range(i_SNR)),'(dB)','L:',num2str(para.L)];
            disp(xianshi);
            SNR=10^(0.1*SNR_dB_range(i_SNR));
            %%signal scaling with current SNR
            para.sigma_beta= sqrt(SNR/SNRr0);   %%beta*Dr_0=Dr*twowayloss so, X=beta/twowaylos*X_0;
            Y_nfree1=para.sigma_beta*Y_nfree1_0;
            Y_nfree2=para.sigma_beta*Y_nfree2_0;
            Y_nfree3= sqrt(SNR/SNRr1)*Y_nfree3_0;
            %%forth loop (AWGN trial)
            for i_trial=1:N_trial
                %%LFMCW
                Noise=(randn(tpara.N_fft_a,tpara.N_fft_d,tpara.N_fft_v)+1i*randn(tpara.N_fft_a,tpara.N_fft_d,tpara.N_fft_v))/sqrt(2)*para.sigma_s*sqrt(para.Nr*para.Ns*para.L);
                Y=Y_nfree3+Noise;
                [estimated_adv,~]= peak_finding(Y,para,tpara);
                RMSE((i_L-1)*6+1,:,i_SNR) = RMSE((i_L-1)*6+1,:,i_SNR)+ abs( estimated_adv-true_adv).^2;
                %%proposed
                Noise=zeros(tpara.N_fft_a,tpara.N_fft_d,tpara.N_fft_v);
                for na=1:1:tpara.N_fft_a
                    Noise(na,:,:)=sigma_n1(na).*(randn(1,tpara.N_fft_d,tpara.N_fft_v)+1i*randn(1,tpara.N_fft_d,tpara.N_fft_v))/sqrt(2);
                end
                Y=Y_nfree1+Noise;
                [estimated_adv,~]= peak_finding(Y,para,tpara);      
                RMSE((i_L-1)*6+2,:,i_SNR) = RMSE((i_L-1)*6+2,:,i_SNR)+ abs( estimated_adv-true_adv).^2;
                %%proposed without scaling
                for na=1:1:tpara.N_fft_a
                    Noise(na,:,:)=sigma_n2(na).*(randn(1,tpara.N_fft_d,tpara.N_fft_v)+1i*randn(1,tpara.N_fft_d,tpara.N_fft_v))/sqrt(2);
                end
                Y=Y_nfree2+Noise;
                [estimated_adv2,~]= peak_finding(Y,para,tpara);
                RMSE((i_L-1)*6+3,:,i_SNR)  = RMSE((i_L-1)*6+3,:,i_SNR) + abs( estimated_adv2-true_adv).^2;
                %%sequential algorithm of [29]
                Noise=para.sigma_s*(randn(para.Nr,para.Ns,para.L)+1i*randn(para.Nr,para.Ns,para.L))/sqrt(2);
                D_r_n=para.sigma_beta*D_r0+Noise;
                [estimated_adv3]=compAlg_29(para,tpara,D_r_n,X0);
                RMSE((i_L-1)*6+4,:,i_SNR)  = RMSE((i_L-1)*6+4,:,i_SNR) + abs( estimated_adv3-true_adv).^2;
                %%sequential algorithm of [28]
                [estimated_adv4,~]=compAlg_28(para,tpara,D_r_n,X0,true_adv);
                RMSE((i_L-1)*6+5,:,i_SNR)  = RMSE((i_L-1)*6+5,:,i_SNR) + abs( estimated_adv4-true_adv).^2;  
            end
        end
    end
    RMSE_sum=RMSE_sum+RMSE;
end
fRMSE=sqrt(RMSE_sum/Ntest/N_trial);


%%plot RMSE of angle
figure;plot_term=1;
semilogy(SNR_dB_range, reshape( fRMSE(1,plot_term,:),1,[]),'^-.k','linewidth',1.5); %%LFMCW黑色
hold on;
semilogy(SNR_dB_range, reshape( fRMSE(7,plot_term,:),1,[]),'s-.k','linewidth',1.5); %%LFMCW黑色
semilogy(SNR_dB_range, reshape( fRMSE(13,plot_term,:),1,[]),'o-.k','linewidth',1.5); %%LFMCW黑色

semilogy(SNR_dB_range, reshape( fRMSE(5,plot_term,:),1,[]),'^--','color','#096C28','linewidth',1.5); %%[28]绿色
semilogy(SNR_dB_range, reshape( fRMSE(11,plot_term,:),1,[]),'s--','color','#096C28','linewidth',1.5); %%[28]绿色
semilogy(SNR_dB_range, reshape( fRMSE(17,plot_term,:),1,[]),'o--','color','#096C28','linewidth',1.5); %%[28]绿色

semilogy(SNR_dB_range, reshape( fRMSE(4,plot_term,:),1,[]),'^:','color','#7D2E8D','linewidth',1.5);%%[29]紫色
semilogy(SNR_dB_range, reshape( fRMSE(10,plot_term,:),1,[]),'s:','color','#7D2E8D','linewidth',1.5);%%[29]紫色
semilogy(SNR_dB_range, reshape( fRMSE(16,plot_term,:),1,[]),'o:','color','#7D2E8D','linewidth',1.5);%%[29]紫色

semilogy(SNR_dB_range, reshape( fRMSE(3,plot_term,:),1,[]),'^-','color','#3C59AB','linewidth',1.5);%%无放缩 蓝色
semilogy(SNR_dB_range, reshape( fRMSE(9,plot_term,:),1,[]),'s-','color','#3C59AB','linewidth',1.5);%%无放缩 蓝色
semilogy(SNR_dB_range, reshape( fRMSE(15,plot_term,:),1,[]),'o-','color','#3C59AB','linewidth',1.5);%%无放缩 蓝色

semilogy(SNR_dB_range, reshape( fRMSE(2,plot_term,:),1,[]),'^-r','linewidth',1.5); %%提出 红色
semilogy(SNR_dB_range, reshape( fRMSE(8,plot_term,:),1,[]),'s-r','linewidth',1.5); %%提出 红色
semilogy(SNR_dB_range, reshape( fRMSE(14,plot_term,:),1,[]),'o-r','linewidth',1.5); %%提出 红色


vir1 = semilogy(SNR_dB_range,zeros(1,length(SNR_dB_range)),'-.k','linewidth',1.5);
vir2 = semilogy(SNR_dB_range,zeros(1,length(SNR_dB_range)),'--','color','#096C28','linewidth',1.5); %%[28]绿色
vir3 = semilogy(SNR_dB_range,zeros(1,length(SNR_dB_range)),':','color','#7D2E8D','linewidth',1.5);%%[29]紫色
vir4 = semilogy(SNR_dB_range,zeros(1,length(SNR_dB_range)),'-','color','#3C59AB','linewidth',1.5);%%无放缩 蓝色
vir5 = semilogy(SNR_dB_range,zeros(1,length(SNR_dB_range)),'-r','linewidth',1.5); %%提出 红色
vir6 = semilogy(SNR_dB_range,zeros(1,length(SNR_dB_range)),'^','color','k','linewidth',1.5);
vir7 = semilogy(SNR_dB_range,zeros(1,length(SNR_dB_range)),'s','color','k','linewidth',1.5);
vir8 = semilogy(SNR_dB_range,zeros(1,length(SNR_dB_range)),'o','color','k','linewidth',1.5);
legend([vir1,vir2,vir3,vir4,vir5,vir6,vir7,vir8],{'3D-DFT, LFMCW','Successive [28]','Successive [29]','W/o scal.','Proposed','{\itL=16}','{\itL=64}','{\itL=256}'});

xlabel('SNR (dB)');
ylabel('RMSE of angle estimation (degree)');
grid on;


%%plot RMSE of range
figure;plot_term=2;
semilogy(SNR_dB_range, reshape( fRMSE(1,plot_term,:),1,[]),'^-.k','linewidth',1.5); %%LFMCW黑色
hold on;
semilogy(SNR_dB_range, reshape( fRMSE(7,plot_term,:),1,[]),'s-.k','linewidth',1.5); %%LFMCW黑色
semilogy(SNR_dB_range, reshape( fRMSE(13,plot_term,:),1,[]),'o-.k','linewidth',1.5); %%LFMCW黑色

semilogy(SNR_dB_range, reshape( fRMSE(5,plot_term,:),1,[]),'^--','color','#096C28','linewidth',1.5); %%[28]绿色
semilogy(SNR_dB_range, reshape( fRMSE(11,plot_term,:),1,[]),'s--','color','#096C28','linewidth',1.5); %%[28]绿色
semilogy(SNR_dB_range, reshape( fRMSE(17,plot_term,:),1,[]),'o--','color','#096C28','linewidth',1.5); %%[28]绿色

semilogy(SNR_dB_range, reshape( fRMSE(4,plot_term,:),1,[]),'^:','color','#7D2E8D','linewidth',1.5);%%[29]紫色
semilogy(SNR_dB_range, reshape( fRMSE(10,plot_term,:),1,[]),'s:','color','#7D2E8D','linewidth',1.5);%%[29]紫色
semilogy(SNR_dB_range, reshape( fRMSE(16,plot_term,:),1,[]),'o:','color','#7D2E8D','linewidth',1.5);%%[29]紫色

semilogy(SNR_dB_range, reshape( fRMSE(3,plot_term,:),1,[]),'^-','color','#3C59AB','linewidth',1.5);%%无放缩 蓝色
semilogy(SNR_dB_range, reshape( fRMSE(9,plot_term,:),1,[]),'s-','color','#3C59AB','linewidth',1.5);%%无放缩 蓝色
semilogy(SNR_dB_range, reshape( fRMSE(15,plot_term,:),1,[]),'o-','color','#3C59AB','linewidth',1.5);%%无放缩 蓝色

semilogy(SNR_dB_range, reshape( fRMSE(2,plot_term,:),1,[]),'^-r','linewidth',1.5); %%提出 红色
semilogy(SNR_dB_range, reshape( fRMSE(8,plot_term,:),1,[]),'s-r','linewidth',1.5); %%提出 红色
semilogy(SNR_dB_range, reshape( fRMSE(14,plot_term,:),1,[]),'o-r','linewidth',1.5); %%提出 红色


vir1 = semilogy(SNR_dB_range,zeros(1,length(SNR_dB_range)),'-.k','linewidth',1.5);
vir2 = semilogy(SNR_dB_range,zeros(1,length(SNR_dB_range)),'--','color','#096C28','linewidth',1.5); %%[28]绿色
vir3 = semilogy(SNR_dB_range,zeros(1,length(SNR_dB_range)),':','color','#7D2E8D','linewidth',1.5);%%[29]紫色
vir4 = semilogy(SNR_dB_range,zeros(1,length(SNR_dB_range)),'-','color','#3C59AB','linewidth',1.5);%%无放缩 蓝色
vir5 = semilogy(SNR_dB_range,zeros(1,length(SNR_dB_range)),'-r','linewidth',1.5); %%提出 红色
vir6 = semilogy(SNR_dB_range,zeros(1,length(SNR_dB_range)),'^','color','k','linewidth',1.5);
vir7 = semilogy(SNR_dB_range,zeros(1,length(SNR_dB_range)),'s','color','k','linewidth',1.5);
vir8 = semilogy(SNR_dB_range,zeros(1,length(SNR_dB_range)),'o','color','k','linewidth',1.5);
legend([vir1,vir2,vir3,vir4,vir5,vir6,vir7,vir8],{'3D-DFT, LFMCW','Successive [28]','Successive [29]','W/o scal.','Proposed','{\itL=16}','{\itL=64}','{\itL=256}'});
xlabel('SNR (dB)');
ylabel('RMSE of range estimation (m)');
grid on;


%%plot RMSE of velocity
figure;plot_term=3;
semilogy(SNR_dB_range, reshape( fRMSE(1,plot_term,:),1,[]),'^-.k','linewidth',1.5); %%LFMCW黑色
hold on;
semilogy(SNR_dB_range, reshape( fRMSE(7,plot_term,:),1,[]),'s-.k','linewidth',1.5); %%LFMCW黑色
semilogy(SNR_dB_range, reshape( fRMSE(13,plot_term,:),1,[]),'o-.k','linewidth',1.5); %%LFMCW黑色

semilogy(SNR_dB_range, reshape( fRMSE(5,plot_term,:),1,[]),'^--','color','#096C28','linewidth',1.5); %%[28]绿色
semilogy(SNR_dB_range, reshape( fRMSE(11,plot_term,:),1,[]),'s--','color','#096C28','linewidth',1.5); %%[28]绿色
semilogy(SNR_dB_range, reshape( fRMSE(17,plot_term,:),1,[]),'o--','color','#096C28','linewidth',1.5); %%[28]绿色

semilogy(SNR_dB_range, reshape( fRMSE(4,plot_term,:),1,[]),'^:','color','#7D2E8D','linewidth',1.5);%%[29]紫色
semilogy(SNR_dB_range, reshape( fRMSE(10,plot_term,:),1,[]),'s:','color','#7D2E8D','linewidth',1.5);%%[29]紫色
semilogy(SNR_dB_range, reshape( fRMSE(16,plot_term,:),1,[]),'o:','color','#7D2E8D','linewidth',1.5);%%[29]紫色

semilogy(SNR_dB_range, reshape( fRMSE(3,plot_term,:),1,[]),'^-','color','#3C59AB','linewidth',1.5);%%无放缩 蓝色
semilogy(SNR_dB_range, reshape( fRMSE(9,plot_term,:),1,[]),'s-','color','#3C59AB','linewidth',1.5);%%无放缩 蓝色
semilogy(SNR_dB_range, reshape( fRMSE(15,plot_term,:),1,[]),'o-','color','#3C59AB','linewidth',1.5);%%无放缩 蓝色

semilogy(SNR_dB_range, reshape( fRMSE(2,plot_term,:),1,[]),'^-r','linewidth',1.5); %%提出 红色
semilogy(SNR_dB_range, reshape( fRMSE(8,plot_term,:),1,[]),'s-r','linewidth',1.5); %%提出 红色
semilogy(SNR_dB_range, reshape( fRMSE(14,plot_term,:),1,[]),'o-r','linewidth',1.5); %%提出 红色


vir1 = semilogy(SNR_dB_range,zeros(1,length(SNR_dB_range)),'-.k','linewidth',1.5);
vir2 = semilogy(SNR_dB_range,zeros(1,length(SNR_dB_range)),'--','color','#096C28','linewidth',1.5); %%[28]绿色
vir3 = semilogy(SNR_dB_range,zeros(1,length(SNR_dB_range)),':','color','#7D2E8D','linewidth',1.5);%%[29]紫色
vir4 = semilogy(SNR_dB_range,zeros(1,length(SNR_dB_range)),'-','color','#3C59AB','linewidth',1.5);%%无放缩 蓝色
vir5 = semilogy(SNR_dB_range,zeros(1,length(SNR_dB_range)),'-r','linewidth',1.5); %%提出 红色
vir6 = semilogy(SNR_dB_range,zeros(1,length(SNR_dB_range)),'^','color','k','linewidth',1.5);
vir7 = semilogy(SNR_dB_range,zeros(1,length(SNR_dB_range)),'s','color','k','linewidth',1.5);
vir8 = semilogy(SNR_dB_range,zeros(1,length(SNR_dB_range)),'o','color','k','linewidth',1.5);
legend([vir1,vir2,vir3,vir4,vir5,vir6,vir7,vir8],{'3D-DFT, LFMCW','Successive [28]','Successive [29]','W/o scal.','Proposed','{\itL=16}','{\itL=64}','{\itL=256}'});

xlabel('SNR (dB)');
ylabel('RMSE of velocity estimation (m/s)');
grid on;

