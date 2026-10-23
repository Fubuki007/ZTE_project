function [p,design,info]=fas_optimize_array(initial,p,options,movable)
% Geometry search only receives coarse estimates and known user channels.
t=tic; [x,y]=ndgrid(0:p.Ntx-1,0:p.Nty-1);
if ~isfield(p,'tx_positions')
    p.tx_positions=p.d*[x(:),y(:),zeros(numel(x),1)];
end
assert(fas_positions_valid(p.tx_positions,p,options));
design=cell(2,1);
for s=1:2, design{s}=optimize_ris_joint(initial,p,(s-1)*pi); end
[score,feasible]=fas_design_score(initial,p,design);
history=score; evaluations=0; moves=0; start_positions=p.tx_positions;
[dx,dy]=ndgrid(-1:1,-1:1); offsets=[dx(:),dy(:),zeros(9,1)]*options.port_step_lambda*p.lambda;
for round=1:options.position_rounds
    candidate_design=fas_transport_beams(initial,p,p,design);
    [value,ok]=fas_design_score(initial,p,candidate_design);
    if ok && value>score, design=candidate_design; score=value; feasible=true; end
    if movable && feasible
        for antenna=1:size(p.tx_positions,1)
            original=p.tx_positions(antenna,:); selected=original; best=score; selected_design=design;
            for k=1:size(offsets,1)
                candidate=p; candidate.tx_positions(antenna,:)=original+offsets(k,:);
                if ~fas_positions_valid(candidate.tx_positions,p,options), continue; end
                candidate_design=fas_transport_beams(initial,p,candidate,design);
                [value,ok]=fas_design_score(initial,candidate,candidate_design); evaluations=evaluations+1;
                if ok && value>best+1e-10
                    best=value; selected=candidate.tx_positions(antenna,:); selected_design=candidate_design;
                end
            end
            moves=moves+any(abs(selected-original)>1e-12);
            p.tx_positions(antenna,:)=selected; score=best; design=selected_design;
        end
    end
    % Fixed and FAS receive the same number of beam/RIS optimization rounds.
    for s=1:2
        design{s}=optimize_ris_joint(initial,p,(s-1)*pi,design{s});
    end
    [score,feasible]=fas_design_score(initial,p,design); history(end+1)=score;
end
[~,feasible,sinr]=fas_design_score(initial,p,design);
g=channel_geometry(initial,p);
scale=max(1e-12,p.ris_side^2*p.d^2/p.lambda*initial(:,1).'./(norm(p.ris_pos)*g.rr));
for s=1:2
    design{s}.scale=scale; design{s}.sinr=sinr(:,s);
    design{s}.feasible=feasible;
end
info=struct('objective',history,'feasible',feasible,'candidate_evaluations',evaluations, ...
    'accepted_moves',moves,'max_displacement_m',max(vecnorm(p.tx_positions-start_positions,2,2)), ...
    'seconds',toc(t),'min_sinr',min(sinr,[],2),'positions',p.tx_positions);
end
