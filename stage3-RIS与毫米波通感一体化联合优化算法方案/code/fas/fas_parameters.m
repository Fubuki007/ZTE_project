function p=fas_parameters(options,trial,snr)
% Independent geometries per MC, paired across methods and SNR values.
rng(options.seed+trial*10000,'twister'); p=build_default_params(); p.SNR=snr;
if strcmp(options.profile,'smoke')
    p.N=1024; p.K=32; p.Mx=4; p.My=4; p.ris_side=4;
    p.coarse_n=128; p.coarse_l=32; p.fine_n=64; p.fine_l=16;
    p.fine_iterations=3; p.sca_iterations=2; p.outer_iterations=1;
end
p.B=p.N*p.delta_f; p.fref=p.fc-floor(p.N/2)*p.delta_f;
p.resolution=p.c/(2*p.B);
end
