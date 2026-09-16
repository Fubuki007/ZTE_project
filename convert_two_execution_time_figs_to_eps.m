% convert_two_execution_time_figs_to_eps.m
% 打开两个 .fig 并导出 .eps 矢量图
function convert_two_execution_time_figs_to_eps()
fig_dir = fullfile(pwd, 'fig');

files = { ...
    'execution_time_vs_cpi_length_zf_null.fig', ...
    'execution_time_vs_subcarriers_zf_null.fig' ...
};

for i = 1:numel(files)
    fig_path = fullfile(fig_dir, files{i});
    [~, name, ~] = fileparts(files{i});
    eps_path = fullfile(fig_dir, [name '.eps']);
    fig = openfig(fig_path, 'invisible');
    print(fig, eps_path, '-depsc2', '-r300');
    close(fig);
    fprintf('saved: %s\n', eps_path);
end
fprintf('Done.\n');
end
