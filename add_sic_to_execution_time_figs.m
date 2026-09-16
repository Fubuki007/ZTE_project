% =========================================================================
% add_sic_to_execution_time_figs.m
%   给两张 execution_time zf_null 图加一条 "Null-space + digital SIC" 线
%   数据来源：直接复用图中 Null-space 线的数据（估计器耗时相同，
%             SIC 在仿真阶段，不影响 estimator-only 计时）
% =========================================================================
function add_sic_to_execution_time_figs()
fig_dir = fullfile(pwd, 'fig');

files = { ...
    'execution_time_vs_cpi_length_zf_null.fig', ...
    'execution_time_vs_subcarriers_zf_null.fig' ...
};

for i = 1:numel(files)
    fig_path = fullfile(fig_dir, files{i});
    [~, name, ~] = fileparts(files{i});
    fig = openfig(fig_path, 'invisible');
    ax = findobj(fig, 'Type', 'axes');
    if isempty(ax)
        error('No axes in %s', files{i});
    end
    ax = ax(1);
    lines = findobj(ax, 'Type', 'line');

    ns_line = [];
    for k = 1:numel(lines)
        if strcmp(get(lines(k), 'DisplayName'), 'Null-space')
            ns_line = lines(k);
            break;
        end
    end
    if isempty(ns_line)
        error('Null-space line not found in %s', files{i});
    end

    x = get(ns_line, 'XData');
    y = get(ns_line, 'YData');

    hold(ax, 'on');
    plot(ax, x, y, '-.', ...
        'Color', [0.200 0.627 0.173], ...
        'LineWidth', 1.35, ...
        'Marker', '^', ...
        'MarkerSize', 5.2, ...
        'MarkerFaceColor', 'w', ...
        'DisplayName', 'Null-space + digital SIC');
    hold(ax, 'off');

    % Rebuild legend with three entries
    legend(ax, {'ZF', 'Null-space', 'Null-space + digital SIC'}, ...
        'Location', 'northwest', 'Box', 'on', ...
        'FontName', 'Times New Roman', 'FontSize', 8);

    % Save .fig / .png / .eps
    savefig(fig, fig_path);
    exportgraphics(fig, fullfile(fig_dir, [name '.png']), 'Resolution', 600);
    print(fig, fullfile(fig_dir, [name '.eps']), '-depsc2', '-r300');
    close(fig);
    fprintf('updated: %s.fig/.png/.eps\n', name);
end
fprintf('Done.\n');
end
