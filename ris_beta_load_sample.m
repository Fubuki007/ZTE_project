function [sample, valid, reason] = ris_beta_load_sample(path,cfg,mc)
sample = struct(); valid = false; reason = 'missing';
if ~isfile(path), return; end
try
    sample = load(path);
    assert(isequaln(sample.config,cfg),'Configuration mismatch');
    assert(isequal(sample.mc,mc),'MC identity mismatch');
    shape = [4 numel(cfg.snr_list) numel(cfg.beta_list)];
    assert(islogical(sample.completed) && same_shape(sample.completed,shape),'Invalid completion mask');
    names = {'rmse_theta','rmse_phi','rmse_R','rmse_v','detected', ...
        'sic_suppression_db','theta_sse','phi_sse','n_matched'};
    for k=1:numel(names)
        v = sample.(names{k});
        assert(isnumeric(v) && isreal(v) && same_shape(v,shape),'Invalid metric dimensions');
    end
    assert(isscalar(sample.reference_target_power) && ...
        isfinite(sample.reference_target_power) && sample.reference_target_power>0,'Invalid reference power');
    mask = sample.completed;
    for name = {'detected','n_matched'}
        v=sample.(name{1})(mask);
        assert(all(isfinite(v) & v>=0 & v==fix(v)),'Invalid counts');
    end
    hit = mask & sample.n_matched>0;
    for name = {'rmse_theta','rmse_phi','rmse_R','rmse_v','theta_sse','phi_sse'}
        v=sample.(name{1})(hit);
        assert(all(isfinite(v) & v>=0),'Invalid completed errors');
    end
    on = false(shape); on(3:4,:,:) = true;
    assert(all(isfinite(sample.sic_suppression_db(mask & on))),'Missing SIC diagnostics');
    valid=true; reason='';
catch ex
    sample=struct(); reason=ex.message;
end
end

function ok = same_shape(a,shape)
ok = size(a,1)==shape(1) && size(a,2)==shape(2) && ...
    size(a,3)==shape(3) && numel(a)==prod(shape);
end
