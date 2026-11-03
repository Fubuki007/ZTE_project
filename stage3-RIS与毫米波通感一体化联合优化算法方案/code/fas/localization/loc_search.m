function [positions,design,info]=loc_search(cache,starts,movable,options,notify)
% Full-footprint continuous reference search, followed by legal 0.1-lambda
% port selection and beam refinement. Both controls receive equal rounds.
if nargin<5, notify=@(s) []; end
p=cache.p; Nt=p.Ntx*p.Nty; U=p.K_stream; n=2*Nt*U; t=tic;
best=Inf; continuous=Inf; evaluations=0; runs=struct([]);
positions=starts{1}.positions; design=starts{1}.design;
for start=1:numel(starts)
    pp=starts{start}.positions; dd=starts{start}.design;
    [pp,dd,value,trace]=solve(pp,dd,movable);
    for phase_round=1:options.ris_rounds
        levels=exp(1j*2*pi*(0:2^p.ris_bits-1)/2^p.ris_bits);
        for s=1:2
            for element=1:numel(dd{s}.phase)
                chosen=dd{s}.phase(element);
                for phase_value=levels
                    candidate=dd; candidate{s}.phase(element)=phase_value;
                    if ~feasible(pp,candidate), continue; end
                    v=loc_information(cache,pp,candidate); evaluations=evaluations+1;
                    if v<value*(1-1e-10), chosen=phase_value; value=v; end
                end
                dd{s}.phase(element)=chosen;
            end
        end
        [pp,dd,value,extra]=solve(pp,dd,movable); trace=[trace;extra];
    end
    if value<continuous, continuous=value; continuous_positions=pp; end
    if movable, pp=snap_ports(pp); end
    [pp,dd,value,extra]=solve(pp,dd,false); trace=[trace;extra];
    % Retain original legal starts if rounding or a local optimizer fails.
    base=starts{start}; basevalue=loc_information(cache,base.positions,base.design);
    if feasible(base.positions,base.design) && basevalue<value
        pp=base.positions; dd=base.design; value=basevalue;
    end
    if value<best && feasible(pp,dd), best=value; positions=pp; design=dd; end
    runs(start).trace=trace; runs(start).grid_peb=value;
    notify(sprintf('localization search start %d/%d; PEB %.6g',start,numel(starts),best));
end
assert(isfinite(best) && feasible(positions,design),'Reference search failed to retain a feasible incumbent.');
if movable
    assert(max(abs(positions/p.lambda/.1-round(positions/p.lambda/.1)),[],'all')<1e-8);
end
info=struct('peb',best,'continuous_peb',continuous,'continuous_positions',continuous_positions, ...
    'runs',runs,'evaluations',evaluations,'seconds',toc(t),'positions',positions);

    function [pp,dd,bestvalue,record]=solve(pp,dd,move)
        phase=cellfun(@(d) d.phase,dd,'UniformOutput',false);
        x0=pack(pp,dd,move); lower=-ones(size(x0)); upper=ones(size(x0));
        if move
            lower(2*n+1:end)=0;
            upper(2*n+(1:Nt))=(p.Ntx-1)/2; upper(2*n+Nt+(1:Nt))=(p.Nty-1)/2;
        end
        fixed=pp; template=dd; chosen=x0; bestvalue=Inf; accepted=[];
        if feasible(pp,dd), bestvalue=loc_information(cache,pp,dd); end
        opts=optimoptions('fmincon','Algorithm','sqp','Display','none', ...
            'SpecifyObjectiveGradient',true,'SpecifyConstraintGradient',true, ...
            'MaxIterations',options.iterations,'MaxFunctionEvaluations',options.iterations*20, ...
            'ConstraintTolerance',1e-8,'OptimalityTolerance',1e-5,'StepTolerance',1e-8,'OutputFcn',@keep);
        [~,~,flag,details]=fmincon(@objective,x0,[],[],[],[],lower,upper,@constraints,opts);
        [pp,dd]=unpack(chosen,move,fixed,template);
        record=struct('movable',move,'exitflag',flag,'iterations',details.iterations, ...
            'funcCount',details.funcCount,'best_peb',bestvalue,'accepted_peb',accepted);
        function [value,gradient]=objective(x)
            [pc,dc]=unpack(x,move,fixed,template);
            [value,~,g]=loc_information(cache,pc,dc); evaluations=evaluations+1;
            if ~isfinite(value), value=1e6; gradient=zeros(size(x)); return; end
            value=log(value); gw=[g.W{1}(:);g.W{2}(:)]; gradient=[real(gw);imag(gw)];
            if move, gradient=[gradient;reshape(g.positions_lambda(:,1:2),[],1)]; end
        end
        function [c,ceq,G,Geq]=constraints(x)
            [c,ceq,G,Geq]=loc_constraints(x,p,phase,move,fixed);
        end
        function stop=keep(x,~,~)
            stop=false; [pc,dc]=unpack(x,move,fixed,template);
            if feasible(pc,dc)
                v=loc_information(cache,pc,dc);
                if v<bestvalue, chosen=x; bestvalue=v; accepted(end+1)=v; end
            end
        end
    end
    function x=pack(pp,dd,move)
        w=[dd{1}.W(:);dd{2}.W(:)]; x=[real(w);imag(w)];
        if move, x=[x;reshape(pp(:,1:2)/p.lambda,[],1)]; end
    end
    function [pp,dd]=unpack(x,move,fixed,template)
        w=reshape(x(1:n)+1j*x(n+(1:n)),Nt,U,2); pp=fixed; dd=template;
        for ss=1:2, dd{ss}.W=w(:,:,ss); end
        if move, pp=[reshape(x(2*n+1:end),Nt,2),zeros(Nt,1)]*p.lambda; end
    end
    function ok=feasible(pp,dd)
        opt=fas_options('full'); pc=p; pc.tx_positions=pp;
        ok=fas_positions_valid(pp,p,opt);
        if ok, [~,ok]=fas_design_score(cache.z,pc,dd); end
    end
    function pp=snap_ports(pp)
        [gx,gy]=ndgrid(0:.1:(p.Ntx-1)/2,0:.1:(p.Nty-1)/2);
        grid=[gx(:),gy(:)]; xy=pp(:,1:2)/p.lambda; selected=[]; bestdistance=Inf;
        for shift=0:Nt-1
            order=circshift(1:Nt,shift); current=nan(Nt,2); used=[];
            for antenna=order
                distance=sum((grid-xy(antenna,:)).^2,2);
                for k=used
                    distance(sum((grid-current(k,:)).^2,2)<.4^2-1e-12)=Inf;
                end
                [nearest,index]=min(distance); if ~isfinite(nearest), break; end
                current(antenna,:)=grid(index,:); used(end+1)=antenna;
            end
            if numel(used)==Nt
                distance=sum((current-xy).^2,'all');
                if distance<bestdistance, selected=current; bestdistance=distance; end
            end
        end
        if isempty(selected), pp=starts{1}.positions; else, pp=[selected,zeros(Nt,1)]*p.lambda; end
    end
end
