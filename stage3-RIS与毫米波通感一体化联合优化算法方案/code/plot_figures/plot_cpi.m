% 观测符号数相关图：每个指标各建一个figure，分别显示。
clear;
root=fileparts(mfilename('fullpath'));
addpath(root);
files={};
for k=[16 64 256], for snr=-60:5:10, files{end+1}=sprintf('cpi_%d_snr_%d.mat',k,snr); end; end
for v=[16 32 64 128 256 512 1024], files{end+1}=sprintf('snr_cpi_%d.mat',v); end
data_dir=select_plot_data(root,files);

%% 不同观测符号数下的四项RMSE（横坐标为输入SNR）
values=[16 64 256]; snrs=-60:5:10;
methods={'无RIS','RIS辅助'};
colors=[.12 .36 .70;.12 .58 .35]; styles={'-','--',':'}; markers={'s','o'};
names={'range','velocity','elevation','azimuth'};
labels={'距离 RMSE','速度 RMSE','俯仰角 RMSE','方位角 RMSE'};
errors=zeros(numel(snrs),2,4,numel(values));
for k=1:numel(values)
    for j=1:numel(snrs)
        d=load(fullfile(data_dir,sprintf('cpi_%d_snr_%d.mat',values(k),snrs(j))));
        errors(j,:,:,k)=reshape(d.rmse,1,2,4);
    end
end
for metric=[4 3 1 2]
    fig=figure('Position',[100 100 900 620]); hold on;
    for k=1:numel(values)
        for method=1:2
            plot(snrs,errors(:,method,metric,k),styles{k},'Marker',markers{method},'Color',colors(method,:),'LineWidth',1.3, ...
                'DisplayName',sprintf('%s，L=%d',methods{method},values(k)));
        end
    end
    set(gca,'YScale','log'); limits=ylim; ylim(limits.*[0.8 1.2]);
    xlabel('输入 SNR (dB)'); ylabel(labels{metric}); xlim([snrs(1)-1 snrs(end)+1]);
    legend('Location','southoutside','NumColumns',3);
    style_figure(fig,['cpi_' names{metric}]);
end

%% 输出SNR随观测符号数变化（独立图片）
values=[16 32 64 128 256 512 1024]; y=zeros(numel(values),2);
for k=1:numel(values)
    d=load(fullfile(data_dir,sprintf('snr_cpi_%d.mat',values(k))));
    y(k,:)=d.snr;
end
fig=figure('Position',[100 100 850 580]);
colororder([.12 .36 .70;.12 .58 .35]);
hold on; styles={'-s','-o'};
for method=1:2
    plot(values,y(:,method),styles{method},'LineWidth',1.3);
end
 xlabel('每个估计阶段的符号数'); ylabel('输出 SNR (dB)');
legend('无RIS','RIS辅助','Location','best');
style_figure(fig,'snr_cpi');
