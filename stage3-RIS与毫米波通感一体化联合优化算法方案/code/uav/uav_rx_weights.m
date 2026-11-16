function w=uav_rx_weights(prior,p)
% A receive beam from the same noisy location prior used for transmission.
g=channel_geometry(prior,p); a=g.receive;
assert(size(a,2)==2);
w=a(:,1)+a(:,2)*exp(-1j*angle(a(:,1)'*a(:,2)));
w=w/norm(w);
end
