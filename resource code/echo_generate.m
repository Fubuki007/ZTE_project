function [D_r,SNRr]=echo_generate(tpara,para,W,X)
%noise-free echo generation 
%input
%%tpara: target paramters; para: system parameters; W: precoding matrix 
%%X: baseband transmit signal 
%output
%%D_r: noise-free echo signal; SNRr: SNR of echo 
%Note:为了方便后续index的查找，该回波建模中的角度和距离角频率都多取了一个负号，后续估计代码中的angle/distance
%%该输出均为未考虑信道衰减和RCS的，这些外面SNR变化的时候再加
%%该echo未添加噪声，噪声将在外层改变SNR时添加
%%-------------------------------------------------------------------------
SNRr_fenzi=0;
%%received echo from targets after DFT (frequency domain)
D_r=zeros(para.Nr,para.Ns,para.L);
phase_shift_D=exp(1i*2*pi*para.T_s_cp* (2*tpara.v*para.fc/para.c)*(0:1:para.L-1));
for i=1:para.Ns
    B_steering=exp(1i*2*pi*((0:1:para.Nt-1).')*para.dt*sin(tpara.thelta_rad.')*(para.fc)/para.c);
    A_steering=exp(1i*2*pi*((0:1:para.Nr-1).')*para.dr*sin(tpara.thelta_rad.')*(para.fc)/para.c);
    Rl=tpara.R+0*tpara.v*[0:1:para.L-1]*para.T_s_cp;
    phase_shift_R=exp(1i*2*pi*(i-1)*para.delta_f*2*(Rl)/para.c );
    temp= reshape( A_steering*(B_steering'*X(:,:,i).*(phase_shift_R.*phase_shift_D )),[para.Nr,1,para.L]  );
    D_r(:,i,:)= temp;
    if tpara.N==1
        SNRr_fenzi=SNRr_fenzi+B_steering'*W(:,:,i)*W(:,:,i)'*B_steering;
    end
end
%%received SNR
if tpara.N==1
    SNRr= SNRr_fenzi / (para.Ns*para.sigma_s^2);
else
    SNRr=1;
end
end