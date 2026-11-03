function test_loc_search(output)
root=fileparts(mfilename('fullpath')); code=fileparts(fileparts(root));
previous=pwd; cleanup=onCleanup(@() cd(previous)); cd(code); addpath(root,fileparts(root),code);
maxNumCompThreads(2); options=fas_options('smoke'); p=fas_parameters(options,0,10); p.ris_enabled=true;
[p,d,info]=fas_optimize_array(p.truth,p,options,false); assert(info.feasible);
[obs,~]=fas_fine_observations(p.truth,p,0,321);
cache=loc_information_cache(p.truth,p,obs,ones(p.Q,1));
w=[d{1}.W(:);d{2}.W(:)]; x=[real(w);imag(w);reshape(p.tx_positions(:,1:2)/p.lambda,[],1)];
phase=cellfun(@(a) a.phase,d,'UniformOutput',false); [~,~,G]=loc_constraints(x,p,phase,true,p.tx_positions);
numerical=zeros(size(G)); h=1e-6;
for k=1:numel(x)
    xp=x; xm=x; xp(k)=xp(k)+h; xm(k)=xm(k)-h;
    numerical(k,:)=(loc_constraints(xp,p,phase,true,p.tx_positions)-loc_constraints(xm,p,phase,true,p.tx_positions)).'/(2*h);
end
constraint_gradient_error=norm(G-numerical,'fro')/norm(numerical,'fro');
assert(constraint_gradient_error<1e-7);
starts={struct('positions',p.tx_positions,'design',{d})};
settings=struct('iterations',5,'ris_rounds',1); baseline=loc_information(cache,p.tx_positions,d);
[pf,df,inf]=loc_search(cache,starts,false,settings);
[pm,dm,inm]=loc_search(cache,starts,true,settings);
assert(norm(pf-p.tx_positions,'fro')==0);
assert(inf.peb<=baseline*(1+1e-10) && inm.peb<=baseline*(1+1e-10));
assert(fas_positions_valid(pm,p,options));
assert(max(abs(pm/p.lambda/.1-round(pm/p.lambda/.1)),[],'all')<1e-8);
pc=p; pc.tx_positions=pm; [~,feasible]=fas_design_score(p.truth,pc,dm); assert(feasible);
for s=1:2, assert(norm(df{s}.W,'fro')<=1+1e-6 && norm(dm{s}.W,'fro')<=1+1e-6); end
evidence=struct('passed',true,'profile','smoke','constraint_gradient_relative_error',constraint_gradient_error, ...
    'initial_peb',baseline,'fixed_peb',inf.peb,'fas_peb',inm.peb,'fas_continuous_peb',inm.continuous_peb, ...
    'fixed_seconds',inf.seconds,'fas_seconds',inm.seconds,'settings',settings);
if nargin>0, fas_write_json(output,evidence); end
disp(evidence);
end
