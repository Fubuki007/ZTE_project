function [estimated_adv,SNRo]=compAlg_28(para,tpara,D_r,X,true_adv)
%This function is used to perform the algorithm of [28] and obtain its
%estimation result

%input:
%%D_r: Received echo cube; X: baseband transmit signal; true_adv: ground
%%true target parameters
%output:
%estimated_adv: estimation result; SNRo: out-put SNR
%--------------------------------------------------------------------------
if (tpara.N<para.Nr)
    estimated_adv=zeros(tpara.N,3);
    %%step1 angle estimation
    %先算协方差矩阵求角度
    Ry=zeros(para.Nr,para.Nr);
    for i=1:para.Ns
        for l=1:para.L
            Ry=Ry+ reshape( ( D_r(:,i,l) ),[],1 )*reshape( ( D_r(:,i,l) ),[],1 )';
        end
    end
    Ry=Ry/(para.Ns*para.L);


    k = 2*pi*para.fc/para.c;        % 波数
    N = para.Nr;                    % 阵元数量
    d = para.dr;                    % 阵元间隔
    z = (0:d:(N-1)*d)';             % 阵元坐标分布
    %%% 信号源参数
    M = tpara.N;                    % 信号源数目

    [EV, D] = eig(Ry);              % 特征值分解
    EVA = diag(D);                  % 提取特征值
    [EVA, I] = sort(EVA, 'descend');   % 降序排序
    SNRo=EVA(1)^2/sum(EVA(2:end).^2)*(N-1);

    Q = EV(:, I);           % 特征向量构成的矩阵
    Q_n = Q(:, M+1:N);      % 噪声子空间
    %%% 计算MUSIC谱估计函数
    phi_list= asin( (-floor(tpara.N_fft_a/2):1:floor(tpara.N_fft_a/2)-1).'*2*pi/tpara.N_fft_a*para.c/(2*pi*para.dr*(para.fc ))   );
    S1 = exp(1j*k*z*sin(phi_list'));       % 不同方向对应的流型矢量构成矩阵
    if N-M >1
        P_MUSIC = 1./sum(abs(Q_n'*S1).^2); % MUSIC 谱估计公式
    else
        P_MUSIC = 1./abs(Q_n'*S1).^2;      % MUSIC 谱估计公式
    end
    %%% 转换为dB
    P_MUSIC = abs(P_MUSIC);
    P_MUSIC_max = max(P_MUSIC);
    P_MUSIC_dB = 10*log10(P_MUSIC/P_MUSIC_max);
    if tpara.N==1
        [~,P_peaks_idx]=max(P_MUSIC_dB);
    else
        %%% 提取信号源方向
        [P_peaks, P_peaks_idx] = findpeaks(P_MUSIC_dB);     % 提取峰值
        [P_peaks, I] = sort(P_peaks, 'descend');    % 峰值降序排序
        P_peaks_idx = P_peaks_idx(I);
        P_peaks = P_peaks(1:M);             % 提取前M个
        P_peaks_idx = P_peaks_idx(1:M);
    end
    
    phi_e = phi_list(P_peaks_idx)*180/pi.';   % 估计方向
    estimated_adv(:,1)=phi_e;
    %%step 2 and 3
    d_all= para.c* (0:1:tpara.N_fft_d-1).'*2*pi/tpara.N_fft_d /(4*pi*para.delta_f) ;
    v_all= para.c* (-floor(tpara.N_fft_v/2):1:floor((tpara.N_fft_v-1)/2)).' *2*pi/tpara.N_fft_v/(4*pi*para.T_s_cp*para.fc);
    for i_na=1:tpara.N
        A=zeros(1,para.Ns,para.L);
        for i=1:para.Ns
            a_part=phi_e(i_na)/180*pi;
            B_steering=exp(1i*2*pi*(0:1:para.Nt-1).'*para.dt*sin(a_part.')*(para.fc)/para.c);
            A_steering=exp(1i*2*pi*((0:1:para.Nr-1).')*para.dr*sin(a_part.')*(para.fc)/para.c);
            mix_temp=reshape(A_steering*B_steering'*X(:,:,i),[para.Nr,1,para.L]);
            A(:,i,:)= sum( D_r(:,i,:) ./mix_temp,1 )/para.Nr;
        end
        A=fft(A,tpara.N_fft_d,2);
        A=fft(A,tpara.N_fft_v,3);
        A=fftshift(A,3);
        A=reshape(A,[tpara.N_fft_d,tpara.N_fft_v]);
        %%找峰值
        index_joint=zeros(1,2);
        [~,peak_index]=max(abs(A),[],'all');  
        index_joint(2)=ceil( peak_index/tpara.N_fft_d );
        peak_index=peak_index-(index_joint(2)-1)*tpara.N_fft_d;
        index_joint(1)=peak_index;
        estimated_adv(i_na,2)=d_all(index_joint(1));
        estimated_adv(i_na,3)=v_all(index_joint(2)) ;
    end

    if tpara.N>1
        estimated_adv_temp=estimated_adv;
        n_count=0;
        while n_count < tpara.N
            %%把找出来的峰值index按照每个目标重新排序
            n_count=n_count+1;
            [~,indx]=min( abs(true_adv(n_count,1)-estimated_adv_temp(:,1)) );
            estimated_adv(n_count,:)=estimated_adv_temp(indx,:);
            estimated_adv_temp(indx,:)=[];
        end
    end

else
    estimated_adv=zeros(tpara.N,3);
    SNRo=0;
end

end