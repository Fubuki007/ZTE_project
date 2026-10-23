function valid=fas_positions_valid(positions,p,options)
% Same xy footprint as the supplied 4x4 half-wavelength array.
bound=p.d*[p.Ntx-1,p.Nty-1,0]; tol=1e-10*p.lambda;
valid=isequal(size(positions),[p.Ntx*p.Nty,3]) && ...
    all(isfinite(positions),'all') && all(positions>=-tol,'all') && ...
    all(positions<=bound+tol,'all');
if ~valid, return; end
dx=positions(:,1)-positions(:,1).'; dy=positions(:,2)-positions(:,2).';
dist=sqrt(dx.^2+dy.^2); dist(1:size(dist,1)+1:end)=inf;
valid=min(dist,[],'all')>=options.min_spacing_lambda*p.lambda-tol;
end
