function [G_hat, info] = estimate_si_channel_ls( ...
        G_true, X_pilot, thermal_noise_std, target_nmse_db)
%ESTIMATE_SI_CHANNEL_LS Pilot-based effective SI-channel LS estimate.
% Implements scheme Eqs. (46)-(47):
%   Y_p = G_true * X_pilot + Z_p
%   G_hat = Y_p * X_pilot^H * (X_pilot * X_pilot^H)^(-1)
%
% target_nmse_db=[] uses receiver thermal noise at thermal_noise_std, as in
% the paper baseline. A finite target_nmse_db scales Z_p so that the LS
% channel-estimation error has the requested NMSE. This provides an
% auditable sensitivity model without modifying the LS or SIC equations.

if nargin < 4
    target_nmse_db = [];
end
if ~ismatrix(G_true) || ~ismatrix(X_pilot) || ...
        size(G_true, 2) ~= size(X_pilot, 1)
    error('estimate_si_channel_ls:DimensionMismatch', ...
        'G_true columns must equal X_pilot rows.');
end
if size(X_pilot, 2) < size(X_pilot, 1)
    error('estimate_si_channel_ls:InsufficientPilots', ...
        'Pilot length must be at least the number of transmit antennas.');
end
if ~isscalar(thermal_noise_std) || ~isreal(thermal_noise_std) || ...
        ~isfinite(thermal_noise_std) || thermal_noise_std < 0
    error('estimate_si_channel_ls:InvalidNoiseStd', ...
        'thermal_noise_std must be a finite nonnegative scalar.');
end
if ~isempty(target_nmse_db) && ...
        (~isscalar(target_nmse_db) || ~isreal(target_nmse_db) || ...
         isnan(target_nmse_db) || target_nmse_db > 0)
    error('estimate_si_channel_ls:InvalidTargetNmse', ...
        'target_nmse_db must be empty, -Inf, or a real scalar <= 0 dB.');
end

pilot_gram = X_pilot * X_pilot';
if rcond(pilot_gram) < 1e-12
    pilot_right_inverse = pinv(X_pilot);
else
    pilot_right_inverse = X_pilot' / pilot_gram;
end

[Nr, ~] = size(G_true);
Lp = size(X_pilot, 2);
unit_noise = randn(Nr, Lp, 'like', G_true) + ...
    1j * randn(Nr, Lp, 'like', G_true);

if isempty(target_nmse_db)
    noise_scale = thermal_noise_std;
    mode = 'paper_thermal_awgn';
    requested_nmse_db = NaN;
else
    unit_error = unit_noise * pilot_right_inverse;
    unit_error_energy = norm(unit_error, 'fro')^2;
    desired_error_energy = norm(G_true, 'fro')^2 * ...
        10^(target_nmse_db / 10);
    if desired_error_energy == 0
        noise_scale = 0;
    else
        noise_scale = sqrt(desired_error_energy / ...
            max(unit_error_energy, realmin));
    end
    mode = 'controlled_nmse';
    requested_nmse_db = target_nmse_db;
end

Z_pilot = noise_scale * unit_noise;
Y_pilot = G_true * X_pilot + Z_pilot;
G_hat = Y_pilot * pilot_right_inverse;

error_energy = norm(G_true - G_hat, 'fro')^2;
channel_energy = norm(G_true, 'fro')^2;
info = struct( ...
    'mode', mode, ...
    'requested_nmse_db', requested_nmse_db, ...
    'achieved_nmse_db', 10 * log10(max(error_energy, realmin) / ...
        max(channel_energy, realmin)), ...
    'pilot_noise_power', mean(abs(Z_pilot(:)).^2), ...
    'pilot_length', Lp, ...
    'pilot_gram_rcond', rcond(pilot_gram));
end
