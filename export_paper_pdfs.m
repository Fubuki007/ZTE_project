% =========================================================================
% export_paper_pdfs.m — 把论文用 .fig 全部导出为矢量 PDF (Overleaf 用)
%   输出: fig/overleaf_export/*.pdf
% =========================================================================
clear; close all; clc;

files = {
    'fig_si_suppression_angle_zf_null.fig'
    'fig_si_suppression_range_zf_null.fig'
    'fig_si_suppression_velocity_zf_null.fig'
    'execution_time_vs_cpi_length_sion.fig'
    'execution_time_vs_subcarriers_sion.fig'
};
fig_dir = 'D:\AA 学习项目\AAA 智能反射面辅助通信感知\AAA ZTE_project\fig';
outdir  = fullfile(fig_dir, 'overleaf_export');
if ~exist(outdir, 'dir'), mkdir(outdir); end

for k = 1:numel(files)
    try
        fig = openfig(fullfile(fig_dir, files{k}), 'invisible');
        [~, name] = fileparts(files{k});
        out = fullfile(outdir, [name '.pdf']);
        exportgraphics(fig, out, 'ContentType', 'vector');
        fprintf('OK  %s\n', out);
        close(fig);
    catch err
        fprintf('FAIL %s : %s\n', files{k}, err.message);
    end
end
disp('DONE');
