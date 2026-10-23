% 接收阵元数相关图：每个指标各建一个figure，分别显示。
clear;
root=fileparts(mfilename('fullpath'));
addpath(root);
files={};
for m=[4 16], for snr=-50:5:10, files{end+1}=sprintf('rx_%d_snr_%d.mat',m,snr); end; end
for v=[9 25 49 100 196 400], files{end+1}=sprintf('snr_rx_%d.mat',v); end
for v=[9 16 25 36 49 64], files{end+1}=sprintf('runtime_rx_%d.mat',v); end
data_dir=select_plot_data(root,files);

%% 不同接收阵元数下的四项RMSE（横坐标为输入SNR）
values=[4 16]; snrs=-50:5:10;
methods={'无RIS','RIS辅助'};
colors=[.12 .36 .70;.12 .58 .35]; styles={'-','--',':'}; markers={'s','o'};
names={'range','velocity','elevation','azimuth'};
labels={'距离 RMSE','速度 RMSE','俯仰角 RMSE','方位角 RMSE'};
errors=zeros(numel(snrs),2,4,numel(values));
for k=1:numel(values)
    for j=1:numel(snrs)
        d=load(fullfile(data_dir,sprintf('rx_%d_snr_%d.mat',values(k),snrs(j))));
        errors(j,:,:,k)=reshape(d.rmse,1,2,4);
    end
end
for metric=[4 3 1 2]
    fig=figure('Position',[100 100 900 620]); hold on;
    for k=1:numel(values)
        for method=1:2
            plot(snrs,errors(:,method,metric,k),styles{k},'Marker',markers{method},'Color',colors(method,:),'LineWidth',1.3, ...
                'DisplayName',sprintf('%s，M_{rx}=%d',methods{method},values(k)));
        end
    end
    set(gca,'YScale','log'); limits=ylim; ylim(limits.*[0.8 1.2]);
    xlabel('输入 SNR (dB)'); ylabel(labels{metric}); xlim([snrs(1)-1 snrs(end)+1]);
    legend('Location','southoutside','NumColumns',2);
    style_figure(fig,['rx_' names{metric}]);
end

%% 输出SNR随接收阵元数变化（独立图片）
values=[9 25 49 100 196 400]; y=zeros(numel(values),2);
for k=1:numel(values)
    d=load(fullfile(data_dir,sprintf('snr_rx_%d.mat',values(k))));
    y(k,:)=d.snr;
end
fig=figure('Position',[100 100 850 580]);
colororder([.12 .36 .70;.12 .58 .35]);
hold on; styles={'-s','-o'};
for method=1:2
    plot(values,y(:,method),styles{method},'LineWidth',1.3);
end
 xlabel('接收天线数'); ylabel('输出 SNR (dB)');
xlim([0 415]);
ylim([min(y,[],'all')-1 max(y,[],'all')+1]);
legend('无RIS','RIS辅助','Location','best');
style_figure(fig,'snr_rx');

%% 运行时间随接收阵元数变化（独立图片）
values=[9 16 25 36 49 64]; y=zeros(numel(values),2);
for k=1:numel(values)
 d=load(fullfile(data_dir,sprintf('runtime_rx_%d.mat',values(k))));
 y(k,:)=d.latency;
end
fig=figure('Position',[100 100 850 580]); hold on;
labels={'无RIS','RIS辅助'};
styles={'-s','-o'}; colororder([.12 .36 .70;.12 .58 .35]);
for method=1:2
 plot(values,y(:,method),styles{method},'LineWidth',1.3,'DisplayName',labels{method});
end
yline(1,':k','1 s','HandleVisibility','off');
xlabel('接收天线数'); ylabel('运行时间 (s)');
legend('Location','northwest');
lo=min(y,[],'all'); hi=max(1,max(y,[],'all'));
ylim([max(0,lo-.05*(hi-lo)) hi+.06*(hi-lo)]);
style_figure(fig,'runtime_rx');
