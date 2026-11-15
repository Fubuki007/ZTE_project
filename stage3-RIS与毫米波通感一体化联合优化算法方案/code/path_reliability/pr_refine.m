function [z,info]=pr_refine(y,obs,design,initial,p,noise_power,mask,lambda)
% Stage-3 variable projection with a fixed path subset and amplitude ridge.
% Normalize at the common initial point, so the ridge prior does not change
% as position changes. DD is unpenalized; reflected coefficients are shrunk.
assert(noise_power>0 && lambda>=0 && numel(mask)==4 && mask(1));
Q=size(initial,1); columns=find(repmat(logical(mask(:)),Q,1));
D0=pr_dictionary(initial,obs,design,p,false);
normalizer=vecnorm(D0(:,columns))/sqrt(noise_power);
normalizer(normalizer<1e-14)=1;
penalty=sqrt(lambda)*double(mod(columns-1,4)~=0);
target=[y/sqrt(noise_power);zeros(numel(columns),1)];
z=initial; scale=repmat([.05 1 .2 .2],Q,1);
limit=repmat([max(.6,2*p.resolution),max(10,p.lambda/(p.K*p.Ts)),15,30],Q,1);
history=zeros(p.fine_iterations+1,1); accepted=0;
for iteration=1:p.fine_iterations
    [D,derivatives]=pr_dictionary(z,obs,design,p,true);
    [A,inverse,beta,residual,cost]=linear_fit(D);
    if iteration==1, history(1)=cost; end
    full_alpha=zeros(4*Q,1); full_alpha(columns)=beta./normalizer.';
    J=zeros(numel(y),4*Q);
    for q=1:Q
        block=(q-1)*4+(1:4);
        for j=1:4
            J(:,q+(j-1)*Q)=derivatives{q,j}*full_alpha(block)*scale(q,j)/sqrt(noise_power);
        end
    end
    J=[J;zeros(numel(columns),4*Q)];
    J=J-A*(inverse*J);
    step=lsqminnorm([real(J);imag(J)],[real(residual);imag(residual)]);
    dz=reshape(step,Q,4).*scale;
    for fraction=2.^-(0:11)
        candidate=z+fraction*dz;
        if any(abs(candidate-initial)>limit,'all') || any(candidate(:,1)<1) || ...
                any(candidate(:,3)<.01 | candidate(:,3)>89.99), continue; end
        Dnew=pr_dictionary(candidate,obs,design,p,false);
        [~,~,~,~,newcost]=linear_fit(Dnew);
        if newcost<cost, z=candidate; cost=newcost; accepted=accepted+1; break; end
    end
    history(iteration+1)=cost;
end
D=pr_dictionary(z,obs,design,p,false);
[A,inverse,beta,~,cost]=linear_fit(D);
X=A(1:numel(y),:); residual=y/sqrt(noise_power)-X*beta;
rss=real(residual'*residual); hat_trace=real(trace(inverse(:,1:numel(y))*X));
% shortcut: GCV uses local geometric degrees of freedom, not exact nonlinear
% risk; compare against AIC/BIC and actual RMSE before treating it as useful.
df_complex=2*Q+hat_trace; observations=numel(y);
k_real=4*Q+2*rank(X,1e-10*max(norm(X,2),realmin));
singular=svd(X,'econ'); condition=Inf;
if ~isempty(singular) && singular(end)>0, condition=singular(1)/singular(end); end
info=struct('mask',logical(mask(:).'),'lambda',lambda,'rss_whitened',rss, ...
    'penalized_cost',cost,'aic',2*rss+2*k_real,'bic',2*rss+k_real*log(2*observations), ...
    'gcv',rss/observations/max(1-df_complex/observations,eps)^2, ...
    'df_complex',df_complex,'condition',condition,'normalizer',normalizer, ...
    'alpha',beta./normalizer.', ...
    'iterations',iteration,'accepted',accepted,'cost_history',history);
assert(all(diff(history)<=1e-7*max(1,history(1))),'Penalized fit cost increased.');
assert(all(isfinite(z),'all') && isfinite(rss) && isfinite(cost));

    function [A,inverse,beta,residual,cost]=linear_fit(D)
        A=[D(:,columns)/sqrt(noise_power)./normalizer;diag(penalty)];
        inverse=pinv(A,1e-12*max(norm(A,2),realmin));
        beta=inverse*target; residual=target-A*beta; cost=real(residual'*residual);
    end
end
