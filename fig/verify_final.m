function verify_final()
% 重开三个 fig，复查字号/位置保存、碰撞检测，导出最终 PNG
files = {...
 'fig_rmse_vs_snr_4methods_edited.fig', ...
 'fig_velocity_rmse_vs_snr_4methods_beta100_server_edited.fig', ...
 'fig_angle_rmse_vs_snr_4methods_beta100_server_edited.fig'};
for i = 1:numel(files)
    fn = files{i};
    f = openfig(fn, 'invisible');
    ax = findobj(f, 'Type', 'axes'); ax = ax(1);
    lg = findobj(f, 'Type', 'legend'); lg = lg(1);
    fprintf('%s: fontsize=%g pos=%s token=%s loc=%s\n', fn, lg.FontSize, ...
        mat2str(lg.Position, 4), mat2str(lg.ItemTokenSize, 4), lg.Location);
    % 碰撞复查（margin 0.004）
    lines = findobj(ax, 'Type', 'line');
    xl = ax.XLim; yl = ax.YLim;
    p = lg.Position; m = 0.004;
    ncoll = 0;
    for k = 1:numel(lines)
        xd = get(lines(k), 'XData'); yd = get(lines(k), 'YData');
        xn = (xd - xl(1)) / (xl(2) - xl(1));
        yn = (log10(yd) - log10(yl(1))) / (log10(yl(2)) - log10(yl(1)));
        inside = (xn >= p(1)+m) & (xn <= p(1)+p(3)-m) & ...
                 (yn >= p(2)+m) & (yn <= p(2)+p(4)-m);
        ncoll = ncoll + sum(inside);
    end
    fprintf('  recheck coll (m=0.004): %d\n', ncoll);
    [~, nm] = fileparts(fn);
    exportgraphics(f, ['verify_' nm '.png'], 'Resolution', 200);
    close(f);
end
disp('VERIFY DONE');
end
