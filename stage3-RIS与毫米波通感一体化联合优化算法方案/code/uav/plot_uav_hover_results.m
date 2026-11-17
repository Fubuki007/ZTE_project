function files=plot_uav_hover_results(results_dir,output_dir)
% Create presentation figures from already audited full-run evidence.
if nargin<2, output_dir=fullfile(results_dir,'presentation_figures'); end
if ~exist(output_dir,'dir'), mkdir(output_dir); end
s=jsondecode(fileread(fullfile(results_dir,'summary.json')));
v=jsondecode(fileread(fullfile(results_dir,'verification.json')));
m=jsondecode(fileread(fullfile(results_dir,'manifest.json')));
t=readtable(fullfile(results_dir,'case_metrics.csv'),'TextType','string');
assert(v.passed && v.cases==900 && height(t)==3600 && s.complete_cases==900);
assert(strcmp(s.manifest_id,m.id) && strcmp(v.manifest_id,m.id));
methods={'Fixed_NoRIS','Fixed_RIS','Selected_NoRIS','Selected_RIS'};
labels={'固定点 无RIS','固定点 有RIS','选点后 无RIS','选点后 有RIS'};
colors=[0.12 0.38 0.58;0.78 0.36 0.19;0.12 0.58 0.49;0.63 0.28 0.43];
rmse=s.position_rmse_m; failure=100*s.failure_rate; rcs=s.rcs_m2;
assert(isequal(s.methods(:),methods(:)) && isequal(rcs(:),[1;10;100]));
font='SimHei';

fig=figure('Color','w','Units','inches','Position',[0.5 0.5 15 8.4]);
ax1=axes('Parent',fig,'Position',[0.105 0.20 0.37 0.58]); hold(ax1,'on');
line_styles={'--','--','-','-'}; markers={'o','o','s','s'};
for k=1:4
    plot(ax1,rcs,rmse(:,k),'LineStyle',line_styles{k},'Marker',markers{k}, ...
        'Color',colors(k,:),'MarkerFaceColor',colors(k,:),'MarkerSize',8,'LineWidth',2.1);
end
set(ax1,'XScale','log','YScale','log','XTick',rcs,'XTickLabel',{'1','10','100'}, ...
    'FontName',font,'FontSize',12,'LineWidth',1,'Layer','top');
xlim(ax1,[0.8 125]); ylim(ax1,[2 1300]); grid(ax1,'on'); box(ax1,'on');
xlabel(ax1,'目標 RCS (m^2)','FontName',font,'FontSize',13);
ylabel(ax1,'三维定位 RMSE (m，对数坐标)','FontName',font,'FontSize',13);
title(ax1,'悬停位置优化前后定位误差','FontName',font,'FontSize',15,'FontWeight','bold');
lgd=legend(ax1,labels,'Orientation','horizontal','FontName',font,'FontSize',10,'Box','off');
lgd.Units='normalized'; lgd.Position=[0.16 0.84 0.68 0.04];
ax2=axes('Parent',fig,'Position',[0.575 0.20 0.37 0.58]); hold(ax2,'on');
b=bar(ax2,1:3,failure,'grouped','BarWidth',0.82);
for k=1:4, b(k).FaceColor=colors(k,:); b(k).EdgeColor='none'; end
set(ax2,'XTick',1:3,'XTickLabel',{'1','10','100'},'FontName',font, ...
    'FontSize',12,'LineWidth',1,'Layer','top');
xlim(ax2,[0.45 3.55]); ylim(ax2,[0 108]); yticks(ax2,0:20:100);
grid(ax2,'on'); box(ax2,'on');
xlabel(ax2,'目標 RCS (m^2)','FontName',font,'FontSize',13);
ylabel(ax2,'严格失败率 (%)','FontName',font,'FontSize',13);
title(ax2,'失败样本也计入统计','FontName',font,'FontSize',15,'FontWeight','bold');
annotation(fig,'textbox',[0.02 0.93 0.96 0.05],'String','无人机悬停点选择：固定位置与优化位置对比', ...
    'EdgeColor','none','FontName',font,'FontSize',18,'FontWeight','bold', ...
    'HorizontalAlignment','center','VerticalAlignment','middle');
note='每个 RCS n=300；优化在 z=80 m 的 9 个位置中选择。仿真为静态悬停，不含飞行轨迹。';
annotation(fig,'textbox',[0.04 0.015 0.92 0.045],'String',note,'EdgeColor','none', ...
    'FontName',font,'FontSize',9,'HorizontalAlignment','center');
files=export_pair(fig,output_dir,'uav_hover_all_rcs'); close(fig);

names={'position_without_RIS','position_with_RIS','RIS_at_fixed_position','RIS_after_position_selection'};
effect=zeros(1,4); effect_ci=zeros(4,2); failure_effect=zeros(1,4); failure_ci=zeros(4,2);
for k=1:4
    c=s.comparisons(strcmp({s.comparisons.name},names{k}) & [s.comparisons.rcs_m2]==10);
    assert(numel(c)==1); effect(k)=c.gain_percent; effect_ci(k,:)=c.ci95_percent;
end
pairs={ {'Fixed_NoRIS','Selected_NoRIS'}, {'Fixed_RIS','Selected_RIS'}, ...
    {'Fixed_NoRIS','Fixed_RIS'}, {'Selected_NoRIS','Selected_RIS'} };
rng(20261117,'twister'); draw=randi(300,300,4000);
for k=1:4
    a=get_group(t,10,pairs{k}{1}); b=get_group(t,10,pairs{k}{2});
    da=read_flag(a.failure); db=read_flag(b.failure); delta=double(da)-double(db);
    failure_effect(k)=100*mean(delta); boot=100*mean(delta(draw),1); boot=sort(boot);
    failure_ci(k,:)=[boot(100),boot(3900)];
end

fig=figure('Color','w','Units','inches','Position',[0.5 0.5 15 8.4]);
ypos=1:4; effect_color=[0.12 0.53 0.45]; ris_color=[0.76 0.39 0.20];
ax1=axes('Parent',fig,'Position',[0.23 0.20 0.28 0.58]); hold(ax1,'on');
xline(ax1,0,'-','Color',[0.35 0.35 0.35],'LineWidth',1.2);
for k=1:4
    c=effect_color; if k>2, c=ris_color; end
    plot(ax1,effect_ci(k,:),[ypos(k) ypos(k)],'-','Color',c,'LineWidth',3);
    plot(ax1,effect(k),ypos(k),'o','Color',c,'MarkerFaceColor',c,'MarkerSize',8);
end
contrast_labels={'选点增益（无RIS）','选点增益（有RIS）','RIS增益（固定点）','RIS增益（分别选点）'};
set(ax1,'YTick',ypos,'YTickLabel',contrast_labels,'YDir','reverse','FontName',font, ...
    'FontSize',10,'LineWidth',1,'Layer','top');
xlim(ax1,[-100 100]); ylim(ax1,[0.4 4.6]); xticks(ax1,-100:25:100);
grid(ax1,'on'); box(ax1,'on');
xlabel(ax1,'定位 RMSE 降幅 (%)','FontName',font,'FontSize',12);
title(ax1,'正值表示误差降低','FontName',font,'FontSize',14,'FontWeight','bold');
for k=1:4
    text(ax1,effect(k),ypos(k)-0.17,sprintf('%.1f%%',effect(k)), ...
        'FontName',font,'FontSize',9,'HorizontalAlignment','center');
end

ax2=axes('Parent',fig,'Position',[0.69 0.20 0.27 0.58]); hold(ax2,'on');
xline(ax2,0,'-','Color',[0.35 0.35 0.35],'LineWidth',1.2);
for k=1:4
    c=effect_color; if k>2, c=ris_color; end
    plot(ax2,failure_ci(k,:),[ypos(k) ypos(k)],'-','Color',c,'LineWidth',3);
    plot(ax2,failure_effect(k),ypos(k),'o','Color',c,'MarkerFaceColor',c,'MarkerSize',8);
end
set(ax2,'YTick',ypos,'YTickLabel',contrast_labels,'YDir','reverse','FontName',font, ...
    'FontSize',10,'LineWidth',1,'Layer','top');
xlim(ax2,[-25 25]); ylim(ax2,[0.4 4.6]); xticks(ax2,-25:5:25);
grid(ax2,'on'); box(ax2,'on');
xlabel(ax2,'严格失败率降低 (百分点)','FontName',font,'FontSize',12);
title(ax2,'配对 bootstrap 95% 区间','FontName',font,'FontSize',14,'FontWeight','bold');
for k=1:4
    text(ax2,failure_effect(k),ypos(k)-0.17,sprintf('%.1f',failure_effect(k)), ...
        'FontName',font,'FontSize',9,'HorizontalAlignment','center');
end
annotation(fig,'textbox',[0.02 0.93 0.96 0.05], ...
    'String','RCS=10：悬停位置收益与 RIS 对比需分开看', ...
    'EdgeColor','none','FontName',font,'FontSize',18,'FontWeight','bold', ...
    'HorizontalAlignment','center','VerticalAlignment','middle');
note='每项 n=300 配对场景；失败率区间为 4000 次配对 bootstrap。RIS“分别选点”也改变了悬停位置。';
annotation(fig,'textbox',[0.035 0.015 0.93 0.045],'String',note,'EdgeColor','none', ...
    'FontName',font,'FontSize',9,'HorizontalAlignment','center');
files=[files,export_pair(fig,output_dir,'uav_hover_rcs10_paired_effects')]; close(fig);
disp(files);
end

function group=get_group(t,rcs,method)
group=t(t.rcs_m2==rcs & t.method==method,:);
assert(height(group)==300,'Expected 300 paired cases per method.');
end

function value=read_flag(x)
if islogical(x), value=x; elseif isnumeric(x), value=x~=0; else
    value=strcmpi(string(x),'true') | string(x)=='1';
end
end

function files=export_pair(fig,folder,stem)
png=fullfile(folder,[stem,'.png']); pdf=fullfile(folder,[stem,'.pdf']);
exportgraphics(fig,png,'Resolution',300,'BackgroundColor','white');
exportgraphics(fig,pdf,'ContentType','vector','BackgroundColor','white');
files={png,pdf};
end
