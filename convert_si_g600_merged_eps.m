% =========================================================================
% convert_si_g600_merged_eps.m — 合并图 .fig → .eps (矢量, 论文用)
% =========================================================================
files = {
    'fig_si_strength_g600_merged_angle.fig'
    'fig_si_strength_g600_merged_velocity.fig'
    'fig_si_strength_g600_merged_range.fig'
};
fig_dir = 'D:\AA 学习项目\AAA 智能反射面辅助通信感知\AAA ZTE_project\fig';
outdir  = fullfile(fig_dir, 'eps_export');
if ~exist(outdir, 'dir'), mkdir(outdir); end

for k = 1:numel(files)
    try
        fig = openfig(fullfile(fig_dir, files{k}), 'invisible');
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
