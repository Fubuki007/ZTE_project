function [obs,noise]=fas_fine_observations(initial,p,guard,seed)
% Preserve the original 256 x 64 fine subsampling. Guard removes samples;
% it never compresses the physical clock or replaces missing observations.
times=round(linspace(0,p.K-1,min(p.K,p.fine_l))); N=min(p.N,p.fine_n);
obs=cell(2,1); noise=cell(2,1); levels=[-3 -1 1 3]/sqrt(10);
for s=1:2
    fulltimes=times(s:2:end); keep=fulltimes>=guard;
    assert(any(keep),'Guard leaves one pattern without samples.');
    rng(seed+s,'twister');
    S=levels(randi(4,p.K_stream,N*numel(fulltimes)))+1j*levels(randi(4,p.K_stream,N*numel(fulltimes)));
    E=(randn(p.Mx*p.My,N*numel(fulltimes))+1j*randn(p.Mx*p.My,N*numel(fulltimes)))/sqrt(2);
    columns=reshape(1:N*numel(fulltimes),N,[]); columns=columns(:,keep);
    % Absolute times start after the common coarse stage.
    obs{s}=prepare_ris_observation(initial,p,p.K+fulltimes(keep),S(:,columns(:)));
    noise{s}=E(:,columns(:));
end
end
