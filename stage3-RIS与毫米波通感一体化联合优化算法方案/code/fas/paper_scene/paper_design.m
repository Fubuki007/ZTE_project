function d=paper_design(c,X,fluid,settings,warm)
if nargin<5, warm=[]; end
N=numel(c.a); levels=exp(1j*(0:3)*pi/2);
if c.reflected==0, v=zeros(N,1); else, v=ones(N,1); end
if ~isempty(warm), X=warm.X; v=warm.v; end
b=paper_controls(c,X,v); [w,score,ok]=paper_beam(c,b);
if ~ok
    % Build a communication-focused feasible phase seed before radar ascent.
    for k=1:3
        w=b.h/norm(b.h)*sqrt(c.power); g=b.G*w;
        v=exp(1j*pi/2*round(angle(conj(c.h1).*g)*2/pi));
        b=paper_controls(c,X,v); [w,score,ok]=paper_beam(c,b);
        if ok, break; end
    end
end
assert(ok,'No communication-feasible seed in the normalized diagnostic.');
trace=score; flags=[]; elapsed=tic;
options=optimoptions('fmincon','Algorithm','sqp','Display','off', ...
    'SpecifyObjectiveGradient',true,'SpecifyConstraintGradient',true, ...
    'MaxIterations',settings.iterations,'ConstraintTolerance',1e-8,'OptimalityTolerance',1e-7);
for round=1:settings.rounds
    if c.reflected~=0
        for n=1:N
            selected=v(n); br=b.brx; bt=b.btx; h=b.h; current=score;
            for value=levels
                delta=value-v(n); nr=br+c.Grx(n,:)'*(delta*c.a(n));
                nt=bt+b.G(n,:)'*(delta*c.a(n)); nh=h+b.G(n,:)'*(delta*c.h1(n));
                y=c.direct*c.arx*(b.atx'*w)+c.reflected*nr*(nt'*w);
                next=real(y'*y);
                if next>current && abs(nh'*w)^2>=c.gamma*c.comm_noise*(1+1e-10)
                    selected=value; current=next;
                end
            end
            delta=selected-v(n); b.brx=br+c.Grx(n,:)'*(delta*c.a(n));
            b.btx=bt+b.G(n,:)'*(delta*c.a(n)); b.h=h+b.G(n,:)'*(delta*c.h1(n));
            v(n)=selected; score=current;
        end
        b=paper_controls(c,X,v); [w,score,ok]=paper_beam(c,b); assert(ok);
    end
    if fluid
        [next,~,flag]=fmincon(@objective,X(:),[],[],[],[],zeros(numel(X),1), ...
            c.aperture*ones(numel(X),1),@constraints,options); flags(end+1)=flag;
        trial=snap(reshape(next,size(X)),c);
        if ~isempty(trial)
            nb=paper_controls(c,trial,v); [nw,ns,feasible]=paper_beam(c,nb);
            if feasible && ns>score, X=trial; b=nb; w=nw; score=ns; end
        end
    end
    assert(score>=trace(end)*(1-1e-9)); trace(end+1)=score;
end
d=struct('X',X,'v',v,'w',w,'score',score,'sinr',abs(b.h'*w)^2/c.comm_noise, ...
    'trace',trace,'flags',flags,'seconds',toc(elapsed));
    function [f,g]=objective(x)
        a=paper_controls(c,reshape(x,size(X)),v,w); f=-log(max(a.score,realmin));
        g=-a.gradient(:)/max(a.score,realmin);
    end
    function [ineq,eq,G,Geq]=constraints(x)
        xx=reshape(x,size(X)); a=paper_controls(c,xx,v,w);
        required=c.gamma*c.comm_noise; ineq=1-abs(a.comm)^2/required;
        G=-a.comm_gradient(:)/required; eq=[]; Geq=[];
        for i=1:size(X,1)
            for j=i+1:size(X,1)
                delta=xx(i,:)-xx(j,:); ineq(end+1,1)=(c.spacing+1e-6)^2-sum(delta.^2);
                g=zeros(size(X)); g(i,:)=-2*delta; g(j,:)=2*delta; G(:,end+1)=g(:);
            end
        end
    end
end

function X=snap(candidate,c)
[x,y]=ndgrid(0:c.grid:c.aperture); ports=[x(:),y(:)]; X=zeros(size(candidate));
for i=1:size(X,1)
    distance=sum((ports-candidate(i,:)).^2,2);
    if i>1
        for j=1:i-1, distance(sum((ports-X(j,:)).^2,2)<c.spacing^2-1e-10)=inf; end
    end
    [best,index]=min(distance); if ~isfinite(best), X=[]; return; end
    X(i,:)=ports(index,:);
end
end
