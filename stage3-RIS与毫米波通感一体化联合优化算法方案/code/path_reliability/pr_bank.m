function bank=pr_bank(y,obs,design,initial,p,noise_power,notify)
% Candidate fitting and feasible choices never read test truth or path gains.
if nargin<7, notify=@(s) []; end
for field={'truth','R_true','v_true','theta_true','phi_true','alpha'}
    if isfield(p,field{1}), p=rmfield(p,field{1}); end
end
masks=[ones(8,1),bitget(repmat((0:7).',1,3),repmat(1:3,8,1))];
lambdas=[1e-6 1e-4 1e-2 1 1e2 1e4];
total=8+numel(lambdas); estimates=zeros(size(initial,1),4,total); fits=cell(1,total);
seconds=zeros(1,total);
for k=1:total
    if k<=8, mask=masks(k,:); lambda=0; else, mask=ones(1,4); lambda=lambdas(k-8); end
    t=tic; [estimates(:,:,k),fits{k}]=pr_refine(y,obs,design,initial,p,noise_power,mask,lambda);
    seconds(k)=toc(t);
    notify(sprintf('candidate %d/%d mask=%s lambda=%g seconds=%.1f',k,total,num2str(mask),lambda,seconds(k)));
end
aic=cellfun(@(f) f.aic,fits(1:8)); bic=cellfun(@(f) f.bic,fits(1:8));
ridge_indices=[8,9:total]; gcv=cellfun(@(f) f.gcv,fits(ridge_indices));
[~,ia]=min(aic); [~,ib]=min(bic); [~,ig]=min(gcv);
bank=struct('estimates',estimates,'fits',{fits},'seconds',seconds, ...
    'choice',[8,1,ia,ib,ridge_indices(ig)], ...
    'methods',{{'Full_normalized','DD_only','AIC','BIC','Ridge_GCV'}}, ...
    'masks',masks,'ridge_lambdas',lambdas);
end
