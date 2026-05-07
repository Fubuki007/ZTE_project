function [SNRo]=SNR_of_compAlg_28(para,tpara,D_r)
%%This function is used to calculate the analyzed/numerical output-SNR of
%%the method of [28]
%%Note: 由于[28]是一种连续分开估计的方法，输出SNR主要由第一步所决定，故该程序仅计算了第一步后的输出SNR

%input:
%%D_r: Received echo cube;
%output:
%SNRo: numerical output-SNR; 
%--------------------------------------------------------------------------
%%step1 angle estimation
%先算协方差矩阵求角度
Ry=zeros(para.Nr,para.Nr);
for i=1:para.Ns
    for l=1:para.L
        Ry=Ry+ reshape( ( D_r(:,i,l) ),[],1 )*reshape( ( D_r(:,i,l) ),[],1 )';
    end
end
Ry=Ry/(para.Ns*para.L);


k = 2*pi*para.fc/para.c;    % 波数
N = para.Nr;                 % 阵元数量
d = para.dr;         % 阵元间隔 
z = (0:d:(N-1)*d)';     % 阵元坐标分布
%%% 信号源参数
M = tpara.N;                % 信号源数目

[EV, D] = eig(Ry);       % 特征值分解
EVA = diag(D);          % 提取特征值
[EVA, I] = sort(EVA, 'descend');   % 降序排序
SNRo=EVA(1)^2/sum(EVA(2:end).^2)*(N-1);


end