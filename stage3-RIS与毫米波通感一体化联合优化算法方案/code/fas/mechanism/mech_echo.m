function [projected,clean]=mech_echo(p,o,d,noise_power,noise,weights)
% Original four paths with controlled, reciprocal target-link attenuation.
assert(isequal(size(weights),[1 4]) && all(weights>=0) && all(isfinite(weights)));
Y=zeros(p.Mx*p.My,size(o.symbol,2));
for q=1:p.Q
    g=channel_geometry(p.truth(q,:),p);
    illumination=[g.transmit';g.to_ris']*d.W;
    c=(d.phase.'*g.V)*exp(-1j*2*pi*p.fref/p.c*(norm(p.ris_pos)+g.rr-p.truth(q,1)));
    phase=exp(-1j*2*pi*p.delta_f/p.c*o.n_grid*g.distance+1j*2*pi*o.time_grid*g.doppler);
    signal=(illumination*o.symbol).';
    wave=[weights(1)*phase(:,1).*signal(:,1)+weights(2)*c*phase(:,2).*signal(:,2), ...
        weights(3)*c*phase(:,2).*signal(:,1)+weights(4)*c^2*phase(:,3).*signal(:,2)];
    Y=Y+p.alpha(q)*[g.receive,g.from_ris]*wave.';
end
clean=reshape(Y*conj(o.B),[],1);
projected=reshape((Y+sqrt(noise_power)*noise)*conj(o.B),[],1);
end
