function export_large_legend_figs()
% 恢复原 fig（从 backup_orig），应用放大图例，另存为新 fig 并导出 png
specs = { ...
 'fig_rmse_vs_snr_4methods_edited.fig', 16, [0.4400 0.5790 0.5400 0.2110]; ...
 'fig_velocity_rmse_vs_snr_4methods_beta100_server_edited.fig', 18, [0.4287 0.5830 0.5513 0.2270]; ...
 'fig_angle_rmse_vs_snr_4methods_beta100_server_edited.fig', 16, [0.4826 0.3990 0.4974 0.2110]};
for i = 1:size(specs,1)
    fn = specs{i,1}; fs = specs{i,2}; pos = specs{i,3};
    % 1) 恢复原 fig（撤销之前的覆盖）
    copyfile(fullfile('backup_orig', fn), fn, 'f');
    % 2) 打开并应用放大的图例
    f = openfig(fn, 'invisible');
    lg = findobj(f, 'Type', 'legend'); lg = lg(1);
    lg.AutoUpdate = 'off';
    lg.FontSize = fs;
    lg.ItemTokenSize = [max(30, fs*1.6), max(18, fs*1.0)];
    lg.Position = pos;
    drawnow;
    % 3) 另存为新 fig，导出新 png
    [~, nm] = fileparts(fn);
    newfn = [nm '_legend_large.fig'];
    savefig(f, newfn);
    exportgraphics(f, [nm '_legend_large.png'], 'Resolution', 200);
    close(f);
    % 4) 重开新 fig 验证 + 碰撞复查（margin 0.004）
    f2 = openfig(newfn, 'invisible');
    ax = findobj(f2, 'Type', 'axes'); ax = ax(1);
    lg2 = findobj(f2, 'Type', 'legend'); lg2 = lg2(1);
    lines = findobj(ax, 'Type', 'line');
    xl = ax.XLim; yl = ax.YLim;
    p = lg2.Position; m = 0.004; ncoll = 0;
    for k = 1:numel(lines)
        xd = get(lines(k), 'XData'); yd = get(lines(k), 'YData');
        xn = (xd - xl(1)) / (xl(2) - xl(1));
        yn = (log10(yd) - log10(yl(1))) / (log10(yl(2)) - log10(yl(1)));
        inside = (xn >= p(1)+m) & (xn <= p(1)+p(3)-m) & ...
                 (yn >= p(2)+m) & (yn <= p(2)+p(4)-m);
        ncoll = ncoll + sum(inside);
    end
    fprintf('%s -> fs=%g pos=%s coll=%d\n', newfn, lg2.FontSize, mat2str(lg2.Position, 4), ncoll);
    close(f2);
end
disp('EXPORT DONE');
end
