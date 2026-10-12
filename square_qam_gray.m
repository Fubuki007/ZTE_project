function symbols = square_qam_gray(data, M)
%SQUARE_QAM_GRAY Gray square-QAM with unit average power, using base MATLAB.
% Matches qammod(data,M,'UnitAveragePower',true) for M=4,16,64,... .
% QAM labels split into the horizontal MSBs and vertical LSBs.  Converting
% each Gray-coded coordinate to binary gives the ascending I and descending
% Q levels used by MATLAB's default constellation.
side = sqrt(M);
if ~isscalar(M) || ~isfinite(M) || M < 4 || side ~= fix(side) || ...
        log2(side) ~= fix(log2(side))
    error('RIS:QAMOrder','M must be a square power of two, at least 4.');
end
if ~isreal(data) || any(~isfinite(data(:))) || ...
        any(data(:) ~= fix(data(:))) || any(data(:) < 0 | data(:) >= M)
    error('RIS:QAMLabels','QAM labels must be integers in [0,M-1].');
end
i_coord = uint32(floor(double(data) / side));
q_coord = uint32(mod(double(data),side));
shift = 1;
while shift < log2(side)
    i_coord = bitxor(i_coord,bitshift(i_coord,-shift));
    q_coord = bitxor(q_coord,bitshift(q_coord,-shift));
    shift = 2*shift;
end
symbols = complex(2*double(i_coord)-(side-1), ...
    (side-1)-2*double(q_coord)) / sqrt((2/3)*(M-1));
end
