function [names,base,guards]=fas_methods(options)
names={'Fixed_noRIS','Fixed_RIS','FAS_noRIS','FAS_RIS'};
base=1:4; guards=[0 0 options.main_guard options.main_guard];
for guard=options.guards
    if guard==options.main_guard, continue; end
    for b=3:4
        names{end+1}=sprintf('%s_guard%d',names{b},guard);
        base(end+1)=b; guards(end+1)=guard;
    end
end
end
