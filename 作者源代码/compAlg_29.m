function [estimated_adv]=compAlg_29(para,tpara,D_r,X)
%This function is used to perform the algorithm of [29] and obtain its
%estimation result

%input:
%%D_r: Received echo cube; X: baseband transmit signal
%output:
%estimated_adv: estimation result
%--------------------------------------------------------------------------
a_all= asin( (-floor(tpara.N_fft_a/2):1:floor((tpara.N_fft_a-1)/2)).'*2*pi/tpara.N_fft_a*para.c/(2*pi*para.dr*(para.fc))   );
d_all= para.c* (0:1:tpara.N_fft_d-1).'*2*pi/tpara.N_fft_d /(4*pi*para.delta_f) ;
v_all= para.c* (-floor(tpara.N_fft_v/2):1:floor((tpara.N_fft_v-1)/2)).' *2*pi/tpara.N_fft_v/(4*pi*para.T_s_cp*para.fc);
%%Step1: spatial DFT processing of one OFDM symbol
index_joint=zeros(1,3);
A=fft( D_r,tpara.N_fft_a,1);
A=fftshift(A,1);
A1=abs( reshape( A(:,1,1),[],1 ) );
[~,index_joint(1)]=max(A1);
%% step2 做互相关，找峰值
A=reshape( A(index_joint(1),:,:),[para.Ns,para.L]);
A_mao=zeros(para.Ns,para.L );
for i=1:para.Ns
    a_part=a_all(index_joint(:,1));
    B_steering=exp(1i*2*pi*(0:1:para.Nt-1).'*para.dt*sin(a_part.')*(para.fc)/para.c);
    A_mao(i,:)= B_steering'* reshape(X(:,:,i),[para.Nt,para.L]);
end
DFT_A=fft(A,tpara.N_fft_d);
DFT_A_mao=fft(A_mao,tpara.N_fft_d);

A_corr=zeros(2*tpara.N_fft_d-1,para.L);
for l=1:para.L
    A_corr(:,l)=xcorr(DFT_A_mao(:,l),DFT_A(:,l));
end
A_corr=flip(A_corr);
A_corr=A_corr(tpara.N_fft_d:end,:);
A2=abs( reshape(A_corr(:,1),[],1) );
[~,index_joint(2)]=max( A2 );
%% step3
A=A_corr(index_joint(2),:);
A=fft(A,tpara.N_fft_v);
A=fftshift(A);
A=flip(A);
A3=abs(  A );
[~,index_joint(3)]=max(A3);
if index_joint(3)+1 < tpara.N_fft_v
    index_joint(3)=index_joint(3)+1;
else
    index_joint(3)=1;
end
estimated_adv=[a_all(index_joint(:,1))/pi*180,d_all(index_joint(:,2)),v_all(index_joint(:,3))   ];
end