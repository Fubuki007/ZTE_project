function export_ris_report_evidence
% Read completed results only; no simulation or parameter changes.
root = fileparts(fileparts(mfilename('fullpath')));
dest = fullfile(root, 'server-results', 'ris_report_20261010');
if ~isfolder(dest), mkdir(dest); end
e = struct();
A = load(fullfile(root, 'ris_isac_no_interference_results.mat'), 'mode', 'params', 'timestamp');
e.no_si = compact(A);
B = load(fullfile(root, 'ris_isac_si_mc_smoke_results.mat'), 'mode', 'n_mc', 'beta_list', 'params', 'timestamp');
e.smoke_si = compact(B);
files = {fullfile(root,'server-results','ris_rmse_snr_mc100','ris_rmse_snr_mc100_results.mat'), ...
    fullfile(root,'server-results','ris_sic_mc60_final','ris_sic_rmse_snr_mc60_resume_v3_double_results.mat')};
labels = {'mc100','mc60'};
fid = fopen(fullfile(dest,'recomputed_rms_across_mc.csv'),'w');
assert(fid>=0);
cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
fprintf(fid,'experiment,snr_dB,scheme,rms_theta_deg,rms_phi_deg,rms_range_m,rms_velocity_mps,valid_MC,min_detected,max_detected\n');
for n = 1:numel(files)
    S = load(files{n});
    info = struct();
    keys = {'timestamp','n_mc','beta_si','sic_mode','sic_pilot_len','snr_list','scheme_names'};
    for k=1:numel(keys)
        if isfield(S,keys{k}), info.(keys{k})=S.(keys{k}); end
    end
    if isfield(S,'config'), info.config = S.config; end
    info.raw_rmse_shape=size(S.rmse_theta);
    info.finite_theta_count=nnz(isfinite(S.rmse_theta));
    info.min_detected=min(S.detected(:));
    info.max_detected=max(S.detected(:));
    e.(labels{n})=info;
    for si=1:numel(S.scheme_names)
        for ni=1:numel(S.snr_list)
            fields={'rmse_theta','rmse_phi','rmse_R','rmse_v'};
            values=zeros(1,4);
            for k=1:4
                x=reshape(S.(fields{k})(si,ni,:),[],1);
                assert(all(isfinite(x)), 'Incomplete raw RMSE data.');
                values(k)=sqrt(mean(x.^2));
            end
            count=nnz(isfinite(S.rmse_theta(si,ni,:)));
            d=reshape(S.detected(si,ni,:),[],1);
            fprintf(fid,'%s,%.12g,%s,%.12g,%.12g,%.12g,%.12g,%d,%g,%g\n', ...
                labels{n},S.snr_list(ni),S.scheme_names{si},values,count,min(d),max(d));
        end
    end
end
fid2=fopen(fullfile(dest,'completed_experiment_metadata.json'),'w');
assert(fid2>=0);
fwrite(fid2,jsonencode(e,'PrettyPrint',true),'char');
fclose(fid2);
fprintf('REPORT_EVIDENCE_EXPORTED=%s\n',dest);
disp(e.no_si); disp(e.smoke_si);
end

function out=compact(S)
out=S;
out=rmfield(out,'params');
keys={'fc','B','N','K','Ntx','Nty','Mx','My','SNR','enable_SI','enable_SIC','beta_SI', ...
    'K_stream','theta_true','phi_true','R_true','v_true','alpha','ris'};
for k=1:numel(keys)
    if isfield(S.params,keys{k}), out.(keys{k})=S.params.(keys{k}); end
end
end
