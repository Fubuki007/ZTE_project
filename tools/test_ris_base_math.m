function test_ris_base_math
% Compare the toolbox-free mapping against the installed official functions.
for M = [4 16 64 256 1024]
    labels = reshape(0:M-1, sqrt(M), 1, sqrt(M));
    before = rng;
    actual = square_qam_gray(labels,M);
    assert(isequal(before,rng),'Mapping changed RNG.');
    expected = reshape(qammod(labels(:),M,'UnitAveragePower',true),size(labels));
    delta = max(abs(actual(:)-expected(:)));
    fprintf('QAM M=%d max_abs_error=%.17g exact=%d\n',M,delta,isequal(actual,expected));
    assert(isequal(size(actual),size(labels)) && delta <= 4*eps);
    if M == 16, assert(isequal(actual,expected),'Formal 16-QAM must match exactly.'); end
end
fprintf('BASE_MATH_TEST_COMPLETE\n');
end
