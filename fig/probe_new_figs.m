function probe_new_figs()
% 探查两张新图：axes、坐标尺度、图例、对象类型、曲线范围
files = {...
 'fig_range_rmse_vs_si_strength_4methods_server_edited.fig', ...
 'fig_rmse_vs_subcarrier_4methods_edited.fig'};
for i = 1:numel(files)
    fn = files{i};
    f = openfig(fn, 'invisible');
    fprintf('=== %s ===\n', fn);
    fprintf('fig pos: %s\n', mat2str(f.Position, 4));
    axs = findobj(f, 'Type', 'axes');
    for a = 1:numel(axs)
        ax = axs(a);
        fprintf('axes %d pos: %s\n', a, mat2str(ax.Position, 4));
        fprintf('  xlim: %s  ylim: %s  xscale: %s  yscale: %s\n', ...
            mat2str(ax.XLim, 5), mat2str(ax.YLim, 5), ax.XScale, ax.YScale);
    end
    lg = findobj(f, 'Type', 'legend');
    if ~isempty(lg)
        fprintf('legend fontsize: %g\n', lg(1).FontSize);
        fprintf('legend pos: %s\n', mat2str(lg(1).Position, 4));
        fprintf('legend loc: %s\n', lg(1).Location);
        fprintf('legend strings:\n');
        for s = 1:numel(lg(1).String)
            fprintf('  [%s]\n', lg(1).String{s});
        end
    end
    % 对象类型统计
    objs = findobj(f);
    types = {};
    for k = 1:numel(objs)
        t = get(objs(k), 'Type');
        if ~any(strcmp(types, t)), types{end+1} = t; end %#ok<AGROW>
    end
    fprintf('object types: %s\n', strjoin(types, ', '));
    % 曲线范围（line 类）
    ax = findobj(f, 'Type', 'axes'); ax = ax(1);
    lines = findobj(ax, 'Type', 'line');
    for k = 1:numel(lines)
        xd = get(lines(k), 'XData'); yd = get(lines(k), 'YData');
        if isempty(xd) || isempty(yd), continue; end
        fprintf('line %d: x[%g,%g] y[%g,%g] n=%d color=%s\n', ...
            k, min(xd), max(xd), min(yd), max(yd), numel(xd), mat2str(get(lines(k),'Color')));
    end
    close(f);
end
disp('PROBE DONE');
end
