function params = build_default_params(overrides)
%BUILD_DEFAULT_PARAMS Build the parameters used by the delivered SI pipeline.
%   PARAMS = BUILD_DEFAULT_PARAMS(OVERRIDES) accepts a struct of independent
%   scene, array, waveform and SI settings. N and B may be overridden for
%   reduced simulations, but B/N must equal delta_f_Hz. Derived fields
%   (lambda, d, Ts, meta) are recomputed after overrides.
%
%   Array dimensions: TX=Ntx x Nty, RX=Mx x My. K is the number of OFDM
%   symbols (called L in the signal model); K_stream is the user count.
%   Target vectors theta_true/phi_true/R_true/v_true/alpha must all have
%   num_targets elements. Angles are degrees; ranges are meters; speeds
%   are m/s. SI beta_SI is an amplitude multiplier, not a power ratio.

if nargin < 1 || isempty(overrides)
    overrides = struct();
end
if ~isstruct(overrides) || ~isscalar(overrides)
    error('overrides must be a scalar struct.');
end

params = struct();
params.c = 3e8;
params.fc = 28e9;
params.Mx = 8;
params.My = 8;
params.Ntx = 4;
params.Nty = 4;
params.K = 256;
params.K_stream = 1;
params.mod_order = 16;

params.num_targets = 2;
params.theta_true = [60.83, 15.94];
params.phi_true = [28.51, 11.53];
params.R_true = [200.6, 210.4];
params.v_true = [15.1, -5.4];
params.alpha = [1.0, 0.8];
params.SNR = 10;                       % dB, relative to target-only power

params.enable_SI = true;
params.beta_SI = 0.001;
params.enable_SIC = false;
params.sic_use_true_channel = false;   % simulation-only ideal SIC bound
params.SIC_pilot_len = 64;
params.precoder_type = 'nullspace';
params.kappa_SI = 10;                  % linear Rician K factor
params.theta_SI = 10.5;
params.phi_SI = 10.5;
params.v_SI = 0;

% Nominal FR2 component carrier: 264 RB x 12 SC, 120 kHz spacing.
params.n_rb = 264;
params.sc_per_rb = 12;
params.delta_f_Hz = 120e3;
params.T_cp_s = 0.6e-6;
params.target_range_resolution_m = 0.1;
params.range_margin_m = 15;

params.fast_estimator = struct( ...
    'n_samp_r', 256, 'n_samp_l', 64, 'n_pad_v', params.K, ...
    'enable_hann', true, 'num_candidates', 64, ...
    'nms_r', 2, 'nms_v', 2, 'R_min_gate', 20, 'R_max_gate', 0);

% Apply only public, independent settings. Derived quantities cannot be
% overwritten independently; otherwise the saved metadata would be stale.
allowed = [fieldnames(params); {'N'; 'B'; 'R_SI'; 'H_SI'; ...
    'H_SI_matrix'; 'H_SI_per_cc'; 'SIC_pilot'; 'user_theta_rad'; ...
    'user_phi_rad'; 'ns_lambda'; 'lg_lambda'}];
fields = fieldnames(overrides);
for i = 1:numel(fields)
    name = fields{i};
    if ~ismember(name, allowed)
        error('Unsupported parameter override: %s', name);
    end
    if strcmp(name, 'fast_estimator')
        if ~isstruct(overrides.fast_estimator) || ...
                ~isscalar(overrides.fast_estimator)
            error('fast_estimator override must be a scalar struct.');
        end
        setting_names = fieldnames(overrides.fast_estimator);
        for j = 1:numel(setting_names)
            setting = setting_names{j};
            if ~isfield(params.fast_estimator, setting)
                error('Unsupported fast_estimator setting: %s', setting);
            end
            params.fast_estimator.(setting) = overrides.fast_estimator.(setting);
        end
    else
        params.(name) = overrides.(name);
    end
end
if ~isfield(overrides, 'fast_estimator') || ...
        ~isfield(overrides.fast_estimator, 'n_pad_v')
    params.fast_estimator.n_pad_v = params.K;
end

validateattributes(params.fc, {'numeric'}, {'scalar', 'positive', 'finite'});
validateattributes(params.delta_f_Hz, {'numeric'}, {'scalar', 'positive', 'finite'});
validateattributes(params.target_range_resolution_m, {'numeric'}, ...
    {'scalar', 'positive', 'finite'});
validateattributes(params.beta_SI, {'numeric'}, {'scalar', 'nonnegative', 'finite'});
validateattributes(params.kappa_SI, {'numeric'}, {'scalar', 'nonnegative', 'finite'});
for name = {'Mx', 'My', 'Ntx', 'Nty', 'K', 'K_stream', 'num_targets'}
    validateattributes(params.(name{1}), {'numeric'}, ...
        {'scalar', 'integer', 'positive'});
end
if params.K_stream > params.Ntx * params.Nty
    error('K_stream cannot exceed the total number of TX antennas.');
end
for name = {'theta_true', 'phi_true', 'R_true', 'v_true', 'alpha'}
    if numel(params.(name{1})) ~= params.num_targets
        error('%s must have num_targets=%d elements.', name{1}, params.num_targets);
    end
end

params.lambda = params.c / params.fc;
params.d = params.lambda / 2;
if ~isfield(overrides, 'R_SI')
    params.R_SI = 10 * params.lambda;
end

N_per_cc = params.n_rb * params.sc_per_rb;
B_per_cc = N_per_cc * params.delta_f_Hz;
if ~isfield(overrides, 'N')
    params.N = ceil(params.c / (2 * params.target_range_resolution_m * ...
        B_per_cc)) * N_per_cc;
end
validateattributes(params.N, {'numeric'}, {'scalar', 'integer', 'positive'});
if ~isfield(overrides, 'B')
    params.B = params.N * params.delta_f_Hz;
end
if abs(params.B / params.N - params.delta_f_Hz) > ...
        1e-9 * params.delta_f_Hz
    error('B/N must equal delta_f_Hz; change N and B together.');
end
params.Ts = 1 / params.delta_f_Hz + params.T_cp_s;

params.meta = struct( ...
    'N_per_cc', N_per_cc, 'B_per_cc', B_per_cc, ...
    'n_cc', params.N / N_per_cc, 'delta_f', params.delta_f_Hz, ...
    'range_resolution', params.c / (2 * params.B), ...
    'R_max', params.c / (2 * params.delta_f_Hz), ...
    'required_Rmax', max(params.R_true) + params.range_margin_m, ...
    'target_range_resolution', params.target_range_resolution_m);
end
