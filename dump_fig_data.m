% =========================================================================
% dump_fig_data.m  导出两张 fig 的曲线数据（供论文文字描述使用）
% =========================================================================
function dump_fig_data()
clear; close all; clc;
figs = {'fig/fig_snr_zf_null_lagrange_sic_range.fig', ...
        'fig/fig_si_strength_zf_null_lagrange_sic_range_mc10_smooth.fig'};
for fi = 1:numel(figs)
    p = fullfile(pwd, figs{fi});
    f = openfig(p, 'invisible');
    ax = gca;
    ls = findobj(ax, 'Type', 'line');
    fprintf('=== %s ===\n', figs{fi});
    for k = numel(ls):-1:1
        dn = ls(k).DisplayName;
        if isempty(dn), dn = '(marker-only)'; end
        x = ls(k).XData; y = ls(k).YData;
        fprintf('  %-26s npts=%d x=[%.4g, %.4g] y=[%.4g, %.4g]\n', dn, numel(x), min(x), max(x), min(y), max(y));
        idx = round(linspace(1, numel(y), 5));
        fprintf('     x@5: %s\n', num2str(x(idx), '%.4g '));
        fprintf('     y@5: %s\n', num2str(y(idx), '%.4g '));
    end
    close(f);
end
end
