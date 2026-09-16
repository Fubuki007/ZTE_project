% regen_velocity_fig.m - inspect & regenerate velocity RMSE fig
close all force;

src = 'fig_velocity_rmse_vs_snr_4methods_beta100_server_edited.fig';
h = openfig(src, 'invisible');

fprintf('Figure type: %s\n', class(h));
ax = findall(h, 'Type', 'axes');
fprintf('Axes count: %d\n', numel(ax));
lines = findall(h, 'Type', 'line');
fprintf('Line count: %d\n', numel(lines));
for i = 1:numel(lines)
    xd = get(lines(i), 'XData');
    yd = get(lines(i), 'YData');
    dn = get(lines(i), 'DisplayName');
    if isempty(dn), dn = '<none>'; end
    fprintf('Line %d: DisplayName=%s  Xlen=%d  Ylen=%d  Xrange=[%.1f %.1f] Yrange=[%.4g %.4g]\n', ...
        i, dn, numel(xd), numel(yd), min(xd), max(xd), min(yd), max(yd));
end
leg = findall(h, 'Type', 'legend');
fprintf('Legend count: %d\n', numel(leg));
if ~isempty(leg)
    fprintf('Legend strings: %s\n', strjoin(leg(1).String, ' | '));
end

% re-save a fresh editable fig
out = 'fig_velocity_rmse_vs_snr_4methods_beta100_server_regen.fig';
savefig(h, out);
fprintf('Saved: %s\n', out);
close(h);

% verify the regenerated file opens cleanly
h2 = openfig(out, 'invisible');
fprintf('Reopen OK, type=%s\n', class(h2));
close(h2);
fprintf('VERIFY DONE\n');
