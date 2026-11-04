function c=paper_target(c,z)
p=c.p; u=[sind(z(3))*cosd(z(4));sind(z(3))*sind(z(4));cosd(z(3))];
position=z(1)*u; r=position-c.ris_pos; rr=norm(r); ur=r/rr;
c.z=z; c.u=u; c.arx=exp(1j*2*pi*c.rx*u);
c.a=exp(1j*2*pi*c.ris_offsets*ur);
c.distance=[2*z(1),2*(norm(c.ris_pos)+rr)];
c.doppler=[2*z(2),2*z(2)*dot(u,ur)]/p.lambda;
end
