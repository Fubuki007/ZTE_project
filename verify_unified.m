% =========================================================================
% verify_unified.m  核对 fig_si_strength_zf_null_lagrange_sic_range_mc10_smooth.fig
% =========================================================================
function verify_unified()
clear; close all; clc;
% 检查 SI 强度 range 图
p = fullfile(pwd, 'fig', 'fig_si_strength_zf_null_lagrange_sic_range_mc10_smooth.fig');
if ~isfile(p)
    error('找不到 %s', p);
end
f = openfig(p, 'invisible');
ax = gca;
ls = findobj(ax, 'Type', 'line');
fprintf('SI-strength range fig: %d line objects\n', numel(ls));
for k = numel(ls):-1:1
    dn = ls(k).DisplayName;
    if isempty(dn), dn = '(no-dn)'; end
    fprintf('  %-26s color=[%s] npts=%d\n', dn, num2str(ls(k).Color, '%.2f '), numel(ls(k).YData));
end
fprintf('legend: %d | ylim=[%g %g]\n', numel(ax.Legend.String), ylim(ax));
close(f);

% 顺便核对 SNR range 图
p2 = fullfile(pwd, 'fig', 'fig_snr_zf_null_lagrange_sic_range.fig');
if isfile(p2)
    f2 = openfig(p2, 'invisible');
    ax2 = gca;
    ls2 = findobj(ax2, 'Type', 'line');
    fprintf('\nSNR range fig: %d line objects\n', numel(ls2));
    for k = numel(ls2):-1:1
        dn = ls2(k).DisplayName;
        if isempty(dn), dn = '(no-dn)'; end
        fprintf('  %-26s color=[%s] marker=%s\n', dn, num2str(ls2(k).Color, '%.2f '), ls2(k).Marker);
    end
    fprintf('legend: %d\n', numel(ax2.Legend.String));
    close(f2);
end
end
