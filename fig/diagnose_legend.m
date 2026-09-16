function diagnose_legend()
% 诊断：扫描字号，输出图例框与碰撞曲线
files = {...
 'fig_rmse_vs_snr_4methods_edited.fig', ...
 'fig_velocity_rmse_vs_snr_4methods_beta100_server_edited.fig', ...
 'fig_angle_rmse_vs_snr_4methods_beta100_server_edited.fig'};
for i = 1:numel(files)
    fn = files{i};
    f = openfig(fn, 'invisible');
    fprintf('=== %s ===\n', fn);
    fprintf('fig pos: %s\n', mat2str(f.Position, 4));
    ax = findobj(f, 'Type', 'axes'); ax = ax(1);
    lg = findobj(f, 'Type', 'legend'); lg = lg(1);
    lg.AutoUpdate = 'off';
    lines = findobj(ax, 'Type', 'line');
    Xall = {}; Yall = {};
    for k = 1:numel(lines)
        Xall{k} = get(lines(k), 'XData'); Yall{k} = get(lines(k), 'YData');
    end
    xl = ax.XLim; yl = ax.YLim;
    for fs = 9:2:27
        lg.FontSize = fs;
        lg.ItemTokenSize = [max(30, fs*1.6), max(18, fs*1.0)];
        for loc = {'northeast', 'best', 'northwest', 'southeast'}
            lg.Location = loc{1};
            drawnow;
            p = lg.Position;
            mx = 0.006; my = 0.006;
            ncoll = 0; maxyn = -inf; coll_lines = [];
            for k = 1:numel(lines)
                xd = Xall{k}; yd = Yall{k};
                xn = (xd - xl(1)) / (xl(2) - xl(1));
                yn = (log10(yd) - log10(yl(1))) / (log10(yl(2)) - log10(yl(1)));
                inside = (xn >= p(1)+mx) & (xn <= p(1)+p(3)-mx) & ...
                         (yn >= p(2)+my) & (yn <= p(2)+p(4)-my);
                if any(inside)
                    ncoll = ncoll + sum(inside);
                    coll_lines(end+1) = k; %#ok<AGROW>
                end
                maxyn = max(maxyn, max(yn(inside)));
            end
            fprintf('fs=%2d loc=%-10s pos=[%.3f %.3f %.3f %.3f] coll_pts=%5d coll_lines=[%s]\n', ...
                fs, loc{1}, p(1), p(2), p(3), p(4), ncoll, num2str(coll_lines));
        end
    end
    close(f);
end
disp('DIAG DONE');
end
