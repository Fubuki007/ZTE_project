function [sample, valid, reason] = ris_sic_load_sample(path_name, config, mc)
% Validate partial/complete samples; NaN RMSE is legitimate for no detection.
sample = struct(); valid = false; reason = '';
if ~isfile(path_name), reason = 'missing'; return; end
try
    sample = load(path_name);
    assert(sample.mc == mc && isstruct(sample.config), 'Sample identity mismatch.');
    fields = fieldnames(config);
    for k = 1:numel(fields)
        name = fields{k};
        assert(isfield(sample.config,name) && ...
            isequaln(sample.config.(name), config.(name)), 'Configuration mismatch: %s', name);
    end
    shape = [6 numel(config.snr_list)];
    assert(islogical(sample.completed) && isequal(size(sample.completed),shape), ...
        'Invalid completion mask.');
    metrics = {'rmse_theta','rmse_phi','rmse_R','rmse_v','detected','sic_suppression_db'};
    for k = 1:numel(metrics)
        value = sample.(metrics{k});
        assert(isnumeric(value) && isreal(value) && isequal(size(value),shape), ...
            'Invalid metric: %s',metrics{k});
    end
    count = sample.detected(sample.completed);
    assert(all(isfinite(count) & count >= 0 & count == fix(count)), 'Invalid detection counts.');
    for k = 1:4
        value = sample.(metrics{k});
        detected_mask = sample.completed & sample.detected > 0;
        assert(all(isfinite(value(detected_mask)) & value(detected_mask) >= 0), ...
            'Invalid completed RMSE: %s',metrics{k});
    end
    valid = true;
catch ME
    reason = ME.message;
    sample = struct();
end
end
