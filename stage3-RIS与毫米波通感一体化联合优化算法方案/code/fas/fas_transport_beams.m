function candidate=fas_transport_beams(initial,oldp,newp,design)
% Match coarse target/RIS/user responses using the new geometry, then apply
% the same total power limit. This avoids trapping port search at tight QoS.
old=responses(initial,oldp,design); next=responses(initial,newp,design);
candidate=design;
for s=1:numel(design)
    W=lsqminnorm(next{s}',old{s}'*design{s}.W,1e-10);
    magnitude=norm(W,'fro');
    if magnitude>1e-12, candidate{s}.W=W/magnitude; end
end
end

function A=responses(initial,p,design)
g=channel_geometry(initial,p);
z=[p.user_R(:),zeros(p.K_stream,1),p.user_theta(:),p.user_phi(:)];
u=channel_geometry(z,p);
u.V=u.V.*exp(-1j*2*pi*p.fc/p.c*(norm(p.ris_pos)+u.rr-p.user_R(:).'));
A=cell(size(design));
for s=1:numel(design)
    H=u.transmit+u.to_ris*conj(design{s}.phase.'*u.V);
    if isfield(p,'ris_enabled') && ~p.ris_enabled
        A{s}=[g.transmit,H]; % No unused RIS-feed constraint on the no-RIS control.
    else
        A{s}=[g.transmit,g.to_ris,H];
    end
end
end
