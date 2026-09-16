function fix_figs_no_title_larger_font()
%FIX_FIGS_NO_TITLE_LARGER_FONT  去掉三个fig的标题并放大全部字体，另存为新文件（不覆盖原文件）
%
% 用法：在 MATLAB 中把当前目录切换到本脚本所在目录，然后运行：
%   fix_figs_no_title_larger_font
%
% 输出（新文件，原文件保持不变）：
%   *_edited.fig / *_edited.eps / *_edited.png

FONT_SIZE = 15;          % 主体字号（坐标轴刻度、轴标签、text），想更大改这里
LEGEND_FONT_SIZE = 10;   % 图例字号（单独调小，避免图例太大挡住曲线）
SUFFIX    = '_edited';

files = { ...
    'fig_rmse_vs_snr_4methods.fig', ...
    'fig_range_rmse_vs_si_strength_4methods_server.fig', ...
    'fig_rmse_vs_subcarrier_4methods.fig'};

for k = 1:numel(files)
    src = files{k};
    if ~exist(src, 'file')
        warning('文件不存在，跳过: %s', src);
        continue;
    end

    hfig = openfig(src, 'invisible');

    % ---- 1. 删除所有标题 ----
    axs = findall(hfig, 'Type', 'axes');
    for a = axs'
        try, title(a, ''); catch, end   % 子图标题置空
    end
    % 兼容 sgtitle / suptitle 等总标题对象
    hd = [findall(hfig, 'Tag', 'sgtitle'); findall(hfig, 'Tag', 'suptitle')];
    for t = hd'
        try, delete(t); catch, end
    end

    % ---- 2. 放大主体字体（不含图例） ----
    for a = axs'
        try, set(a, 'FontSize', FONT_SIZE); catch, end
        try, set(get(a, 'XLabel'), 'FontSize', FONT_SIZE); catch, end
        try, set(get(a, 'YLabel'), 'FontSize', FONT_SIZE); catch, end
        try, set(get(a, 'ZLabel'), 'FontSize', FONT_SIZE); catch, end
    end
    txts = findall(hfig, 'Type', 'text');   % 包括残留的 title 对象
    for t = txts'
        try, set(t, 'FontSize', FONT_SIZE); catch, end
    end
    cbs = findall(hfig, 'Type', 'colorbar');
    for c = cbs'
        try, set(c, 'FontSize', FONT_SIZE); catch, end
    end

    % ---- 3. 图例：字号调小 + 自动避开曲线（保持在坐标轴框内） ----
    lgs = findall(hfig, 'Type', 'legend');
    for l = lgs'
        try, set(l, 'FontSize', LEGEND_FONT_SIZE); catch, end
        try, set(l, 'Location', 'best'); catch, end
    end

    % ---- 4. 另存为新文件，不覆盖原文件 ----
    [~, name, ext] = fileparts(src);
    dst = [name SUFFIX ext];
    savefig(hfig, dst);

    % ---- 5. 导出 EPS（矢量） ----
    epspath = [name SUFFIX '.eps'];
    try
        print(hfig, epspath, '-depsc');
        fprintf('已导出: %s\n', epspath);
    catch err
        warning('EPS 导出失败: %s', err.message);
    end

    % ---- 6. 导出 PNG（预览） ----
    pngpath = [name SUFFIX '.png'];
    try
        print(hfig, pngpath, '-dpng', '-r200');
        fprintf('已导出: %s\n', pngpath);
    catch err
        warning('PNG 导出失败: %s', err.message);
    end

    close(hfig);
    fprintf('已生成: %s\n', dst);
end

fprintf('完成。原文件未被修改。\n');
end
