function [SNRa,imag_SNR]=SNR_of_my_proposed(para,tpara,D_r,X)
%%This function is used to calculate the analyzed/numerical output-SNR of
%%our proposed method

%input:
%%D_r: Received echo cube; X: baseband transmit signal
%output:
%SNRa: analyzed output-SNR; imag_SNR: numerical output-SNR; 
% runtime: execution time;
%--------------------------------------------------------------------------
A=fft(D_r,tpara.N_fft_a);
A=fftshift(A,1);

y_temp=zeros(tpara.N_fft_a,1);
sigma_n=zeros(tpara.N_fft_a,1);
for i=1:para.Ns
    a_all= asin( (-floor(tpara.N_fft_a/2):1:floor((tpara.N_fft_a)/2)-1).'*2*pi/tpara.N_fft_a*para.c/(2*pi*para.dr*(para.fc))   );
    B_steering=exp(1i*2*pi*(0:1:para.Nt-1).'*para.dt*sin(a_all.')*(para.fc)/para.c);
    y_temp=y_temp+sum(abs( A(:,i,:) ).^2, 3);
    mixed_MS=reshape( B_steering'*X(:,:,i),[tpara.N_fft_a,1,para.L]  );
    A(:,i,:)= A(:,i,:) ./mixed_MS;
    sigma_n=sigma_n+reshape( sum( abs(1/mixed_MS).^2,[2,3]), tpara.N_fft_a,1 );
end
C_scale=sqrt( sum( abs(A).^2, [2 3])./ y_temp );
sigma_n=sqrt(  sigma_n./ (C_scale.^2) *para.Nr*para.sigma_s^2  );
%%normalization of A
A=A./ repmat(C_scale,1,para.Ns,para.L);

A=fft(A,tpara.N_fft_d,2);
A=fft(A,tpara.N_fft_v,3);
A=fftshift(A,3);

A=abs(A);
[imag_peak,peak_index]=max(A,[],'all');  
index_true=zeros(1,3);
index_true(3)=ceil( peak_index/(tpara.N_fft_a*tpara.N_fft_d) );
peak_index=peak_index-(index_true(3)-1)*(tpara.N_fft_a*tpara.N_fft_d);
index_true(2)=ceil( peak_index/tpara.N_fft_a );
peak_index=peak_index-(index_true(2)-1)*tpara.N_fft_a;
index_true(1)=peak_index;

%% SNR calculation
%analytical output SNR
SNRa= para.sigma_beta^2 *para.Nr^2*para.L^2*para.Ns^2* abs( 1./C_scale(index_true(1)) )^2/sigma_n(index_true(1))^2  ;
%imag SNR
imag_SNR=  imag_peak^2/sigma_n(index_true(1))^2;

end