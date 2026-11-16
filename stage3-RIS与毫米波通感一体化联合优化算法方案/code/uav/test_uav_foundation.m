function report=test_uav_foundation(output)
root=fileparts(mfilename('fullpath')); addpath(root,fileparts(root)); maxNumCompThreads(2);
cfg=uav_config('smoke'); scene=struct('targets',cfg.targets,'prior',cfg.targets+[2 -3 0;-4 1 0], ...
    'scatter_phase',[.3 -.6]);
[p,prior]=uav_parameters(cfg,scene,cfg.hover,10);
[p2,~]=uav_parameters(cfg,scene,[40 0 80],100);
g=channel_geometry(p.truth,p);
world=(p.world_to_local'*g.position).'+p.hover;
assert(max(abs(world-scene.targets),[],'all')<1e-10,'Coordinate roundtrip failed.');
assert(p.noise_power==p2.noise_power && p.noise_w==p2.noise_w,'Noise must not follow position/RCS.');
expected=sqrt(10*[1 .8]).*(cfg.reference_range_m./p.R_true).^2;
assert(max(abs(abs(p.alpha)-expected))<1e-12,'Radar inverse-square field law failed.');
assert(abs(p.reference_amplitude^2-p.lambda^2/((4*pi)^3*cfg.reference_range_m^4))<1e-25);
assert(abs(p.noise_w-1.380649e-23*290*p.B*10^(.7))<1e-20);
for enabled=0:1
    p.ris_enabled=enabled; d=cell(2,1); o=cell(2,1); y=cell(2,1);
    for s=1:2
        d{s}=uav_design(prior,p,enabled,s);
        assert(d{s}.feasible && norm(d{s}.W,'fro')^2<=1+1e-8);
        assert(all(d{s}.sinr>=10.^(p.comm_sinr_db/10)));
        quantized=angle(d{s}.phase)*2^p.ris_bits/(2*pi);
        assert(max(abs(quantized-round(quantized)))<1e-12);
        other=p; other.alpha=100*p.alpha; other.truth=p.truth+1;
        alternative=uav_design(prior,other,enabled,s);
        assert(isequal(d{s}.W,alternative.W) && isequal(d{s}.phase,alternative.phase), ...
            'Designer must not read target truth/scattering.');
        times=round(linspace(0,p.K-1,p.fine_l)); rng(100+s,'twister');
        o{s}=prepare_ris_observation(p.truth,p,times(s:2:end));
        assert(norm(o{s}.B'*o{s}.B-eye(o{s}.rank),'fro')<1e-7);
        n=zeros(p.Mx*p.My,size(o{s}.symbol,2));
        [y{s},clean]=uav_echo(p,o{s},d{s},n); assert(isequal(y{s},clean));
        if ~enabled
            direct=zeros(size(n));
            for q=1:p.Q
                gt=channel_geometry(p.truth(q,:),p);
                ph=exp(-1j*2*pi*p.delta_f/p.c*o{s}.n_grid*2*p.R_true(q));
                wave=ph.*((gt.transmit'*d{s}.W)*o{s}.symbol).';
                direct=direct+p.alpha(q)*gt.receive*wave.';
            end
            projected=reshape(direct*conj(o{s}.B),[],1);
            assert(norm(projected-y{s})/max(norm(y{s}),realmin)<1e-12);
        end
    end
    [~,fit]=refine_ris_parameters(vertcat(y{:}),o,d,p.truth,p);
    assert(fit.residual/max(norm(vertcat(y{:}))^2,realmin)<1e-12, ...
        'Synthesized four-path echo does not match the inherited estimator.');
end
result=uav_case(cfg,0,2);
assert(isequal(size(result.position_errors),[2 4]) && all(isfinite(result.position_errors),'all'));
assert(all(result.locked) && all(result.feasible),'Smoke must exercise every fine-estimation branch.');
assert(isequal(result.coarse(:,:,1),result.coarse(:,:,2)), ...
    'Fixed RIS/no-RIS must share the complete coarse observation.');
assert(all(result.tx_power_fraction(isfinite(result.tx_power_fraction))<=1+1e-6));
report=struct('passed',true,'profile','smoke','position_rmse_m',sqrt(mean(result.position_errors.^2,1)), ...
    'locked',result.locked,'feasible',result.feasible,'seconds',result.seconds, ...
    'checks',{{'coordinate roundtrip','fixed thermal noise','radar link budget', ...
    'power/SINR/2-bit phases','no target-truth leakage into design', ...
    'orthonormal projection','no-RIS physical DD echo','four-path synthesis/fit consistency','paired acquisition'}});
if nargin>0, uav_write_json(output,report); end
disp(report);
end
