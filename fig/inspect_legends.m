% inspect_legends.m — 探查三个 fig 的图例位置/字号与曲线分布
files = {...
 'fig_rmse_vs_snr_4methods_edited.fig', ...
 'fig_velocity_rmse_vs_snr_4methods_beta100_server_edited.fig', ...
 'fig_angle_rmse_vs_snr_4methods_beta100_server_edited.fig'};
for i = 1:numel(files)
    f = openfig(files{i}, 'invisible');
    lg = findobj(f, 'Type', 'legend');
    ax = findobj(f, 'Type', 'axes');
    ax = ax(1);
    fprintf('=== %s ===\n', files{i});
    fprintf('axes pos: %s\n', mat2str(ax.Position, 4));
    fprintf('xlim: %s  ylim: %s\n', mat2str(ax.XLim, 5), mat2str(ax.YLim, 5));
    fprintf('xscale: %s  yscale: %s\n', ax.XScale, ax.YScale);
    if ~isempty(lg)
        fprintf('legend pos: %s\n', mat2str(lg.Position, 4));
        fprintf('legend fontsize: %g\n', lg.FontSize);
        fprintf('legend location: %s\n', lg.Location);
        fprintf('legend strings: [%s]\n', strjoin(lg.String, '] ['));
    end
    lines = findobj(ax, 'Type', 'line');
    for k = 1:numel(lines)
        xd = get(lines(k), 'XData'); yd = get(lines(k), 'YData');
        if isempty(xd) || isempty(yd), continue; end
        fprintf('line %d: x[%g,%g] y[%g,%g] n=%d\n', k, min(xd), max(xd), min(yd), max(yd), numel(xd));
    end
    close(f);
end
disp('DONE');
