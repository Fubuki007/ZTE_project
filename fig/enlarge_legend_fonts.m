function enlarge_legend_fonts()
% 二分搜索每张图不遮挡曲线的最大图例字号，保存并导出验证 PNG
files = {...
 'fig_rmse_vs_snr_4methods_edited.fig', ...
 'fig_velocity_rmse_vs_snr_4methods_beta100_server_edited.fig', ...
 'fig_angle_rmse_vs_snr_4methods_beta100_server_edited.fig'};
if ~exist('backup_orig', 'dir'), mkdir('backup_orig'); end
for i = 1:numel(files)
    fn = files{i};
    copyfile(fn, fullfile('backup_orig', fn), 'f');  % 备份原图
    f = openfig(fn, 'invisible');
    ax = findobj(f, 'Type', 'axes'); ax = ax(1);
    lg = findobj(f, 'Type', 'legend');
    if isempty(lg), close(f); continue; end
    lg = lg(1);
    lg.AutoUpdate = 'off';
    lg.Location = 'northeast';   % 统一锚定右上角（曲线最空区域）
    % 收集全部曲线点，转为 axes 归一化坐标（y 为 log10 线性化）
    lines = findobj(ax, 'Type', 'line');
    X = []; Y = [];
    for k = 1:numel(lines)
        xd = get(lines(k), 'XData'); yd = get(lines(k), 'YData');
        if isempty(xd) || isempty(yd), continue; end
        X = [X, xd(:)']; Y = [Y, yd(:)'];
    end
    xl = ax.XLim; yl = ax.YLim;
    xn = (X - xl(1)) / (xl(2) - xl(1));
    yn = (log10(Y) - log10(yl(1))) / (log10(yl(2)) - log10(yl(1)));
    lo = 8; hi = 64; best = 8;
    while lo <= hi
        mid = floor((lo + hi) / 2);
        lg.FontSize = mid;
        lg.ItemTokenSize = [max(30, mid*1.6), max(18, mid*1.0)];
        drawnow;
        p = lg.Position;
        mx = 0.006; my = 0.006;   % 安全边距
        inside = (xn >= p(1)+mx) & (xn <= p(1)+p(3)-mx) & ...
                 (yn >= p(2)+my) & (yn <= p(2)+p(4)-my);
        box_ok = p(1) >= -0.005 && p(2) >= -0.005 && ...
                 p(1)+p(3) <= 1.005 && p(2)+p(4) <= 1.005;
        if ~any(inside) && box_ok
            best = mid; lo = mid + 1;
        else
            hi = mid - 1;
        end
    end
    lg.FontSize = best;
    lg.ItemTokenSize = [max(30, best*1.6), max(18, best*1.0)];
    drawnow;
    fprintf('%s -> fontsize %d, legend pos %s\n', fn, best, mat2str(lg.Position, 4));
    savefig(f, [fn '_tmp.fig']);
    close(f);
    movefile([fn '_tmp.fig'], fn, 'f');
    f = openfig(fn, 'invisible');
    [~, nm] = fileparts(fn);
    exportgraphics(f, ['verify_' nm '.png'], 'Resolution', 200);
    close(f);
end
disp('ALL DONE');
end
