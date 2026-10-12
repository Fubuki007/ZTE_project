function [cfg, prefix, shards] = ris_beta_config
% Experiment identity is independent of sharding and process batch size.
cfg = struct('format_version',1,'n_mc_total',integer_env('RIS_MC_TOTAL',50), ...
    'snr_list',[-25 -20 -15 -10 0 10 20],'beta_list',[10 100 1000], ...
    'use_single',false,'sic_pilot_len',128,'sic_mode','pilot-LS thermal AWGN', ...
    'scheme_names',{{'No RIS / SIC off','RIS / SIC off', ...
                     'No RIS / SIC on','RIS / SIC on'}}, ...
    'seed_version','paired-v3','ris_phase','continuous');
cfg.snr_list = list_env('RIS_SNR_LIST',cfg.snr_list);
cfg.beta_list = list_env('RIS_BETA_LIST',cfg.beta_list);
if any(cfg.beta_list <= 0), error('RIS:Config','Beta values must be positive.'); end
raw = getenv('RIS_USE_SINGLE');
if ~isempty(raw) && ~strcmp(raw,'0'), error('RIS:Config','This sweep uses double precision.'); end
shards = integer_env('RIS_N_SHARDS',4);
if shards > cfg.n_mc_total, error('RIS:Config','Too many shards.'); end
prefix = getenv('RIS_RESULT_PREFIX');
if isempty(prefix), prefix = 'ris_beta_sweep_mc50_20261010_double'; end
if isempty(regexp(prefix,'^[A-Za-z0-9_]+$','once')), error('RIS:Config','Invalid prefix.'); end
end

function v = integer_env(name,default)
v = default; raw = getenv(name);
if ~isempty(raw), v = str2double(raw); end
if ~isscalar(v) || ~isfinite(v) || v < 1 || v ~= fix(v)
    error('RIS:Config','Invalid %s.',name);
end
end

function v = list_env(name,default)
v = default; raw = strtrim(getenv(name));
if ~isempty(raw), v = cellfun(@str2double,regexp(raw,'[,\s]+','split')); end
if isempty(v) || any(~isfinite(v)) || any(diff(v) <= 0)
    error('RIS:Config','Invalid %s.',name);
end
end
