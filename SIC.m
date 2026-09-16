clear
clc
close all

% rng(10)
M = 36; % Transmit antenna
K = 4;  % User number
N = 36; % Receive antenna
L = 64;

target_DOA = [-30,45];
RCS = [1,0.8];

%%% pilot
pilot0 = randi([0 16-1], M, L);
S0 = qammod(pilot0, 16, 'UnitAveragePower', true);
X0 = S0;

%%% Communication channel
Hk = 1/sqrt(2)*(randn(M,K)+1j*randn(M,K)); 

%%% Interference Channel
% Hint = 100*ULA(N,-65)*ULA(M,65)'; 
Hint = 100*1/sqrt(2)*(randn(N,M)+1j*randn(N,M)); 
% kap=1e1;
% Hint = 100* (sqrt(kap/(1+kap))*ULA(N,-65)*ULA(M,65)'+sqrt(1/(1+kap))*1/sqrt(2)*(randn(N,M)+1j*randn(N,M)));

Y0=Hint*X0+1/sqrt(2)*(randn(N,L)+1j*randn(N,L)); 
Hint_hat = Y0*X0'*(X0*X0')^(-1);

norm((Hint-Hint_hat),'fro')^2/ norm(Hint, 'fro')^2

%%% data
data = randi([0 16-1], K, 1);
s = qammod(data, 16, 'UnitAveragePower', true);
Nc = null(Hk');
W0 = Hk*(Hk'*Hk)^(-1);
W1 = W0-Nc*pinv(Hint_hat*Nc)*Hint_hat*W0; W1 = 1/norm(W1,'fro')*W1;
x = W1*s;
x_no = W0*s;

noise = 1/sqrt(2)*(randn(N,1)+1j*randn(N,1));
y=noise+ Hint*x;
for t = 1:length(target_DOA)
    y = y+RCS(t)*ULA(N,target_DOA(t))*ULA(M,target_DOA(t))'*x;
end

y_clean = noise;
for t = 1:length(target_DOA)
    y_clean = y_clean+RCS(t)*ULA(N,target_DOA(t))*ULA(M,target_DOA(t))'*x;
end


y_noprocess = noise+ Hint*x_no;
for t = 1:length(target_DOA)
    y_noprocess = y_noprocess+RCS(t)*ULA(N,target_DOA(t))*ULA(M,target_DOA(t))'*x_no;
end
y_noprocess2 = noise;
for t = 1:length(target_DOA)
    y_noprocess2 = y_noprocess2+RCS(t)*ULA(N,target_DOA(t))*ULA(M,target_DOA(t))'*x_no;
end

y_SIC = y-Hint_hat*x;
norm(y-y_clean)^2
norm(y_SIC-y_clean)^2
norm(y_noprocess-y_noprocess2)^2

norm(Hint*W0*s)^2
norm(Hint*W1*s)^2
norm((Hint-Hint_hat)*W1*s)^2


function a=ULA(M,angle)
a = 1/sqrt(M)*exp(1j*pi*sind(angle)*(0:M-1)');
end