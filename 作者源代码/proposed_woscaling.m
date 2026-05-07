function [A,sigma_n]=proposed_woscaling(para,tpara,D_r,X)
%without scaling
%input:
%%tpara: target paramters; para: system parameters;
%%D_r: echo signal; X: baseband transmit signal 
%output
%%A: 处理后最终得到的3D-angle-range-velocity cube; 
%%sigma_n: 处理过程中，噪声被放大的缩放系数


%%Step1: spatial DFT processing
A=fft(D_r,tpara.N_fft_a,1);
A=fftshift(A,1);
%%Step2: Signal-Dependent Coefficients Removing without scaling
sigma_n=zeros(tpara.N_fft_a,1);
for i=1:para.Ns
    a_all= asin( (-floor(tpara.N_fft_a/2):1:floor((tpara.N_fft_a-1)/2)).'*2*pi/tpara.N_fft_a*para.c/(2*pi*para.dr*(para.fc))   );
    B_steering=exp(1i*2*pi*(0:1:para.Nt-1).'*para.dt*sin(a_all.')*(para.fc)/para.c);
    mixed_MS=reshape( B_steering'*X(:,:,i),[tpara.N_fft_a,1,para.L]  );
    A(:,i,:)= A(:,i,:) ./mixed_MS ;
    sigma_n=sigma_n+reshape( sum( abs(1/mixed_MS).^2,[2,3]), tpara.N_fft_a,1 );
end
%%normalization of A
sigma_n=sqrt(  sigma_n *para.Nr*para.sigma_s^2  );
%%Step3: 2D-DFT in fast and slow time dimension
A=fft(A,tpara.N_fft_d,2);
A=fft(A,tpara.N_fft_v,3);
A=fftshift(A,3);
A=abs(A);

end