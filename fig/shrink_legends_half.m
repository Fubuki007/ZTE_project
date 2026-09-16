function shrink_legends_half()
% 把五张 *_legend_large 图的图例字号减半，中心位置不变，覆盖保存并复查碰撞
files = {...
 'fig_rmse_vs_snr_4methods_edited_legend_large.fig', ...
 'fig_velocity_rmse_vs_snr_4methods_beta100_server_edited_legend_large.fig', ...
 'fig_angle_rmse_vs_snr_4methods_beta100_server_edited_legend_large.fig', ...
 'fig_range_rmse_vs_si_strength_4methods_server_edited_legend_large.fig', ...
 'fig_rmse_vs_subcarrier_4methods_edited_legend_large.fig'};
for i = 1:numel(files)
    fn = files{i};
    f = openfig(fn, 'invisible');
    ax = findobj(f, 'Type', 'axes'); ax = ax(1);
    lg = findobj(f, 'Type', 'legend'); lg = lg(1);
    oldp = lg.Position;
    oldfs = lg.FontSize;
    cx = oldp(1) + oldp(3)/2;   % 原框中心
    cy = oldp(2) + oldp(4)/2;
    newfs = round(oldfs / 2);
    lg.FontSize = newfs;
    lg.ItemTokenSize = [max(30, newfs*1.6), max(18, newfs*1.0)];
    lg.Location = 'northeast';
    drawnow;
    p = lg.Position; w2 = p(3); h2 = p(4);
    newpos = [cx - w2/2, cy - h2/2, w2, h2];
    newpos(1) = min(max(newpos(1), 0.005), 1 - w2 - 0.005);
    newpos(2) = min(max(newpos(2), 0.005), 1 - h2 - 0.005);
    lg.Position = newpos;
    drawnow;
    % 碰撞复查（margin 0.005）
    lines = findobj(ax, 'Type', 'line');
    xl = ax.XLim; yl = ax.YLim;
    if strcmp(ax.XScale, 'log'), xt = @(v) log10(v); else, xt = @(v) v; end
    if strcmp(ax.YScale, 'log'), yt = @(v) log10(v); else, yt = @(v) v; end
    m = 0.005; ncoll = 0;
    q = lg.Position;
    for k = 1:numel(lines)
        xd = get(lines(k), 'XData'); yd = get(lines(k), 'YData');
        if isempty(xd) || isempty(yd), continue; end
        xn = (xt(xd) - xt(xl(1))) / (xt(xl(2)) - xt(xl(1)));
        yn = (yt(yd) - yt(yl(1))) / (yt(yl(2)) - yt(yl(1)));
        inside = (xn >= q(1)+m) & (xn <= q(1)+q(3)-m) & ...
                 (yn >= q(2)+m) & (yn <= q(2)+q(4)-m);
        ncoll = ncoll + sum(inside);
    end
    fprintf('%s -> fs %g -> %d, pos %s, coll=%d\n', fn, oldfs, newfs, mat2str(q, 4), ncoll);
    % 保存 + 导出 png
    pngfile = strrep(fn, '.fig', '.png');
    if exist(fn, 'file'), delete(fn); end
    if exist(pngfile, 'file'), delete(pngfile); end
    savefig(f, fn);
    try
        exportgraphics(f, pngfile, 'Resolution', 200);
    catch
        print(f, pngfile, '-dpng', '-r200');
    end
    close(f);
end
disp('SHRINK DONE');
end
