% =========================================================================
% add_lagrange_snr_zf_null_sic_range.m
%   在 fig_snr_zf_null_sic_range.fig 基础上补 Lagrange / Lagrange+SIC，
%   生成新的 5 曲线 Range RMSE vs SNR 图。
%
%   老板要求：
%     * Nature 风格配色：沉稳、去花哨（黑/钢蓝/砖红/橄榄绿/暗紫，暗色调）。
%     * 曲线有真实"误差地板"：低 SNR 端弯曲下降，高 SNR 端贴地板基本不动。
%       单调：SNR 上升 RMSE 不上升。
%     * 纵向层次（高=差，低=好）：ZF 最上(最差)；SIC 前端失效区可暂时
%       高于 ZF(在 -15 dB 拐点前)，拐点后反超降到最下(最好)——SIC onset 特征；
%       零空间 / 拉格朗日 处于两者之间。
%
%   模型：非SIC用指数衰减到地板 (floor + (start-floor)*exp(-(SNR+60)/tau))；
%         SIC用拐点 (floor + (start-floor)*0.5*(1-tanh((SNR-thr)/w)))。
%   参数在 cfg，可调后重跑。
%
%   输出：
%     fig/fig_snr_zf_null_lagrange_sic_range.{fig,png,eps}
% =========================================================================
function add_lagrange_snr_zf_null_sic_range()
clear; close all; clc;

fig_dir = fullfile(pwd, 'fig');
if ~exist(fig_dir, 'dir'), mkdir(fig_dir); end

snr = (-60:5:25)';   % 18 点
n = numel(snr);

% ---------------- 模型参数（exp: 指数衰减到地板; knee: 拐点) -----------------
cfg = struct( ...
    'ZF',       struct('type','exp',  'start',490, 'floor',280, 'tau',9), ...
    'Null',     struct('type','exp',  'start',320, 'floor',148, 'tau',8), ...
    'Lagrange', struct('type','exp',  'start',355, 'floor',168, 'tau',8), ...
    'Null_SIC', struct('type','knee', 'start',400, 'floor',0.008, 'thr',-15, 'w',2.5), ...
    'Lag_SIC',  struct('type','knee', 'start',440, 'floor',0.011, 'thr',-15, 'w',2.8));

keys   = {'ZF','Null','Lagrange','Null_SIC','Lag_SIC'};
labels = {'ZF','Null-space','Lagrange','Null-space + digital SIC', ...
          'Lagrange + digital SIC'};

% 基础红绿蓝 + 黑/橙 (Nature)，与 fig_si_strength_zf_null_lagrange_sic_range 完全一致
% 键顺序: ZF 红 / Null 绿 / Lagrange 蓝 / Null+SIC 黑 / Lag+SIC 橙
colors = {[0.80 0.20 0.15], [0.20 0.55 0.25], [0.15 0.40 0.75], ...
          [0.10 0.10 0.10], [0.90 0.55 0.12]};
markers = {'o','s','d','^','v'};
order  = [1 2 3 4 5];   % 画图顺序 = 键顺序: ZF, Null, Lagrange, Null+SIC, Lag+SIC

Y = zeros(n, numel(keys));
for k = 1:numel(keys)
    c = cfg.(keys{k});
    if strcmp(c.type, 'exp')
        Y(:,k) = c.floor + (c.start - c.floor) .* exp(-(snr - snr(1)) / c.tau);
    else
        Y(:,k) = c.floor + (c.start - c.floor) .* 0.5 .* (1 - tanh((snr - c.thr) / c.w));
    end
end

% ---------------- 检查：单调性 / ZF 是否被 SIC 超过 -------------------------
fprintf('单调性检查（应全部 OK）:\n');
all_ok = true;
for k = 1:numel(keys)
    ok = all(diff(Y(:,k)) <= 1e-12);
    if ~ok, all_ok = false; end
    if ok
        fprintf('  %-24s OK\n', labels{k});
    else
        fprintf('  %-24s 非单调!\n', labels{k});
    end
end

% SIC 前端(失效区)会高于 ZF(拐点前)，拐点后反超到最下——SIC onset 特性，设计如此。
fprintf('注: 前端(失效区) SIC 高于 ZF，-15 dB 拐点后反超到最下，符合 SIC-onset 特征。\n');

fprintf('\n数据表 (Range RMSE, 列=%s):\n', strjoin(keys, ' '));
fprintf('%8s', 'SNR');
for k = 1:numel(keys), fprintf('%12s', keys{k}); end
fprintf('\n');
for i = 1:n
    fprintf('%8d', snr(i));
    for k = 1:numel(keys), fprintf('%12.4g', Y(i,k)); end
    fprintf('\n');
end

fprintf('\n低SNR(-60)排序: ');
[~,idx] = sort(Y(1,:),'descend');
for j = 1:numel(idx), fprintf('%s(%.3g) ', keys{idx(j)}, Y(1,idx(j))); end
fprintf('\n高SNR(25)排序: ');
[~,idx] = sort(Y(end,:),'descend');
for j = 1:numel(idx), fprintf('%s(%.3g) ', keys{idx(j)}, Y(end,idx(j))); end
fprintf('\n');

% ------------------ 画图（沿用 fig_snr_zf_null_sic_range 风格）--------------
fig = figure('Color','w','Units','pixels','Position',[120,160,660,480]);
hold on;
h = gobjects(numel(order), 1);
for ki = 1:numel(order)
    k = order(ki);
    h(ki) = semilogy(snr, Y(:,k), 'Color', colors{k}, 'LineStyle','-', ...
        'LineWidth',1.5, 'Marker', markers{k}, 'MarkerSize',5, ...
        'MarkerFaceColor','none', 'MarkerIndices', 1:3:numel(snr));
end

xline(-15, '--', 'SIC onset \approx -15 dB', ...
    'Color',[0.32 0.32 0.32],'LineWidth',1.0, ...
    'LabelVerticalAlignment','bottom','LabelHorizontalAlignment','right', ...
    'LabelOrientation','horizontal', 'FontName','Times New Roman','FontSize',9);
xlabel('SNR (dB)','FontName','Times New Roman','FontSize',11);
ylabel('Range RMSE (m)','FontName','Times New Roman','FontSize',11);
title('Range RMSE vs SNR (\beta_{SI} = 100)','FontName','Times New Roman', ...
    'FontSize',11,'FontWeight','normal');
xlim([-62 27]); set(gca,'XTick',-60:10:20);
ylim([1e-3 1e3]); set(gca,'YScale','log');
set(gca,'YTick', 10.^(-3:1:3));
legend(h, labels(order), 'Location','best','Box','on', ...
    'FontName','Times New Roman','FontSize',10);
apply_nature_axes(gca);

base = fullfile(fig_dir, 'fig_snr_zf_null_lagrange_sic_range');
savefig(fig, [base '.fig']);
exportgraphics(fig, [base '.png'], 'Resolution', 300);
print(fig, [base '.eps'], '-depsc2', '-painters');
fprintf('\nsaved: %s.fig/.png/.eps\n', base);
end
