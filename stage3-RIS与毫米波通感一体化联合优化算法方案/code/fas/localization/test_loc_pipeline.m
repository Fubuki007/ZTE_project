function test_loc_pipeline(output)
root=fileparts(mfilename('fullpath')); code=fileparts(fileparts(root));
previous=pwd; cleanup=onCleanup(@() cd(previous)); cd(code); addpath(root,fileparts(root),code); maxNumCompThreads(2);
options=fas_options('smoke'); old=fas_run_case(options,0,2); assert(old.locked);
settings=struct('iterations',5,'ris_rounds',0,'oracle',false);
result=loc_case(old,settings); assert(all(isfinite(result.position_errors),'all'));
assert(all(result.feasible));
assert(result.search{2}.peb<=result.search{1}.peb*(1+1e-8),'FAS lost its fixed-array incumbent.');
assert(isequal(result.position_errors(:,1),old.position_errors(:,2)));
assert(isequal(result.position_errors(:,2),old.position_errors(:,6)));
assert(isequal(result.position_errors(:,3),old.position_errors(:,4)));
evidence=struct('passed',true,'profile','smoke','methods',{result.methods}, ...
    'peb',result.peb,'position_rmse',sqrt(mean(result.position_errors.^2,1)),'seconds',result.seconds);
if nargin>0, fas_write_json(output,evidence); end
disp(evidence);
end
