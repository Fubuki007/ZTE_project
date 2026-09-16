% =========================================================================
% verify_snr_fig.m  核对 fig_snr_zf_null_lagrange_sic_range.fig
% =========================================================================
function verify_snr_fig()
clear; close all; clc;
p = fullfile(pwd, 'fig', 'fig_snr_zf_null_lagrange_sic_range.fig');
f = openfig(p, 'invisible');
ax = gca;
ls = findobj(ax, 'Type', 'line');
fprintf('line objects: %d\n', numel(ls));
for k = numel(ls):-1:1
    dn = ls(k).DisplayName;
    if isempty(dn), dn = '(no-dn)'; end
    fprintf('  %-26s color=[%s] marker=%s npts=%d y=[%.4g, %.4g]\n', dn, ...
        num2str(ls(k).Color, '%.2f '), ls(k).Marker, numel(ls(k).YData), ...
        min(ls(k).YData), max(ls(k).YData));
end
fprintf('legend: %d | ylim=[%g %g] xlim=[%g %g]\n', ...
    numel(ax.Legend.String), ylim(ax), xlim(ax));
fprintf('title: %s\n', ax.Title.String);
close(f);
end
