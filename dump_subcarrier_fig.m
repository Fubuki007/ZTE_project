% =========================================================================
% dump_subcarrier_fig.m  读取 range_RMSEvssubcarrier.fig 曲线数据
% =========================================================================
function dump_subcarrier_fig()
clear; close all; clc;
p = fullfile(pwd, 'fig', 'range_RMSEvssubcarrier.fig');
if ~isfile(p)
    error('找不到 %s', p);
end
f = openfig(p, 'invisible');
ax = gca;
fprintf('xlabel: %s | ylabel: %s | title: %s\n', ax.XLabel.String, ax.YLabel.String, ax.Title.String);
fprintf('xlim=[%g %g], ylim=[%g %g]\n', xlim(ax), ylim(ax));
ls = findobj(ax, 'Type', 'line');
fprintf('line objects: %d\n', numel(ls));
for k = numel(ls):-1:1
    dn = ls(k).DisplayName;
    if isempty(dn), dn = '(no-dn)'; end
    x = ls(k).XData; y = ls(k).YData;
    fprintf('  %-26s npts=%d x=[%.4g, %.4g] y=[%.4g, %.4g]\n', dn, numel(x), min(x), max(x), min(y), max(y));
    idx = round(linspace(1, numel(y), 6));
    fprintf('     x@6: %s\n', num2str(x(idx), '%.6g '));
    fprintf('     y@6: %s\n', num2str(y(idx), '%.6g '));
end
if ~isempty(ax.Legend)
    fprintf('legend: %d entries\n', numel(ax.Legend.String));
end
close(f);
end
