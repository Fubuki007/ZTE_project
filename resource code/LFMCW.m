function [Y,SNRr1]=LFMCW(H,para,tpara)
%%LFMCW
%input:
%%H: ISAC user channel matrix
%output:
%Y: obtained 3D-angle-range-Doppler cube; SNRr1: output SNR after 3D-DFT
%--------------------------------------------------------------------------
%%tranmit beamforming
W_zf_norm=zeros( para.Nt , para.K );
W_zf_norm(:,:)=H(:,:,floor(para.Ns/2))/(H(:,:,floor(para.Ns/2))'*H(:,:,floor(para.Ns/2)));
W_zf_norm(:,:)=1/norm(sum(W_zf_norm(:,:), 2),'fro')*W_zf_norm(:,:);
%% Chirp waveform generation and the related echo
slope=para.Ns*para.delta_f/para.T_s_cp;
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
%%3D-FFT processing
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

end