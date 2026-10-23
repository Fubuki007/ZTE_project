function options=fas_options(profile)
% Full profile inherits build_default_params; smoke changes are explicit.
options=struct('profile',char(profile),'seed',20261023,'mc',300, ...
    'snr_db',-50:5:10,'guards',[0 4 16],'main_guard',4, ...
    'port_step_lambda',.1,'min_spacing_lambda',.4,'position_rounds',2, ...
    'failure_position_m',5,'threads',2);
assert(ismember(options.profile,{'full','smoke'}));
if strcmp(profile,'smoke')
    options.mc=1; options.snr_db=[-20 10]; options.position_rounds=1;
end
end
