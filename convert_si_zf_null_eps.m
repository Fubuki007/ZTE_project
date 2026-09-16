% =========================================================================
% convert_si_zf_null_eps.m — 把 SI 抑制对比图 .fig 转成 .eps (矢量, 论文用)
% =========================================================================
files = {
    'fig_si_suppression_angle_zf_null.fig'
    'fig_si_suppression_velocity_zf_null.fig'
    'fig_si_suppression_range_zf_null.fig'
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
