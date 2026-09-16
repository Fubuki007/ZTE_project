% probe_fonts.m - inspect current font sizes of the regen fig
close all force;
h = openfig('fig_velocity_rmse_vs_snr_4methods_beta100_server_regen.fig', 'invisible');
ax = findall(h, 'Type', 'axes');
leg = findall(h, 'Type', 'legend');
tit = get(ax, 'Title');
fprintf('Title string: %s\n', tit.String);
fprintf('Title FontSize: %s\n', mat2str(tit.FontSize));
fprintf('Axes FontSize: %s\n', mat2str(ax.FontSize));
fprintf('Axes Label x: %s (FontSize %s)\n', ax.XLabel.String, mat2str(ax.XLabel.FontSize));
fprintf('Axes Label y: %s (FontSize %s)\n', ax.YLabel.String, mat2str(ax.YLabel.FontSize));
if ~isempty(leg)
    fprintf('Legend FontSize: %s\n', mat2str(leg(1).FontSize));
end
fprintf('XA tick font size (default = axes FontSize): %s\n', mat2str(ax.FontSize));
close(h);
