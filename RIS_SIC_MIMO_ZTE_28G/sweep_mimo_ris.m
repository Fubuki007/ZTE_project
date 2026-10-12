function sweep_mimo_ris()
%SWEEP_MIMO_RIS  企业 28 GHz MIMO 配置下 RIS 尺寸/几何的快速扫描
%
% 目的: 找到在 28 GHz、16发64收配置下，什么 N_ris / 几何能让
% 单位模 RIS 相位优化真正有效。

root=fileparts(mfilename('fullpath'));
addpath(root); addpath(fullfile(root,'..')); addpath(fullfile(root,'..','RIS_SIC_Wu2024_验证'));
rng(20240920,'twister');

base=zte_ris_mimo_params();
base.M=32;                         % 快速扫描用 32 个子载波
base.rcg.n_restarts=4;
base.rcg.max_iter=800;

% 生成一次 W，几何变化不影响 W
p_tx=base; p_tx.N=base.M; p_tx.K=8; p_tx.K_stream=1; p_tx.precoder_type='zf';
p_tx.user_theta_rad=deg2rad(base.theta_true(1)); p_tx.user_phi_rad=deg2rad(base.phi_true(1));
if isfield(p_tx,'H_SI'), p_tx=rmfield(p_tx,'H_SI'); end
if isfield(p_tx,'H_SI_per_cc'), p_tx=rmfield(p_tx,'H_SI_per_cc'); end
tx=generate_mimo_ofdm_waveform(p_tx);
W=tx.W;

N_list = [64, 144, 256];
geo_list = [0.3 0.3; 0.5 0.5; 1.0 1.0; 1.5 1.5];  % [d_sep_wl, x_c_wl]

rows = [];
fprintf('d_sep_wl x_c_wl N_ris  max_ris_dB  RCG_supp_dB  ideal_ratio_dB\n');
fprintf('%s\n', repmat('-',1,72));

for g = 1:size(geo_list,1)
    d_sep_wl = geo_list(g,1);
    x_c_wl   = geo_list(g,2);
    for N = N_list
        p = base;
        p.d_sep_wl = d_sep_wl;
        p.x_c_wl = x_c_wl;
        p.d_sep = p.d_sep_wl * p.lambda;
        p.x_c   = p.x_c_wl   * p.lambda;
        p.N_ris = N;
        p.Nx_ris = round(sqrt(N));
        p.Ny_ris = round(sqrt(N));
        if p.Nx_ris*p.Ny_ris ~= N
            continue;
        end

        ch = generate_ris_mimo_channels(p);
        [a, h_r, info] = build_mimo_ris_objective(ch, W);
        Q = numel(a);
        direct_pow = mean(abs(a).^2);
        max_ris_pow = mean(sum(abs(info.B_all),1).^2);
        ratio_db = 10*log10(direct_pow/max(max_ris_pow,eps));

        [phi_rcg, ~] = rcg_phase_optimize(a, h_r, ones(Q,1), p);
        met = eval_mimo_sic(a, h_r, phi_rcg);

        fprintf('%8.2f %6.2f %5d %10.2f %12.2f %15.2f\n', ...
            d_sep_wl, x_c_wl, N, 10*log10(direct_pow/max_ris_pow), ...
            met.suppression_db, ratio_db);
        rows = [rows; d_sep_wl, x_c_wl, N, ratio_db, met.suppression_db]; %#ok<AGROW>
    end
end

T = array2table(rows, 'VariableNames', ...
    {'d_sep_wl','x_c_wl','N_ris','max_ris_ratio_dB','RCG_supp_dB'});
writetable(T, fullfile(root,'zte_ris_mimo_sweep.csv'));
fprintf('\n扫描结果已写入 zte_ris_mimo_sweep.csv\n');
end

