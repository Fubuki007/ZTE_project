% adjust_fonts_velocity.m - enlarge fonts on the velocity RMSE regen fig
close all force;
h = openfig('fig_velocity_rmse_vs_snr_4methods_beta100_server_regen.fig', 'invisible');
ax = findall(h, 'Type', 'axes');
leg = findall(h, 'Type', 'legend');

% axis tick numbers (bottom numbers) -> 16
ax.FontSize = 16;

% axis labels -> 16
ax.XLabel.FontSize = 16;
ax.YLabel.FontSize = 16;

% legend stays at 14
if ~isempty(leg)
    leg(1).FontSize = 14;
    leg(1).Location = 'northwest';
end

savefig(h, 'fig_velocity_rmse_vs_snr_4methods_beta100_server_regen.fig');
fprintf('SAVED with AxesFont=%g LabelFont=%g LegendFont=%g\n', ...
    ax.FontSize, ax.XLabel.FontSize, leg(1).FontSize);

% verify by reopening
h2 = openfig('fig_velocity_rmse_vs_snr_4methods_beta100_server_regen.fig', 'invisible');
ax2 = findall(h2, 'Type', 'axes');
leg2 = findall(h2, 'Type', 'legend');
fprintf('VERIFY AxesFont=%g XLabelFont=%g YLabelFont=%g LegendFont=%g\n', ...
    ax2.FontSize, ax2.XLabel.FontSize, ax2.YLabel.FontSize, leg2(1).FontSize);
close(h2);

% export png preview
h3 = openfig('fig_velocity_rmse_vs_snr_4methods_beta100_server_regen.fig', 'invisible');
exportgraphics(h3, 'fig_velocity_rmse_vs_snr_4methods_beta100_server_regen.png', 'Resolution', 200);
close(h3);
fprintf('PNG EXPORTED\n');
