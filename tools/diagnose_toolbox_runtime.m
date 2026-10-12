function diagnose_toolbox_runtime
% Minimal runtime isolation: no project code, large arrays or parallel pool.
mode=getenv('RIS_DIAG_MODE');
fprintf('ISOLATION_BEGIN mode=%s time=%s\n',mode,datestr(now,30));
switch mode
    case 'base'
        w=0.5*(1-cos(2*pi*(0:255)'/256));
    case 'signal'
        w=hann(256,'periodic');
    case 'comm'
        w=qammod((0:15)',16,'UnitAveragePower',true);
    otherwise
        error('Unknown isolation mode.');
end
assert(all(isfinite(w)));
fprintf('TRIGGER_RETURNED mode=%s time=%s\n',mode,datestr(now,30));
for k=1:36
    pause(5);
    fprintf('ISOLATION_HEARTBEAT mode=%s step=%d time=%s\n',mode,k,datestr(now,30));
end
fprintf('ISOLATION_COMPLETE mode=%s time=%s\n',mode,datestr(now,30));
end
