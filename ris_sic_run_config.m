function [config, prefix, n_shards] = ris_sic_run_config
% Shared experiment identity. Worker count is deliberately not part of it.
config = struct('format_version', 3, 'n_mc_total', env_integer('RIS_MC_TOTAL',60), ...
    'snr_list', [-25 -20 -15 -10 0 10 20], 'beta_si', 0.1, 'use_single', false);
n_shards = env_integer('RIS_N_SHARDS',4);
if n_shards > config.n_mc_total, error('RIS_N_SHARDS exceeds RIS_MC_TOTAL.'); end
raw = lower(strtrim(getenv('RIS_USE_SINGLE')));
if ~isempty(raw)
    if ~any(strcmp(raw, {'0','1','true','false','yes','no','on','off'}))
        error('Invalid RIS_USE_SINGLE.');
    end
    config.use_single = any(strcmp(raw, {'1','true','yes','on'}));
end
raw = strtrim(getenv('RIS_SNR_LIST'));
if ~isempty(raw)
    tokens = regexp(raw, '[,\s]+', 'split');
    config.snr_list = cellfun(@str2double, tokens);
    if any(~isfinite(config.snr_list)) || any(diff(config.snr_list) <= 0)
        error('RIS_SNR_LIST must contain increasing finite SNR values.');
    end
end
tag = getenv('RIS_RUN_TAG');
if isempty(tag), tag = 'resume_v3'; end
if isempty(regexp(tag, '^[A-Za-z0-9_]+$', 'once')), error('Invalid RIS_RUN_TAG.'); end
precision = 'double';
if config.use_single, precision = 'single'; end
prefix = sprintf('ris_sic_rmse_snr_mc%d_%s_%s',config.n_mc_total,tag,precision);
end

function value = env_integer(name, default_value)
raw = getenv(name);
value = default_value;
if isempty(raw), return; end
value = str2double(raw);
if ~isfinite(value) || value < 1 || value ~= fix(value)
    error('%s must be a positive integer.', name);
end
end
