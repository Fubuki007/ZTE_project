function [projected,clean]=uav_echo(p,o,d,standard_noise)
% Same DD/RD/DR/RR synthesis as ris_sensing; physical amplitude set in p.alpha.
Y=zeros(p.Mx*p.My,size(o.symbol,2));
for q=1:p.Q
    g=channel_geometry(p.truth(q,:),p);
    illumination=[g.transmit';g.to_ris']*d.W;
    c=(d.phase.'*g.V)*exp(-1j*2*pi*p.fref/p.c*(norm(p.ris_pos)+g.rr-p.truth(q,1)));
    phase=exp(-1j*2*pi*p.delta_f/p.c*o.n_grid*g.distance+1j*2*pi*o.time_grid*g.doppler);
    signal=(illumination*o.symbol).';
    wave=[phase(:,1).*signal(:,1)+c*phase(:,2).*signal(:,2), ...
        c*phase(:,2).*signal(:,1)+c^2*phase(:,3).*signal(:,2)];
    Y=Y+p.alpha(q)*[g.receive,g.from_ris]*wave.';
end
clean=reshape(Y*conj(o.B),[],1);
projected=reshape((Y+sqrt(p.noise_power)*standard_noise)*conj(o.B),[],1);
end
