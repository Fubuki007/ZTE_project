% Standalone MATLAB allocator/FFT exercise without any RIS/project functions.
fprintf('MINIMAL_HEAP_BEGIN %s\n',char(datetime('now')));
rng(20261009,'twister');
for k = 1:32
    A = complex(randn(64,12672,16),randn(64,12672,16));
    power = mean(abs(A(:)).^2);
    assert(isfinite(power) && abs(power-2)<0.01,'Unexpected random-array power.');
    F = fft(A,[],2);
    assert(all(isfinite(F(1:128))),'Unexpected FFT result.');
    clear A F;
    fprintf('HEAP_PROGRESS=%d power=%.9g\n',k,power);
    pause(3);
end
fprintf('MINIMAL_HEAP_COMPLETE %s\n',char(datetime('now')));
