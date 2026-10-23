function visualize_results()
% 读取本目录蒙特卡洛结果
root = fileparts(mfilename('fullpath'));
d = load(fullfile(root,'ZTE_3D_RIS_MC_results.mat'));
folder = fullfile(root,'figures');
if ~exist(folder,'dir'), mkdir(folder); end
color = [.302 .732 .836];

% ---- 1. 两组RMSE图，每个指标单独保存 ----
names = {'range','velocity','elevation','azimuth'};
labels = {'距离 RMSE','速度 RMSE','俯仰角 RMSE','方位角 RMSE'};
colors = [.902 .294 .208; .302 .732 .836; 0 .627 .529];
markers = {'o','s','^'};
scans = {d.rx_results,d.symbol_results};
snrs = {d.snrs_rx,d.snrs_symbols};
counts = {d.rx_counts,d.symbol_counts};
prefix = {'rx','symbols'};
symbol = {'M_{rx}','L'};
for group = 1:2
    for metric = 1:4
        fig = figure('Color','w','Position',[100 100 900 650]);
        hold on;
        for k = 1:numel(scans{group})
            plot(snrs{group},scans{group}{k}.rmse(:,metric), ...
                'Color',colors(k,:),'Marker',markers{k}, ...
                'MarkerFaceColor',colors(k,:),'MarkerSize',6,'LineWidth',1.5, ...
                'DisplayName',sprintf('RIS辅助，%s=%d',symbol{group},counts{group}(k)));
        end
        set(gca,'YScale','log'); % 用对数纵轴展示跨多个数量级的RMSE。
        xlabel('输入 SNR (dB)'); ylabel(labels{metric});
        xlim([min(snrs{group}) max(snrs{group})]);
        xticks(min(snrs{group}):10:max(snrs{group}));
        legend('Location','northeast');
        save_plot(fig,folder,[prefix{group} '_' names{metric}]);
    end
end

% ---- 2. RIS阵元数变化 ----
for metric = 1:4
    fig = figure('Color','w','Position',[100 100 900 650]);
    values = cellfun(@(x) x.rmse(metric),d.ris_results);
    plot(d.ris_values,values,'-s','Color',color, ...
        'MarkerFaceColor',color,'MarkerSize',6,'LineWidth',1.5);
    set(gca,'YScale','log');
    xlabel('RIS阵元数'); ylabel(labels{metric});
    xticks(d.ris_values);
    legend('RIS辅助','Location','northeast');
    save_plot(fig,folder,['ris_' names{metric}]);
end

% ---- 3. 运行时间随三类阵列规模变化 ----
values = {d.tx_values,d.rx_values,d.ris_values};
names = {'tx','rx','ris'};
labels = {'发射天线数','接收天线数','RIS阵元数'};
for k = 1:3
    fig = figure('Color','w','Position',[100 100 900 650]);
    plot(values{k},mean(d.latency{k},1),'-s','Color',color, ...
        'MarkerFaceColor',color,'MarkerSize',6,'LineWidth',1.5);
    yline(1,':k','1 s','HandleVisibility','off');
    xlabel(labels{k}); ylabel('运行时间 (s)');
    xticks(values{k});
    legend('RIS辅助','Location','northwest');
    save_plot(fig,folder,['runtime_' names{k}]);
end
end

function save_plot(fig,folder,name)
ax = gca;
set(ax,'FontName','Microsoft YaHei','FontSize',16,'TickDir','in', ...
    'Box','on','XMinorTick','on','YMinorTick','on', ...
    'Position',[.17 .15 .78 .80]);
ax.XLabel.FontSize = 18; ax.YLabel.FontSize = 18;
lg = findobj(fig,'Type','Legend');
set(lg,'FontName','Microsoft YaHei','FontSize',15);
grid on; grid minor;
drawnow;
savefig(fig,fullfile(folder,[name '.fig']));
exportgraphics(fig,fullfile(folder,[name '.png']),'Resolution',200);
end
