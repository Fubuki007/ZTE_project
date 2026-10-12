function out = aggregate_ris_rmse_snr_mc100
%AGGREGATE_RIS_RMSE_SNR_MC100  Merge four MC shards and create RMSE plots.

root = fileparts(mfilename('fullpath'));
if isempty(root), root = pwd; end
addpath(root);
warning('off', 'all');
n_shards = 4;
stem = 'ris_rmse_snr_mc100_shard%d.mat';
wait_log = fullfile(root, 'aggregate_ris_rmse_snr_mc100.log');
if isfile(wait_log), delete(wait_log); end
diary(wait_log); diary on;

fprintf('Waiting for %d full-size MC shards...\n', n_shards);
while true
    ready = true;
    for k = 1:n_shards
        path_k = fullfile(root, sprintf(stem,k));
        if ~isfile(path_k)
            ready = false;
            break;
        end
        try
            % Each shard owns only its mc_indices subset.  Checking the
            % entire done_mc vector would wait forever because the other
            % shard indices are intentionally false in this file.
            s = load(path_k, 'done_mc', 'mc_indices', 'n_mc_total');
            if ~isfield(s, 'done_mc') || ~isfield(s, 'mc_indices') || ...
                    ~all(s.done_mc(s.mc_indices))
                ready = false;
                break;
            end
        catch
            % A worker can be writing the MAT file while the aggregator
            % checks it; retry on the next polling interval.
            ready = false;
            break;
        end
    end
    if ready, break; end
    fprintf('[%s] shards incomplete; checking again in 60 s.\n', char(datetime('now')));
    pause(60);
end

S = load(fullfile(root, sprintf(stem,1)));
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
for k = 1:n_shards
    T = load(fullfile(root, sprintf(stem,k)), 'mc_indices', ...
        'rmse_theta','rmse_phi','rmse_R','rmse_v','detected');
    idx = T.mc_indices;
    rmse_theta(:,:,idx) = T.rmse_theta(:,:,idx);
    rmse_phi(:,:,idx) = T.rmse_phi(:,:,idx);
    rmse_R(:,:,idx) = T.rmse_R(:,:,idx);
    rmse_v(:,:,idx) = T.rmse_v(:,:,idx);
    detected(:,:,idx) = T.detected(:,:,idx);
end

% Median is the primary curve because low-SNR peak mistakes create heavy
% tails. Means are also saved for downstream analysis.
med_theta = median(rmse_theta,3,'omitnan');
med_phi = median(rmse_phi,3,'omitnan');
med_R = median(rmse_R,3,'omitnan');
med_v = median(rmse_v,3,'omitnan');
mean_theta = mean(rmse_theta,3,'omitnan');
mean_phi = mean(rmse_phi,3,'omitnan');
mean_R = mean(rmse_R,3,'omitnan');
mean_v = mean(rmse_v,3,'omitnan');
mean_detected = mean(detected,3,'omitnan');

out = struct('snr_list',snr_list,'n_mc',n_mc,'beta_si',S.beta_si, ...
    'scheme_names',{scheme_names},'rmse_theta',rmse_theta,'rmse_phi',rmse_phi, ...
    'rmse_R',rmse_R,'rmse_v',rmse_v,'detected',detected, ...
    'median_theta',med_theta,'median_phi',med_phi,'median_R',med_R, ...
    'median_v',med_v,'mean_theta',mean_theta,'mean_phi',mean_phi, ...
    'mean_R',mean_R,'mean_v',mean_v,'mean_detected',mean_detected, ...
    'timestamp',char(datetime('now','Format','yyyy-MM-dd HH:mm:ss')));
save(fullfile(root,'ris_rmse_snr_mc100_results.mat'),'-struct','out','-v7.3');

% Long-form CSV includes both elevation and azimuth angle RMSE.
fid = fopen(fullfile(root,'ris_rmse_snr_mc100_summary.csv'),'w');
fprintf(fid,'snr_dB,scheme,median_theta_deg,median_phi_deg,median_range_m,median_velocity_mps,mean_theta_deg,mean_phi_deg,mean_range_m,mean_velocity_mps,mean_detected\n');
for si = 1:n_scheme
    for ni = 1:n_snr
        fprintf(fid,'%.12g,%s,%.9g,%.9g,%.9g,%.9g,%.9g,%.9g,%.9g,%.9g,%.9g\n', ...
            snr_list(ni),scheme_names{si},med_theta(si,ni),med_phi(si,ni), ...
            med_R(si,ni),med_v(si,ni),mean_theta(si,ni),mean_phi(si,ni), ...
            mean_R(si,ni),mean_v(si,ni),mean_detected(si,ni));
    end
end
fclose(fid);

colors = lines(n_scheme);
labels = scheme_names;
fig_dir = fullfile(root,'fig');
if ~isfolder(fig_dir), mkdir(fig_dir); end

% Main three requested plots: elevation angle, range, and velocity.
make_plot(snr_list, med_theta, labels, colors, 'Elevation angle RMSE (deg)', ...
    'RIS-assisted ISAC: angle RMSE vs SNR', fullfile(fig_dir,'ris_angle_rmse_vs_snr_mc100'));
make_plot(snr_list, med_R, labels, colors, 'Range RMSE (m)', ...
    'RIS-assisted ISAC: range RMSE vs SNR', fullfile(fig_dir,'ris_range_rmse_vs_snr_mc100'));
make_plot(snr_list, med_v, labels, colors, 'Velocity RMSE (m/s)', ...
    'RIS-assisted ISAC: velocity RMSE vs SNR', fullfile(fig_dir,'ris_velocity_rmse_vs_snr_mc100'));

% One combined panel for quick acceptance.
fig = figure('Visible','off','Color','w','Position',[80 80 1500 520]);
Y = {med_theta,med_R,med_v};
ylab = {'Elevation angle RMSE (deg)','Range RMSE (m)','Velocity RMSE (m/s)'};
ttl = {'Angle','Range','Velocity'};
for pi = 1:3
    subplot(1,3,pi); hold on; grid on;
    for si = 1:n_scheme
        semilogy(snr_list,Y{pi}(si,:),'-o','LineWidth',1.5,'MarkerSize',4, ...
            'Color',colors(si,:),'DisplayName',labels{si});
    end
    xlabel('SNR (dB)'); ylabel(ylab{pi}); title(ttl{pi});
    xlim([snr_list(1),snr_list(end)]); set(gca,'YScale','log');
    if pi == 1, legend('Location','best'); end
end
sgtitle(sprintf('RIS + self-interference, beta_{SI}=%.3g, median over MC=%d', S.beta_si,n_mc));
print(fig,fullfile(fig_dir,'ris_rmse_vs_snr_mc100_all'),'-dpng','-r180');
savefig(fig,fullfile(fig_dir,'ris_rmse_vs_snr_mc100_all.fig'));
print(fig,fullfile(fig_dir,'ris_rmse_vs_snr_mc100_all'),'-depsc','-painters');
close(fig);

fprintf('AGGREGATED_RESULT=%s\n',fullfile(root,'ris_rmse_snr_mc100_results.mat'));
fprintf('CSV=%s\n',fullfile(root,'ris_rmse_snr_mc100_summary.csv'));
fprintf('Plots written under %s\n',fig_dir);
diary off;
end

function make_plot(x, Y, labels, colors, ylab, ttl, base)
fig = figure('Visible','off','Color','w','Position',[100 100 900 620]);
hold on; grid on;
for k = 1:size(Y,1)
    semilogy(x,Y(k,:),'-o','LineWidth',1.8,'MarkerSize',5, ...
        'Color',colors(k,:),'DisplayName',labels{k});
end
xlabel('SNR (dB)'); ylabel(ylab); title(ttl); legend('Location','best');
xlim([x(1),x(end)]); set(gca,'YScale','log');
set(gca,'FontName','Arial','FontSize',11);
print(fig,[base '.png'],'-dpng','-r200');
savefig(fig,[base '.fig']);
print(fig,[base '.eps'],'-depsc','-painters');
close(fig);
end
