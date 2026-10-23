function style_figure(fig,name)
% 统一各图样式，仅显示，不保存文件。
ax=findobj(fig,'Type','axes'); ax=ax(1);
% 二期PDF配色与网格，中文使用微软雅黑并放大刻度、轴名和图例。
set(fig,'Color','w','Position',[100 100 900 650]);
set(ax,'FontName','Microsoft YaHei','FontSize',16,'LineWidth',.8, ...
    'TickDir','in','TickLength',[.012 .025],'Box','on','Layer','top', ...
    'XMinorTick','on','YMinorTick','on','XGrid','on','YGrid','on', ...
    'XMinorGrid','on','YMinorGrid','on','GridLineStyle','-', ...
    'MinorGridLineStyle',':','GridColor',[.65 .65 .65], ...
    'MinorGridColor',[.75 .75 .75],'GridAlpha',.35,'MinorGridAlpha',.3);
set([ax.XLabel ax.YLabel],'FontName','Microsoft YaHei','FontSize',18,'FontWeight','normal');
% 从二期PDF提取的RGB颜色；参数组用颜色和标记区分，两种方法用线型区分。
colors=[.902344 .293945 .208008;.302002 .732422 .835938;0 .626953 .529297];
markers={'o','s','^'};
h=flipud(findobj(ax,'Type','line'));
is_rx=startsWith(name,'rx_'); is_cpi=startsWith(name,'cpi_');
for k=1:numel(h)
    label=string(h(k).DisplayName); index=min(k,3); style='-';
    if is_rx || is_cpi
        if is_rx
            token=regexp(label,'M_\{rx\}=(\d+)','tokens','once'); values=[4 16];
        else
            token=regexp(label,'L=(\d+)','tokens','once'); values=[16 64 256];
        end
        if ~isempty(token), index=find(values==str2double(token{1}),1); end
        if contains(label,'无RIS'), style='--'; end
    elseif contains(label,'无RIS')
        index=1;
    elseif contains(label,'RIS辅助')
        index=2;
    end
    set(h(k),'Color',colors(index,:),'LineStyle',style,'LineWidth',1.5, ...
        'Marker',markers{index},'MarkerSize',6,'MarkerEdgeColor',colors(index,:), ...
        'MarkerFaceColor',colors(index,:));
    if strcmp(style,'--'), h(k).MarkerFaceColor='w'; end
end
% 规模扫描采用二期图4、图5的对数横坐标，不改变数据。
if ismember(name,{'snr_rx','snr_cpi','runtime_tx','runtime_rx'})
    x=vertcat(h.XData); x=x(x>0);
    set(ax,'XScale','log','XTickMode','auto'); xlim(ax,[min(x)*.9 max(x)*1.1]);
end
if is_rx || is_cpi
    title(ax,'RMSE随输入SNR的变化');
elseif startsWith(name,'snr_')
    title(ax,'输出SNR');
else
    title(ax,['运行时间随' ax.XLabel.String '的变化']);
end
set(ax.Title,'FontName','Microsoft YaHei','FontSize',18,'FontWeight','normal');
lg=findobj(fig,'Type','legend');
for k=1:numel(lg)
    set(lg(k),'FontName','Microsoft YaHei','FontSize',15,'NumColumns',1, ...
        'Box','on','Color','w','EdgeColor','k','LineWidth',.6,'Location','northeast');
    if is_cpi, lg(k).Location='southwest'; end
    if startsWith(name,'runtime_'), lg(k).Location='northwest'; end
end
set(findall(ax,'Type','text'),'FontName','Microsoft YaHei');
drawnow;
end
