function cfg = nc_config(profile)
% NC_CONFIG  Configuration for 3GPP UMi urban street-canyon UAV-BS + passive RIS ISAC.
% Implements Proposal v2.0: 32x32 passive 2-bit RIS (17.1 cm, D_F = 11.0 m),
% zero artificial no-fly box, communication-tethered 3D building blockage,
% true wideband frequency-dependent steering, and detection-margin + CRB optimization.
if nargin < 1, profile = 'full'; end

cfg = struct();
cfg.profile = profile;
cfg.seed = 20261124;          % Fresh independent seed set (distinct from 20261116)
cfg.bootstrap_seed = 20261125;
cfg.bootstrap_repeats = 4000;

% ---- Full-scale physical & OFDM parameters (inherited from Stage 3) ----
cfg.c = 3e8;
cfg.fc = 28e9;
cfg.lambda = cfg.c / cfg.fc;
cfg.d = cfg.lambda / 2;
cfg.delta_f = 120e3;
cfg.T_sym = 1 / cfg.delta_f;
cfg.T_cp = 0.6e-6;
cfg.Ts = cfg.T_sym + cfg.T_cp;
cfg.N = 12672;                % Full subcarriers (B = 1.52064 GHz)
cfg.K_coarse = 256;           % Coarse stage total symbols (81 LoS + 175 NLoS = 256)
cfg.K_coarse_los = 81;
cfg.K_coarse_nlos = 175;
cfg.S_coarse_side = 5;        % 5x5 = 25 coarse RIS beams (7 sym/beam = 175 sym, covers +/-7.0 deg)
cfg.S_coarse = cfg.S_coarse_side^2;
cfg.K_fine = 256;             % Fine stage total symbols (8 configs x 32 sym)
cfg.S_fine = 8;               % Time-multiplexed fine RIS configurations
cfg.B = cfg.N * cfg.delta_f;
cfg.fref = cfg.fc - floor(cfg.N / 2) * cfg.delta_f;
cfg.resolution = cfg.c / (2 * cfg.B);

% Arrays & RIS (Pure passive 32x32 = 1024, 2-bit quantized)
cfg.Ntx = 4; cfg.Nty = 4; cfg.Nt = 16;
cfg.Mx = 8;  cfg.My = 8;  cfg.Mr = 64;
cfg.ris_side = 32;
cfg.N_ris = cfg.ris_side^2;
cfg.ris_bits = 2;
cfg.ris_aperture_m = cfg.ris_side * cfg.d;
cfg.ris_diagonal_m = sqrt(2) * cfg.ris_aperture_m;
cfg.fraunhofer_m = 2 * cfg.ris_diagonal_m^2 / cfg.lambda; % ~11.0 m (diagonal D)
cfg.far_field_min_m = 14.0;   % Strictly > 1.27 * D_F

% Power, thermal noise & communication constraints
cfg.power_w = 1.0;            % 1 W (30 dBm) total average radiated power
cfg.temperature_k = 290.0;
cfg.noise_figure_db = 7.0;
cfg.noise_w = 1.380649e-23 * cfg.temperature_k * cfg.B * 10^(cfg.noise_figure_db / 10);
cfg.U = 2;                    % Two ground communication users
cfg.Q = 2;                    % Two stationary ground sensing targets (v_q = 0)
cfg.comm_sinr_db = [10.0, 10.0];
cfg.comm_gamma = 10.^(cfg.comm_sinr_db / 10);

% Detection margin hard constraint (P_fa = 1e-6 -> ~11.4 dB threshold, P_d >= 0.99 -> ~15.5 dB)
cfg.pfa_target = 1e-6;
cfg.det_threshold_linear = -log(cfg.pfa_target); % 13.8155 (~11.40 dB)
cfg.det_snr_min_db = 14.5;    % Required single-beam SNR for reliable capture
cfg.det_margin_db = 2.0;      % Optimization margin (target >= 16.5 dB when feasible)

% Wideband model & delay-window fine compression
cfg.wideband = true;          % True frequency-dependent steering (ablation toggles false)
cfg.freq_knots = 16;          % Gauss-Legendre / Chebyshev knots (< 1e-12 accuracy, 2x faster)
cfg.delay_half_bins = 4;      % +/-4 bins (9 bins ~ 0.9 m) lossless delay window
cfg.fine_iterations = 12;

% ---- 3GPP UMi 300 m Urban Street Canyon Geometry (ZERO artificial no-fly box) ----
% Main avenue: x in [-20, 0], y in [-160, 160]
% East buildings (30 m tall): south wing y <= -6, north wing y >= +6
% Side alley (12 m wide): x in [0, 40], y in [-6, +6]
cfg.buildings = struct( ...
    'bmin', { [0, -180, 0], [0, 6, 0] }, ...
    'bmax', { [70, -6, 30], [70, 180, 30] } );
cfg.ris_pos = [-20.0; 0.0; 12.0];   % Mounted on West facade opposite side alley
cfg.ris_normal = [1.0; 0.0; 0.0];   % Facing +x into main street & side alley
cfg.z_bounds = [14.0, 24.0];        % Urban street-canyon altitude below 30 m rooflines
cfg.wall_clearance_m = 2.0;         % Physical building wall safety margin

% Random scene distributions (300 independent scenes)
% Two MU-MIMO users in the active South/North urban block: near-block user & far-block user
% (naturally separated along the street so a well-positioned UAV resolves them in 3D elevation!).
cfg.mc = 300;
cfg.rcs_m2 = [10, 30, 100];
cfg.primary_rcs_m2 = 30;
cfg.user1_y_abs_range = [38.0, 58.0];  % Mid-block sidewalk user (West curb)
cfg.user2_y_abs_range = [126.0, 152.0]; % Far-block avenue user (East curb, 3GPP UMi ~150 m half-ISD!)
cfg.user_x_range = [-18.0, -2.0];
cfg.t1_y_abs_range = [75.0, 115.0];    % LoS target in active avenue block
cfg.t2_x_range = [4.0, 12.0];          % Recessed Side-Alley target (NLoS when UAV tethered)
cfg.t2_y_range = [-4.0, 4.0];
cfg.prior_sigma_m = 2.0;            % Tracking/re-acquisition prior (ablation: 1/2/4 m)
cfg.coarse_beam_step_deg = 2.8;     % 4x4 grid -> 11.2 deg x 11.2 deg (~+/-3.4 m at 35 m)

% Scale-invariant & legacy accuracy thresholds
cfg.rel_error_limit = 0.02;         % < 2% of target-anchor range
cfg.abs_error_limit_m = 1.0;        % < 1.0 m high-precision threshold
cfg.legacy_error_limit_m = 5.0;     % Legacy Stage-3 compatibility threshold

% Methods (8 comprehensive baselines)
cfg.methods = { ...
    'FixedOpt_NoRIS', ...
    'FixedOpt_RIS', ...
    'FixedOpt_RandomRIS', ...
    'OnlineUAV_NoRIS', ...
    'MatchedPos_NoRIS', ...
    'GridSelect_RIS', ...
    'Lit_EnergyMax_AO', ...
    'Proposed_Joint_CRB'};

% Optimization hyperparameters
cfg.bcd_outer_iters = 4;
cfg.sca_beam_iters = 5;
cfg.ris_grad_iters = 12;
cfg.pos_opt_iters = 10;

if strcmp(profile, 'pilot')
    cfg.mc = 3;
elseif strcmp(profile, 'smoke')
    cfg.mc = 2;
    cfg.rcs_m2 = [30];
elseif ~strcmp(profile, 'full')
    error('Unknown profile: %s', profile);
end
end
