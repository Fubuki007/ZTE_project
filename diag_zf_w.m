function diag_zf_w()
clear; clc;
p=build_default_params(); p.K_stream=2;
% ensure users
p.user_theta_rad=deg2rad(p.theta_true(:)); p.user_phi_rad=deg2rad(p.phi_true(:));
p.enable_SI=false; p.precoder_type='zf';
tx=generate_mimo_ofdm_waveform(p);
disp(any(isnan(tx.H(:)))); disp(any(isnan(tx.W(:)))); disp(tx.precoder_info)
end
