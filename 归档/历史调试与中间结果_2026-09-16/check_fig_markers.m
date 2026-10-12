% =========================================================================
% check_fig_markers.m  检查原 fig / 新 fig 的 line 对象与 marker
% =========================================================================
function check_fig_markers()
clear; close all; clc;
pairs = { ...
    'fig/fig_si_strength_zf_null_sic_angle_mc10_smooth.fig', ...
    'fig/fig_si_strength_zf_null_lagrange_sic_angle_mc10_smooth.fig'};
for pi = 1:numel(pairs)
    p = fullfile(pwd, pairs{pi});
    f = openfig(p, 'invisible');
    ax = gca;
    ls = findobj(ax, 'Type', 'line');
    fprintf('=== %s: %d line objects ===\n', pairs{pi}, numel(ls));
    for k = numel(ls):-1:1
        dn = ls(k).DisplayName;
        if isempty(dn), dn = '(no-dn)'; end
        fprintf('   %-26s marker=%s npts=%d\n', dn, ls(k).Marker, numel(ls(k).YData));
    end
    close(f);
end
end
