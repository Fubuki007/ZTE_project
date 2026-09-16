% =========================================================================
% verify_new_fig.m  核对新 fig 中的曲线对象与图例
% =========================================================================
function verify_new_fig()
clear; close all; clc;
names = {'angle', 'range', 'velocity'};
for fi = 1:3
    p = fullfile(pwd, 'fig', ...
        sprintf('fig_si_strength_zf_null_lagrange_sic_%s_mc10_smooth.fig', names{fi}));
    f = openfig(p, 'invisible');
    ax = gca;
    ls = findobj(ax, 'Type', 'line');
    fprintf('=== %s: %d line objects ===\n', names{fi}, numel(ls));
    for k = numel(ls):-1:1
        dn = ls(k).DisplayName;
        if isempty(dn), dn = '(marker)'; end
        yd = ls(k).YData;
        fprintf('  %-26s npts=%5d y=[%.4g, %.4g]\n', dn, numel(yd), min(yd), max(yd));
    end
    fprintf('  legend entries: %d | ylim=[%g, %g] xlim=[%g, %g]\n', ...
        numel(ax.Legend.String), ylim(ax), xlim(ax));
    close(f);
end
end
