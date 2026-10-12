function run_subband_mimo_ris()
%RUN_SUBBAND_MIMO_RIS  企业 28 GHz MIMO 下子带 RIS 相位验证
%
% 论文假设所有子载波共用同一个 phi。1.52 GHz 带宽下这个假设可能太强。
% 这里把子载波分成 G 组，每组独立优化一个 phi_g，看带宽分段能带来多大提升。

root=fileparts(mfilename('fullpath'));
addpath(root); addpath(fullfile(root,'..')); addpath(fullfile(root,'..','RIS_SIC_Wu2024_验证'));
rng(20240920,'twister');

p=zte_ris_mimo_params();
p.N_ris=144; p.Nx_ris=12; p.Ny_ris=12;
p.d_sep_wl=1.5; p.x_c_wl=1.5;
p.d_sep=p.d_sep_wl*p.lambda; p.x_c=p.x_c_wl*p.lambda;
p.M=64; p.rcg.n_restarts=2; p.rcg.max_iter=300;

ch=generate_ris_mimo_channels(p);
p_tx=p; p_tx.N=p.M; p_tx.K=8; p_tx.K_stream=1; p_tx.precoder_type='zf';
p_tx.user_theta_rad=deg2rad(p.theta_true(1)); p_tx.user_phi_rad=deg2rad(p.phi_true(1));
if isfield(p_tx,'H_SI'), p_tx=rmfield(p_tx,'H_SI'); end
if isfield(p_tx,'H_SI_per_cc'), p_tx=rmfield(p_tx,'H_SI_per_cc'); end
tx=generate_mimo_ofdm_waveform(p_tx);
W=tx.W;
[a,h_r,info]=build_mimo_ris_objective(ch,W);
B=info.B_all; M=p.M; Nr=ch.Nr; K=size(W,2);

% 每个子载波的 observation 索引: q = (m-1)*Nr*K + (k-1)*Nr + (1:Nr)
idx_m = cell(M,1);
for m=1:M
    idx_m{m} = (m-1)*Nr*K + (1:Nr*K);
end

G_list=[1,2,4,8,16,32,64];
supp=zeros(numel(G_list),1);
for gi=1:numel(G_list)
    G=G_list(gi);
    groups=cell(G,1);
    for g=1:G
        groups{g}=find(mod((0:M-1),G)==(g-1));
    end
    direct_tot=0; resid_tot=0;
    for g=1:G
        qidx=[];
        for mm=groups{g}
            qidx=[qidx, idx_m{mm}]; %#ok<AGROW>
        end
        w=zeros(numel(a),1); w(qidx)=1;
        [phi_g,~]=rcg_phase_optimize(a,h_r,w,p);
        r=a(qidx)+B(:,qidx).'*phi_g;
        direct_tot=direct_tot+sum(abs(a(qidx)).^2);
        resid_tot=resid_tot+sum(abs(r).^2);
    end
    supp(gi)=10*log10(direct_tot/max(resid_tot,eps));
    fprintf('G=%3d subbands, suppression=%.2f dB\n',G,supp(gi));
end
T=table(G_list(:),supp,'VariableNames',{'num_subbands','suppression_dB'});
writetable(T,fullfile(root,'zte_ris_mimo_subband.csv'));
fprintf('\n子带结果已写入 zte_ris_mimo_subband.csv\n');
end

