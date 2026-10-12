% Report only runtime provenance; do not print credentials or license contents.
fprintf('MATLAB_VERSION=%s\n',version);
fprintf('MATLAB_ROOT=%s\n',matlabroot);
for name={'startup','matlabrc','pause','datestr','hann','qammod'}
    fprintf('RESOLVED_FUNCTION=%s\n',name{1});
    disp(which(name{1},'-all'));
end
fprintf('USER_PATH=%s\n',userpath);
fprintf('PROVENANCE_COMPLETE\n');
