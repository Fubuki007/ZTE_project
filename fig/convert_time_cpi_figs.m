% 批量把 time vs cpi / subcarriers 的 .fig 转成 .png
files = {
    'execution_time_vs_cpi_length.fig'
    'execution_time_vs_cpi_length_paper_axis.fig'
    'execution_time_vs_cpi_length_sion.fig'
    'execution_time_vs_subcarriers.fig'
    'execution_time_vs_subcarriers_paper_axis.fig'
    'execution_time_vs_subcarriers_sion.fig'
};
outdir = fullfile(pwd, 'png_preview');
if ~exist(outdir, 'dir'), mkdir(outdir); end
for k = 1:numel(files)
    try
        fig = openfig(files{k}, 'invisible');
        [~, name] = fileparts(files{k});
        out = fullfile(outdir, [name '.png']);
        exportgraphics(fig, out, 'Resolution', 150);
        fprintf('OK  %s\n', out);
        close(fig);
    catch err
        fprintf('FAIL %s : %s\n', files{k}, err.message);
    end
end
disp('DONE');
