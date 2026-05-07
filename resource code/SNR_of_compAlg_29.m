function [SNRo]=SNR_of_compAlg_29(para,tpara,D_r)
%%This function is used to calculate the analyzed/numerical output-SNR of
%%the method of [29]
%%Note: 由于[29]是一种连续分开估计的方法，输出SNR主要由第一步所决定，故该程序仅计算了第一步后的输出SNR

%input:
%%D_r: Received echo cube;
%output:
%SNRo: numerical output-SNR; 
%--------------------------------------------------------------------------

%Step1: spatial DFT processing
A=fft( D_r,tpara.N_fft_a,1);
A=fftshift(A,1);
A1=abs( reshape( A(:,1,1),[],1 ) );
SNRo=max(A1)^2/ (para.Nr*para.sigma_s^2);

end