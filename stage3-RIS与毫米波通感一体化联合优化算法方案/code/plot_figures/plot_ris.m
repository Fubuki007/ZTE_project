% RIS阵元数相关图：仅保留文档图6(c)的运行时间。
clear;
root=fileparts(mfilename('fullpath'));
addpath(root);
files=arrayfun(@(v) sprintf('runtime_ris_%d.mat',v),[4 16 64 256 1024],'UniformOutput',false);
data_dir=select_plot_data(root,files);

%% 运行时间随RIS阵元数变化（独立图片）
values=[4 16 64 256 1024]; y=zeros(numel(values),2);
for k=1:numel(values)
 d=load(fullfile(data_dir,sprintf('runtime_ris_%d.mat',values(k))));
 y(k,:)=d.latency;
end
fig=figure('Position',[100 100 850 580]); hold on;
labels={'无RIS','RIS辅助'};
styles={'-s','-o'}; colororder([.12 .36 .70;.12 .58 .35]);
for method=1:2
 plot(values,y(:,method),styles{method},'LineWidth',1.3,'DisplayName',labels{method});
end
yline(1,':k','1 s','HandleVisibility','off');
set(gca,'XScale','log','XTick',values); xlim([3 1400]);
xlabel('RIS阵元数'); ylabel('运行时间 (s)');
legend('Location','northwest');
lo=min(y,[],'all'); hi=max(1,max(y,[],'all'));
ylim([max(0,lo-.05*(hi-lo)) hi+.06*(hi-lo)]);
style_figure(fig,'runtime_ris');
