function [SNR]=SNR_of_LFMCW(H,para,tpara,SNRr)


W_zf_norm=zeros( para.Nt , para.K );

W_zf_norm(:,:)=H(:,:,floor(para.Ns/2))/(H(:,:,floor(para.Ns/2))'*H(:,:,floor(para.Ns/2)));
W_zf_norm(:,:)=1/norm(sum(W_zf_norm(:,:), 2),'fro')*W_zf_norm(:,:);

%%Chirp 信号参数
slope=para.Ns*para.delta_f/para.T_s_cp;
%%无ISI的混频采样信号
Y=zeros(para.Nr,para.Ns,para.L);
t1=para.T_cp+(0:1:para.Ns-1)*para.T_s_cp/para.Ns;
for l=1:para.L
    for i_t=1:tpara.N
        t2=(l-1)*para.T_s_cp*ones(1,para.Ns);
        b=exp(1i*2*pi*((0:1:para.Nt-1).')*para.dt*sin(tpara.thelta_rad(i_t))*(para.fc)/para.c);
        a=exp(1i*2*pi*((0:1:para.Nr-1).')*para.dr*sin(tpara.thelta_rad(i_t))*(para.fc)/para.c);
        mix_part=exp(1i*2*pi*( (2*tpara.v(i_t)*para.fc/para.c)*t2+slope*t1*2*tpara.R(i_t)/para.c  )  )  ;
        y=a*b'*W_zf_norm*ones(tpara.N,1)*mix_part;
        Y(:,:,l)= Y(:,:,l)+y;
    end
end
%%3D-FFT分析
Noise=(randn(para.Nr,para.Ns,para.L)+1i*randn(para.Nr,para.Ns,para.L))/sqrt(2)*para.sigma_s;
Y=Y+Noise;

Y=fft(Y,tpara.N_fft_a,1);
Y=fftshift(Y,1);
Y=fft(Y,tpara.N_fft_d,2);
Y=fft(Y,tpara.N_fft_v,3);
Y=fftshift(Y,3);
Y=abs(Y);
if tpara.N==1
    SNRr1=(b'*W_zf_norm*ones(tpara.N,1))^2/(para.sigma_s^2);
else
    SNRr1=1;
end
[imag_peak,~]=max(Y,[],'all'); 
SNR=  SNRr/SNRr1*imag_peak^2/ (para.Nr*para.Ns*para.L*para.sigma_s^2);

end