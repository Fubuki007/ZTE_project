function evidence=test_path_reliability(output)
root=fileparts(mfilename('fullpath')); code=fileparts(root); cd(code);
addpath(root,code,fullfile(code,'fas'),fullfile(code,'fas','localization')); maxNumCompThreads(2);
t=tic; options=fas_options('smoke'); old=fas_run_case(options,0,2,@(s) []); assert(old.locked);
localized=loc_case(old,struct('iterations',5,'ris_rounds',0,'oracle',false),@(s) []);
result=pr_case(old,localized,struct('no_ris_iterations',5),@(s) []);
assert(all(result.feasible) && all(result.baseline_feasible));
p=old.p; p.ris_enabled=true; p.tx_positions=old.design_info{2}.positions; d=old.design{2};
[obs,noise]=fas_fine_observations(old.coarse,p,0,old.seed+20);
D=pr_dictionary(old.coarse,obs,d,p,false); bank=result.banks{1};
% Only the function name and trailing whitespace differ from Stage-3.
text=fileread(fullfile(code,'refine_ris_parameters.m'));
start=strfind(text,'function [D,derivatives] = path_dictionary(');
expected=strrep(text(start(1):end),'function [D,derivatives] = path_dictionary(', ...
    'function [D,derivatives] = pr_dictionary(');
canonical=@(s) strtrim(regexprep(strrep(s,sprintf('\r\n'),newline),'[ \t]+(?=\n)',''));
assert(strcmp(canonical(expected),canonical(fileread(fullfile(root,'pr_dictionary.m')))));
yy=cell(2,1); for s=1:2, yy{s}=fas_echo(p,obs{s},d{s},old.noise_power,noise{s}); end
y=vertcat(yy{:}); [native,native_info]=refine_ris_parameters(y,obs,d,old.coarse,p);
normal=bank.estimates(:,:,8); normalization_error=max(abs(native-normal),[],'all');
assert(normalization_error<1e-5,'Column normalization changed the full-model reference materially.');
% Joint signal/noise scaling must not alter normalized masks or shrinkage.
[scaled,scaled_fit]=pr_refine(3*y,obs,d,old.coarse,p,9*old.noise_power,ones(1,4),1);
[unscaled,unscaled_fit]=pr_refine(y,obs,d,old.coarse,p,old.noise_power,ones(1,4),1);
assert(max(abs(scaled-unscaled),[],'all')<1e-5);
assert(abs(scaled_fit.rss_whitened-unscaled_fit.rss_whitened)<1e-6*max(1,unscaled_fit.rss_whitened));
% Selectors must reproduce their recorded AIC/BIC/GCV minima without truth.
[~,ia]=min(cellfun(@(f) f.aic,bank.fits(1:8))); [~,ib]=min(cellfun(@(f) f.bic,bank.fits(1:8)));
assert(isequal(bank.choice(3:4),[ia ib]));
% Independently differentiate the profiled ridge cost, with its penalty rows.
[D,J]=pr_dictionary(old.coarse,obs,d,p,true); sigma=sqrt(old.noise_power);
normalizer=vecnorm(D)/sigma; penalty=double(mod(0:4*p.Q-1,4)~=0);
A=[D/sigma./normalizer;diag(penalty)]; target=[y/sigma;zeros(4*p.Q,1)];
inverse=pinv(A,1e-12*norm(A,2)); beta=inverse*target; residual=target-A*beta;
alpha=beta./normalizer.'; maximum_gradient_error=0;
for parameter=1:4
    derivative=J{1,parameter}*alpha(1:4)/sigma;
    derivative=[derivative;zeros(4*p.Q,1)]; derivative=derivative-A*(inverse*derivative);
    analytic=-2*real(derivative'*residual); h=[1e-4 1e-3 1e-4 1e-4]; costs=zeros(1,2);
    for side=1:2
        z=old.coarse; z(1,parameter)=z(1,parameter)+(2*side-3)*h(parameter);
        Ds=pr_dictionary(z,obs,d,p,false); As=[Ds/sigma./normalizer;diag(penalty)];
        rs=target-As*(pinv(As,1e-12*norm(As,2))*target); costs(side)=real(rs'*rs);
    end
    numeric=(costs(2)-costs(1))/(2*h(parameter));
    relative=abs(analytic-numeric)/max([1 abs(analytic) abs(numeric)]);
    maximum_gradient_error=max(maximum_gradient_error,relative);
end
assert(maximum_gradient_error<2e-3,'Profiled ridge gradient failed finite-difference check.');
% Unknown path gains are four independent fit variables; no true alpha is passed.
assert(size(D,2)==4*p.Q && native_info.num_paths==4);
partial=fullfile(tempdir,sprintf('ris_pr_incomplete_%d',feature('getpid')));
if ~exist(partial,'dir'), mkdir(partial); end
fas_write_json(fullfile(partial,'manifest.json'),struct('total_cases',3900));
rejected=false;
try
    aggregate_path_reliability(partial,'unused','unused');
catch err
    rejected=strcmp(err.identifier,'PR:IncompleteRun');
end
assert(rejected,'Finalization accepted or failed to recognize an incomplete run.');
evidence=struct('passed',true,'profile','reduced local smoke only','seconds',toc(t), ...
    'normalization_error',normalization_error,'legacy_errors',result.legacy_error, ...
    'ridge_gradient_relative_error',maximum_gradient_error, ...
    'incomplete_run_rejected',rejected, ...
    'methods',{result.methods},'rmse',squeeze(sqrt(mean(result.position_errors.^2,1))), ...
    'baseline_rmse',sqrt(mean(result.baseline_errors.^2,1)));
if nargin>0, fas_write_json(output,evidence); end
disp(evidence);
end
