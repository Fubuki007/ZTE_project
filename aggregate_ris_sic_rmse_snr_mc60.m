function out = aggregate_ris_sic_rmse_snr_mc60
% Merge validated per-case checkpoints only after every case has completed.
root = fileparts(mfilename('fullpath'));
if isempty(root), root = pwd; end
addpath(root);
[config, result_prefix] = ris_sic_run_config;
n_mc = config.n_mc_total;
sample_dir = fullfile(root,[result_prefix '_samples']);
wait_log = fullfile(root, [result_prefix '_aggregate.log']);
diary(wait_log); diary on;
diary_cleanup = onCleanup(@() diary('off')); %#ok<NASGU>

fprintf('Waiting for %d paired SIC samples...\n', n_mc);
wait_started = tic;
wait_seconds = env_num('RIS_AGGREGATE_TIMEOUT_SECONDS', 43200);
while true
    missing = zeros(1,0);
    saved_cases = 0;
    for mc = 1:n_mc
        path_k = fullfile(sample_dir, sprintf('mc_%05d.mat',mc));
        [T, valid, reason] = ris_sic_load_sample(path_k,config,mc);
        if ~valid && isfile(path_k)
            error('RIS:InvalidCheckpoint','Checkpoint %s rejected: %s',path_k,reason);
        end
        if valid, saved_cases = saved_cases + nnz(T.completed); end
        if ~valid || ~all(T.completed(:)), missing(end+1) = mc; end %#ok<AGROW>
    end
    if isempty(missing), break; end
    if toc(wait_started) >= wait_seconds
        error('Aggregate wait timed out after %.0f s; missing MC indices: %s', ...
            wait_seconds, mat2str(missing));
    end
    fprintf('[%s] %d/%d MC complete, %d/%d cases saved; unfinished: %s; retry in 30 s.\n', ...
        char(datetime('now')), n_mc-numel(missing), n_mc, saved_cases, ...
        n_mc*6*numel(config.snr_list),mat2str(missing));
    pause(30);
end

[first_sample, valid] = ris_sic_load_sample(fullfile(sample_dir,'mc_00001.mat'),config,1);
assert(valid,'Invalid first sample.');
config = first_sample.config;
S = struct('snr_list',config.snr_list,'beta_si',config.beta_si, ...
    'n_mc_total',config.n_mc_total,'sic_pilot_len',128, ...
    'sic_mode','pilot LS with thermal AWGN, no genie channel');
S.scheme_names = {'No RIS (SIC off)', 'RIS continuous (SIC off)', ...
    'RIS tau=4 (SIC off)', 'No RIS (SIC on)', ...
    'RIS continuous (SIC on)', 'RIS tau=4 (SIC on)'};
snr_list = S.snr_list;
scheme_names = S.scheme_names;
n_scheme = numel(scheme_names);
n_snr = numel(snr_list);
n_mc = S.n_mc_total;
rmse_theta = NaN(n_scheme,n_snr,n_mc);
rmse_phi = NaN(n_scheme,n_snr,n_mc);
rmse_R = NaN(n_scheme,n_snr,n_mc);
rmse_v = NaN(n_scheme,n_snr,n_mc);
detected = NaN(n_scheme,n_snr,n_mc);
sic_suppression_db = NaN(n_scheme,n_snr,n_mc);
for mc = 1:n_mc
    sample_path = fullfile(sample_dir, sprintf('mc_%05d.mat',mc));
    [T, valid, reason] = ris_sic_load_sample(sample_path,config,mc);
    assert(valid && all(T.completed(:)), 'Invalid MC=%d: %s',mc,reason);
    rmse_theta(:,:,mc) = T.rmse_theta;
    rmse_phi(:,:,mc) = T.rmse_phi;
    rmse_R(:,:,mc) = T.rmse_R;
    rmse_v(:,:,mc) = T.rmse_v;
    detected(:,:,mc) = T.detected;
    sic_suppression_db(:,:,mc) = T.sic_suppression_db;
end

med_theta = median(rmse_theta,3,'omitnan');
med_phi = median(rmse_phi,3,'omitnan');
med_R = median(rmse_R,3,'omitnan');
med_v = median(rmse_v,3,'omitnan');
mean_theta = mean(rmse_theta,3,'omitnan');
mean_phi = mean(rmse_phi,3,'omitnan');
mean_R = mean(rmse_R,3,'omitnan');
mean_v = mean(rmse_v,3,'omitnan');
mean_detected = mean(detected,3,'omitnan');
med_sic = median(sic_suppression_db,3,'omitnan');
mean_sic = mean(sic_suppression_db,3,'omitnan');

out = struct('snr_list',snr_list,'n_mc',n_mc,'beta_si',S.beta_si, ...
    'scheme_names',{scheme_names},'sic_mode',S.sic_mode, ...
    'sic_pilot_len',S.sic_pilot_len,'rmse_theta',rmse_theta, ...
    'rmse_phi',rmse_phi,'rmse_R',rmse_R,'rmse_v',rmse_v, ...
    'detected',detected,'sic_suppression_db',sic_suppression_db, ...
    'median_theta',med_theta,'median_phi',med_phi,'median_R',med_R, ...
    'median_v',med_v,'mean_theta',mean_theta,'mean_phi',mean_phi, ...
    'mean_R',mean_R,'mean_v',mean_v,'mean_detected',mean_detected, ...
    'median_sic_suppression_db',med_sic, ...
    'mean_sic_suppression_db',mean_sic, ...
    'timestamp',char(datetime('now','Format','yyyy-MM-dd HH:mm:ss')));
out.config = config;
ris_sic_save_atomic(fullfile(root,[result_prefix '_results.mat']),out);

csv_path = fullfile(root,[result_prefix '_summary.csv']);
fid = fopen(csv_path,'w');
assert(fid >= 0,'Unable to write CSV.');
fprintf(fid,['snr_dB,scheme,median_theta_deg,median_phi_deg,median_range_m,' ...
    'median_velocity_mps,mean_theta_deg,mean_phi_deg,mean_range_m,' ...
    'mean_velocity_mps,mean_detected,median_sic_suppression_db,' ...
    'mean_sic_suppression_db\n']);
for si = 1:n_scheme
    for ni = 1:n_snr
        fprintf(fid,'%.12g,%s,%.9g,%.9g,%.9g,%.9g,%.9g,%.9g,%.9g,%.9g,%.9g,%.9g,%.9g\n', ...
            snr_list(ni),scheme_names{si},med_theta(si,ni),med_phi(si,ni), ...
            med_R(si,ni),med_v(si,ni),mean_theta(si,ni),mean_phi(si,ni), ...
            mean_R(si,ni),mean_v(si,ni),mean_detected(si,ni), ...
            med_sic(si,ni),mean_sic(si,ni));
    end
end
fclose(fid);

colors = lines(n_scheme);
fig_dir = fullfile(root,'fig');
if ~isfolder(fig_dir), mkdir(fig_dir); end
make_plot(snr_list, med_theta, scheme_names, colors, ...
    'Elevation angle RMSE (deg)', ...
    sprintf('RIS + SIC: angle RMSE vs SNR (paired MC=%d)', n_mc), ...
    fullfile(fig_dir,[result_prefix '_angle_rmse_vs_snr']));
make_plot(snr_list, med_R, scheme_names, colors, ...
    'Range RMSE (m)', ...
    sprintf('RIS + SIC: range RMSE vs SNR (paired MC=%d)', n_mc), ...
    fullfile(fig_dir,[result_prefix '_range_rmse_vs_snr']));
make_plot(snr_list, med_v, scheme_names, colors, ...
    'Velocity RMSE (m/s)', ...
    sprintf('RIS + SIC: velocity RMSE vs SNR (paired MC=%d)', n_mc), ...
    fullfile(fig_dir,[result_prefix '_velocity_rmse_vs_snr']));

fig = figure('Visible','off','Color','w','Position',[80 80 1550 520]);
Y = {med_theta,med_R,med_v};
ylab = {'Elevation angle RMSE (deg)','Range RMSE (m)','Velocity RMSE (m/s)'};
ttl = {'Angle','Range','Velocity'};
for pi = 1:3
    subplot(1,3,pi); hold on; grid on;
    for si = 1:n_scheme
        semilogy(snr_list,max(Y{pi}(si,:),1e-12),'-o','LineWidth',1.3, ...
            'MarkerSize',4,'Color',colors(si,:),'DisplayName',scheme_names{si});
    end
    xlabel('SNR (dB)'); ylabel(ylab{pi}); title(ttl{pi});
    if numel(snr_list)>1, xlim([snr_list(1),snr_list(end)]); end
    set(gca,'YScale','log');
    if pi == 1, legend('Location','best'); end
end
sgtitle(sprintf('RIS + matrix self-interference + pilot-LS SIC, beta_{SI}=%.3g, MC=%d', ...
    S.beta_si,n_mc));
print(fig,fullfile(fig_dir,[result_prefix '_all']),'-dpng','-r180');
savefig(fig,fullfile(fig_dir,[result_prefix '_all.fig']));
print(fig,fullfile(fig_dir,[result_prefix '_all']),'-depsc','-painters');
close(fig);

fprintf('AGGREGATED_RESULT=%s\n',fullfile(root,[result_prefix '_results.mat']));
fprintf('CSV=%s\n',csv_path);
fprintf('Plots written under %s\n',fig_dir);
diary off;
end

function make_plot(x,Y,labels,colors,ylab,ttl,base)
fig = figure('Visible','off','Color','w','Position',[100 100 1050 660]);
hold on; grid on;
for k = 1:size(Y,1)
    semilogy(x,max(Y(k,:),1e-12),'-o','LineWidth',1.6,'MarkerSize',5, ...
        'Color',colors(k,:),'DisplayName',labels{k});
end
xlabel('SNR (dB)'); ylabel(ylab); title(ttl);
legend('Location','best');
if numel(x)>1, xlim([x(1),x(end)]); end
set(gca,'YScale','log');
set(gca,'FontName','Arial','FontSize',11);
print(fig,[base '.png'],'-dpng','-r200');
savefig(fig,[base '.fig']);
print(fig,[base '.eps'],'-depsc','-painters');
close(fig);
end

function value = env_num(name, default_value)
raw = getenv(name);
if isempty(raw)
    value = default_value;
else
    value = round(str2double(raw));
    if ~isfinite(value) || value < 1, value = default_value; end
end
end


