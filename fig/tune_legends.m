function tune_legends()
% range 图：往右下区域（曲线下方空白）重试
specs = { ...
  {'fig_range_rmse_vs_si_strength_4methods_server_edited_legend_large.fig', 20, [0.40 0.75], [0.08 0.35]}};
for i = 1:numel(specs)
    fn = specs{i}{1}; fs_start = specs{i}{2};
    xr = specs{i}{3}; yr = specs{i}{4};
    f = openfig(fn, 'invisible');
    ax = findobj(f, 'Type', 'axes'); ax = ax(1);
    lg = findobj(f, 'Type', 'legend'); lg = lg(1);
    lg.AutoUpdate = 'off';
    lines = findobj(ax, 'Type', 'line');
    xn_all = []; yn_all = [];
    xl = ax.XLim; yl = ax.YLim;
    if strcmp(ax.XScale, 'log'), xt = @(v) log10(v); else, xt = @(v) v; end
    if strcmp(ax.YScale, 'log'), yt = @(v) log10(v); else, yt = @(v) v; end
    for k = 1:numel(lines)
        xd = get(lines(k), 'XData'); yd = get(lines(k), 'YData');
        if isempty(xd) || isempty(yd), continue; end
        xn_all = [xn_all, (xt(xd) - xt(xl(1))) / (xt(xl(2)) - xt(xl(1)))]; %#ok<AGROW>
        yn_all = [yn_all, (yt(yd) - yt(yl(1))) / (yt(yl(2)) - yt(yl(1)))]; %#ok<AGROW>
    end
    m = 0.005;
    best_fs = 0; best_pos = []; use_full = false;
    for fs = fs_start:-1:8
        lg.FontSize = fs;
        lg.ItemTokenSize = [max(30, fs*1.6), max(18, fs*1.0)];
        lg.Location = 'northeast';
        drawnow;
        p = lg.Position; w = p(3); h = p(4);
        if w > 0.96 || h > 0.96, continue; end
        found = false; bx = NaN; by = NaN;
        for y0 = min(yr(2), 1-h-0.02):-0.02:max(yr(1), 0.02)
            sel_y = (yn_all >= y0+m) & (yn_all <= y0+h-m);
            for x0 = min(xr(2), 1-w-0.02):-0.02:max(xr(1), 0.02)
                sel = sel_y & (xn_all >= x0+m) & (xn_all <= x0+w-m);
                if ~any(sel), found = true; bx = x0; by = y0; break; end
            end
            if found, break; end
        end
        if ~found
            for y0 = (1-h-0.02):-0.02:0.02
                sel_y = (yn_all >= y0+m) & (yn_all <= y0+h-m);
                for x0 = (1-w-0.02):-0.02:0.02
                    sel = sel_y & (xn_all >= x0+m) & (xn_all <= x0+w-m);
                    if ~any(sel), found = true; bx = x0; by = y0; break; end
                end
                if found, break; end
            end
            if found, use_full = true; end
        end
        if found
            best_fs = fs; best_pos = [bx by w h];
            break;
        end
    end
    if best_fs == 0
        fprintf('%s: nothing fits\n', fn); close(f); continue;
    end
    lg.FontSize = best_fs;
    lg.ItemTokenSize = [max(30, best_fs*1.6), max(18, best_fs*1.0)];
    lg.Position = best_pos;
    drawnow;
    q = lg.Position;
    sel = (xn_all >= q(1)+m) & (xn_all <= q(1)+q(3)-m) & ...
          (yn_all >= q(2)+m) & (yn_all <= q(2)+q(4)-m);
    ncoll = sum(sel);
    fprintf('%s -> fs=%d pos=[%.4f %.4f %.4f %.4f] coll=%d full=%d\n', ...
        fn, best_fs, q(1), q(2), q(3), q(4), ncoll, use_full);
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
disp('TUNE2 DONE');
end
