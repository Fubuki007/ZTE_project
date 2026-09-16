function squeeze_legends()
% 全图空位扫描（优先右上角），对更高一档字号找无碰撞位置
targets = {...
 'fig_angle_rmse_vs_snr_4methods_beta100_server_edited.fig', 17};
for i = 1:size(targets,1)
    fn = targets{i,1}; fs = targets{i,2};
    f = openfig(fn, 'invisible');
    ax = findobj(f, 'Type', 'axes'); ax = ax(1);
    lg = findobj(f, 'Type', 'legend'); lg = lg(1);
    lg.FontSize = fs;
    lg.ItemTokenSize = [max(30, fs*1.6), max(18, fs*1.0)];
    lg.Location = 'northeast';
    drawnow;
    p = lg.Position; w = p(3); h = p(4);
    lines = findobj(ax, 'Type', 'line');
    xn_all = []; yn_all = [];
    xl = ax.XLim; yl = ax.YLim;
    for k = 1:numel(lines)
        xd = get(lines(k), 'XData'); yd = get(lines(k), 'YData');
        xn_all = [xn_all, (xd - xl(1)) / (xl(2) - xl(1))];
        yn_all = [yn_all, (log10(yd) - log10(yl(1))) / (log10(yl(2)) - log10(yl(1)))];
    end
    m = 0.005;
    bestx = NaN; besty = NaN; found = false;
    for y0 = (1-h-0.02):-0.01:0.02          % 从上往下
        sel_y = (yn_all >= y0+m) & (yn_all <= y0+h-m);
        for x0 = (1-w-0.02):-0.01:0.02      % 从右往左
            sel = sel_y & (xn_all >= x0+m) & (xn_all <= x0+w-m);
            if ~any(sel)
                bestx = x0; besty = y0; found = true;
                break;
            end
        end
        if found, break; end
    end
    if found
        fprintf('%s fs=%d: manual pos [%.4f %.4f %.4f %.4f] OK\n', fn, fs, bestx, besty, w, h);
        lg.Position = [bestx besty w h];
        lg.AutoUpdate = 'off';
        drawnow;
        savefig(f, [fn '_tmp.fig']);
        close(f);
        movefile([fn '_tmp.fig'], fn, 'f');
    else
        fprintf('%s fs=%d: no free spot found\n', fn, fs);
        close(f);
    end
end
disp('SQUEEZE DONE');
end
