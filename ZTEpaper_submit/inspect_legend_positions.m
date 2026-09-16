fig_dir = fullfile('..', 'fig');
fig_names = {
    'fig_angle_rmse_vs_snr_4methods_beta100_server_edited_legend_large.fig'
    'fig_velocity_rmse_vs_snr_4methods_beta100_server_edited_legend_large.fig'
    'fig_rmse_vs_snr_4methods_edited_legend_large.fig'
    };

for k = 1:numel(fig_names)
    fig_path = fullfile(fig_dir, fig_names{k});
    f = openfig(fig_path, 'invisible');
    ax = findobj(f, 'Type', 'axes');
    lg = findobj(f, 'Type', 'legend');
    fprintf('\n%s\n', fig_names{k});
    fprintf('figure Position [%g %g %g %g], Units %s\n', f.Position, f.Units);
    for a = 1:numel(ax)
        fprintf('axes Position [%g %g %g %g], Units %s\n', ax(a).Position, ax(a).Units);
    end
    for j = 1:numel(lg)
        fprintf('legend Position [%g %g %g %g], Units %s, Location %s\n', ...
            lg(j).Position, lg(j).Units, lg(j).Location);
    end
    close(f);
end
