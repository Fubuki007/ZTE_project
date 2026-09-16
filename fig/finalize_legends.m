function finalize_legends()
% 为每张图选最大不遮挡字号的图例，冻结位置，保存并验证
files = {...
 'fig_rmse_vs_snr_4methods_edited.fig', ...
 'fig_velocity_rmse_vs_snr_4methods_beta100_server_edited.fig', ...
 'fig_angle_rmse_vs_snr_4methods_beta100_server_edited.fig'};
% 每文件候选 {fontsize, location}，从大到小，取第一个无碰撞的
cands = { ...
  { {14,'best'} {13,'best'} {15,'best'} }, ...
  { {18,'best'} {17,'best'} {19,'best'} }, ...
  { {12,'northeast'} {11,'northeast'} {13,'northeast'} } };
for i = 1:numel(files)
    fn = files{i};
    f = openfig(fn, 'invisible');
    ax = findobj(f, 'Type', 'axes'); ax = ax(1);
    lg = findobj(f, 'Type', 'legend'); lg = lg(1);
    lg.AutoUpdate = 'off';
    lines = findobj(ax, 'Type', 'line');
    Xall = {}; Yall = {};
    for k = 1:numel(lines)
        Xall{k} = get(lines(k), 'XData'); Yall{k} = get(lines(k), 'YData');
    end
    xl = ax.XLim; yl = ax.YLim;
    chosen = []; ch_p = []; ch_fs = 0;
    for c = 1:numel(cands{i})
        fs = cands{i}{c}{1}; loc = cands{i}{c}{2};
        lg.FontSize = fs;
        lg.ItemTokenSize = [max(30, fs*1.6), max(18, fs*1.0)];
        lg.Location = loc;
        drawnow;
        p = lg.Position;
        mx = 0.006; my = 0.006;
        ncoll = 0;
        for k = 1:numel(lines)
            xd = Xall{k}; yd = Yall{k};
            xn = (xd - xl(1)) / (xl(2) - xl(1));
            yn = (log10(yd) - log10(yl(1))) / (log10(yl(2)) - log10(yl(1)));
            inside = (xn >= p(1)+mx) & (xn <= p(1)+p(3)-mx) & ...
                     (yn >= p(2)+my) & (yn <= p(2)+p(4)-my);
            ncoll = ncoll + sum(inside);
        end
        box_ok = p(1) >= 0 && p(2) >= 0 && p(1)+p(3) <= 1 && p(2)+p(4) <= 1;
        fprintf('%s fs=%2d loc=%-10s coll=%4d box_ok=%d\n', fn, fs, loc, ncoll, box_ok);
        if ncoll == 0 && box_ok
            chosen = cands{i}{c}; ch_p = p; ch_fs = fs;
            break;
        end
    end
    if isempty(chosen)
        fprintf('%s: no candidate passed\n', fn);
        close(f); continue;
    end
    % 冻结位置：手动 Position（Location 自动变 none），重开不再漂移
    lg.Position = ch_p;
    lg.AutoUpdate = 'off';
    drawnow;
    fprintf('==> %s -> fontsize %d, loc %s, pos %s\n', fn, ch_fs, chosen{2}, mat2str(lg.Position, 4));
    savefig(f, [fn '_tmp.fig']);
    close(f);
    movefile([fn '_tmp.fig'], fn, 'f');
    % 重开验证：字号/位置是否保留 + 碰撞复查 + 导出 PNG
    f = openfig(fn, 'invisible');
    ax = findobj(f, 'Type', 'axes'); ax = ax(1);
    lg = findobj(f, 'Type', 'legend'); lg = lg(1);
    fprintf('REOPEN %s: fontsize %d, pos %s\n', fn, lg.FontSize, mat2str(lg.Position, 4));
    [~, nm] = fileparts(fn);
    exportgraphics(f, ['verify_' nm '.png'], 'Resolution', 200);
    close(f);
end
disp('FINALIZE DONE');
end
