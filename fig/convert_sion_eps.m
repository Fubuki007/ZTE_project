% 把 sion 版 .fig 转成 eps（矢量格式，论文用）
files = {
    'execution_time_vs_cpi_length_sion.fig'
    'execution_time_vs_subcarriers_sion.fig'
};
outdir = fullfile(pwd, 'eps_export');
if ~exist(outdir, 'dir'), mkdir(outdir); end
for k = 1:numel(files)
    try
        fig = openfig(files{k}, 'invisible');
        [~, name] = fileparts(files{k});
        out = fullfile(outdir, [name '.eps']);
        exportgraphics(fig, out, 'ContentType', 'vector');
        fprintf('OK  %s\n', out);
        close(fig);
    catch err
        fprintf('FAIL %s : %s\n', files{k}, err.message);
    end
end
disp('DONE');
