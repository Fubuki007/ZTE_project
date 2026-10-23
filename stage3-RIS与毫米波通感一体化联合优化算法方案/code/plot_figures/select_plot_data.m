function folder=select_plot_data(root,files)
% 绘图脚本与results同属交付目录，固定读取这组已保存数据。
folder=fullfile(fileparts(root),'results');
missing=files(~cellfun(@(name) isfile(fullfile(folder,name)),files));
assert(isempty(missing),'缺少绘图数据：%s',strjoin(missing,', '));
end
