function [estimated_adv,index_joint]=peak_finding(Y,para,tpara)
%This function is used to find out the peak index of the obtained 3D-angle-
%%rang-Doppler cube

%input:
%%Y: 3D-angle-rang-Doppler cube
%output:
%estimated_adv: estimation result; index_joint: peak index

%% --------------- peaks finding ----------------
index_joint=zeros(1,3);
[~,peak_index]=max(Y,[],'all');  
index_joint(3)=ceil( peak_index/(tpara.N_fft_a*tpara.N_fft_d) );
peak_index=peak_index-(index_joint(3)-1)*(tpara.N_fft_a*tpara.N_fft_d);
index_joint(2)=ceil( peak_index/tpara.N_fft_a );
peak_index=peak_index-(index_joint(2)-1)*tpara.N_fft_a;
index_joint(1)=peak_index;

a_all= asin( (-floor(tpara.N_fft_a/2):1:floor(tpara.N_fft_a/2)-1).'*2*pi/tpara.N_fft_a*para.c/(2*pi*para.dr*(para.fc ))   );
d_all= para.c* (0:1:tpara.N_fft_d-1).'*2*pi/tpara.N_fft_d /(4*pi*para.delta_f) ;
v_all= para.c* (-floor(tpara.N_fft_v/2):1:floor(tpara.N_fft_v/2)-1).' *2*pi/tpara.N_fft_v/(4*pi*para.T_s_cp*para.fc);

estimated_adv=[a_all(index_joint(:,1))/pi*180,d_all(index_joint(:,2)),v_all(index_joint(:,3))   ];

end