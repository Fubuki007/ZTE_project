function enlarge_legends_v2()
% 五张图：图例去括号、最大字号空位扫描、另存 *_legend_large.fig + png
files = {...
 'fig_rmse_vs_snr_4methods_edited.fig', ...
 'fig_velocity_rmse_vs_snr_4methods_beta100_server_edited.fig', ...
 'fig_angle_rmse_vs_snr_4methods_beta100_server_edited.fig', ...
 'fig_range_rmse_vs_si_strength_4methods_server_edited.fig', ...
 'fig_rmse_vs_subcarrier_4methods_edited.fig'};
for i = 1:numel(files)
    fn = files{i};
    f = openfig(fn, 'invisible');
    ax = findobj(f, 'Type', 'axes'); ax = ax(1);
    lg = findobj(f, 'Type', 'legend'); lg = lg(1);
    lg.AutoUpdate = 'off';
    % 1) 图例文字去括号
    strs = lg.String;
    if ischar(strs), strs = cellstr(strs); end
    for s = 1:numel(strs)
        strs{s} = regexprep(strs{s}, '\s*\([^)]*\)\s*$', '');
    end
    lg.String = strs;
    % 2) 曲线点 -> axes 归一化坐标（按坐标尺度）
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
    best_fs = 0; best_pos = [];
    for fs = 40:-1:8
        lg.FontSize = fs;
        lg.ItemTokenSize = [max(30, fs*1.6), max(18, fs*1.0)];
        lg.Location = 'northeast';
        drawnow;
        p = lg.Position; w = p(3); h = p(4);
        if w > 0.96 || h > 0.96, continue; end
        found = false; bx = NaN; by = NaN;
        for y0 = (1-h-0.02):-0.02:0.02
            sel_y = (yn_all >= y0+m) & (yn_all <= y0+h-m);
            for x0 = (1-w-0.02):-0.02:0.02
                sel = sel_y & (xn_all >= x0+m) & (xn_all <= x0+w-m);
                if ~any(sel), found = true; bx = x0; by = y0; break; end
            end
            if found, break; end
        end
        if found
            best_fs = fs; best_pos = [bx by w h];
            break;
        end
    end
    if best_fs == 0
        fprintf('%s: nothing fits\n', fn); close(f); continue;
    end
    % 3) 应用最终设置并另存
    lg.FontSize = best_fs;
    lg.ItemTokenSize = [max(30, best_fs*1.6), max(18, best_fs*1.0)];
    lg.Position = best_pos;
    drawnow;
    [~, nm] = fileparts(fn);
    newfn = [nm '_legend_large.fig'];
    pngfile = [nm '_legend_large.png'];
    if exist(newfn, 'file'), delete(newfn); end
    if exist(pngfile, 'file'), delete(pngfile); end
    savefig(f, newfn);
    try
        exportgraphics(f, pngfile, 'Resolution', 200);
    catch
        print(f, pngfile, '-dpng', '-r200');
    end
    close(f);
    % 4) 重开验证 + 碰撞复查
    f2 = openfig(newfn, 'invisible');
    lg2 = findobj(f2, 'Type', 'legend'); lg2 = lg2(1);
    p2 = lg2.Position;
    sel = (xn_all >= p2(1)+m) & (xn_all <= p2(1)+p2(3)-m) & ...
          (yn_all >= p2(2)+m) & (yn_all <= p2(2)+p2(4)-m);
    ncoll = sum(sel);
    fprintf('%s -> fs=%d pos=[%.4f %.4f %.4f %.4f] coll=%d\n', ...
        newfn, lg2.FontSize, p2(1), p2(2), p2(3), p2(4), ncoll);
    close(f2);
end
disp('V2 DONE');
end
