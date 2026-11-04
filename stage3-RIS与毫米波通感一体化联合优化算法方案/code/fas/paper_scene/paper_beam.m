function [w,score,ok]=paper_beam(c,b)
R=b.H'*b.H; R=(R+R')/2; h=b.h; required=c.gamma*c.comm_noise;
ok=c.power*real(h'*h)>=required*(1+1e-9); w=[]; score=nan;
if ~ok, return; end
scale=max(norm(R,2),realmin); R=R/scale; C=(h*h')/real(h'*h);
v=largest(R); w=sqrt(c.power)*v;
if abs(h'*w)^2<required*(1+1e-9)
    lo=0; hi=1;
    for k=1:60
        v=largest(R+hi*C);
        if c.power*abs(h'*v)^2>=required*(1+1e-9), break; end
        hi=hi*2;
    end
    for k=1:48
        mid=(lo+hi)/2; v=largest(R+mid*C);
        if c.power*abs(h'*v)^2>=required*(1+1e-9), hi=mid; else, lo=mid; end
    end
    w=sqrt(c.power)*largest(R+hi*C);
end
ok=abs(h'*w)^2>=required*(1-1e-8) && norm(w)^2<=c.power*(1+1e-8);
score=real(w'*(b.H'*b.H)*w);
end

function v=largest(A)
[V,D]=eig((A+A')/2,'vector'); [~,ix]=max(real(D)); v=V(:,ix);
end
