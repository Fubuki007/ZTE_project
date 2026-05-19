clear
clc
close all

rng(0)
M = 36; % Transmit antenna
K = 4;  % User number
N = 36; % Receive antenna

D = eye(K);

%%% Communication channel
Hk = 1/sqrt(2)*(randn(M,K)+1j*randn(M,K)); 

%%% Interference Channel ZF预编码
% Hint = 100*ULA(N,-65)*ULA(M,65)'; 
% Hint = 100*1/sqrt(2)*(randn(N,M)+1j*randn(N,M)); 
kap=1e10;
Hint = 10* (sqrt(kap/(1+kap))*ULA(N,-65)*ULA(M,65)'+sqrt(1/(1+kap))*1/sqrt(2)*(randn(N,M)+1j*randn(N,M)));

W0 = Hk/(Hk'*Hk); W0 = 1/norm(W0,'fro')*W0;
Hk'*W0;
int0 = norm(Hint*W0,'fro')^2;
%%拉格朗日
Nc = null(Hk');
W1 = W0-Nc*pinv(Hint*Nc)*Hint*W0; W1 = 1/norm(W1,'fro')*W1;
Hk'*W1;
int1 =  norm(Hint*W1,'fro')^2;
%%零空间法
R = Hint'*Hint;
W2 = R^(-1)*Hk*(Hk'*R^(-1)*Hk)^(-1); W2 = 1/norm(W2,'fro')*W2;
Hk'*W2;
int2 =  norm(Hint*W2,'fro')^2;

disp('以下记录||Hsi*W||^2')
disp(['传统ZF(未考虑干扰抑制)：',num2str(int0)])
disp(['拉格朗日法(考虑干扰抑制)：',num2str(int1)])
disp(['零空间法(考虑干扰抑制)：',num2str(int2)])

function a=ULA(M,angle)
a = 1/sqrt(M)*exp(1j*pi*sind(angle)*(0:M-1)');
end