function report=paper_scene_components(result_root,output)
% Read saved full-run checkpoints; no new channel draws or optimization.
manifest=jsondecode(fileread(fullfile(result_root,'manifest.json')));
verification=jsondecode(fileread(fullfile(result_root,'verification.json')));
assert(verification.complete && verification.count==900 && manifest.mc==300);
assert(strcmp(verification.manifest_id,manifest.id));
files=dir(fullfile(result_root,'samples','rice_*_mc_*.mat')); assert(numel(files)==900);
rows=cell(900*8,14); cursor=0; maximum_error=0; seen=false(300,3);
guards=[0 0 0 0 4 0 0 4]; design_index=[1 2 3 4 4 5 6 6];
for k=1:numel(files)
    a=load(fullfile(files(k).folder,files(k).name),'result','manifest_id'); r=a.result;
    assert(strcmp(a.manifest_id,manifest.id));
    assert(~seen(r.trial+1,r.rice_index)); seen(r.trial+1,r.rice_index)=true;
    p=r.p; assert(p.N==12672 && p.K==256 && p.Ntx*p.Nty==16 && p.Mx*p.My==64 && p.ris_side^2==256);
    symbols=round(linspace(0,p.K-1,min(p.K,p.fine_l)));
    for m=1:8
        count=min(p.N,p.fine_n)*sum(symbols>=guards(m));
        info=r.information{m}; K=info.gram; covariance=info.covariance;
        direct=real(K(1,1))/count; reflected=real(K(2,2))/count;
        radial=sqrt(max(0,covariance(1,1)));
        angular=sqrt(max(0,(r.scene.z(1)*pi/180)^2*(covariance(3,3)+sind(r.scene.z(3))^2*covariance(4,4))));
        reconstructed=hypot(radial,angular);
        err=abs(reconstructed-r.peb(m))/max(r.peb(m),realmin);
        assert(err<1e-7); maximum_error=max(maximum_error,err);
        d=r.design{design_index(m)};
        moved=norm(d.X-r.design{3}.X,'fro');
        cursor=cursor+1;
        rows(cursor,:)={r.trial,r.rice_index,r.methods{m},direct,reflected,10*log10(reflected/direct), ...
            radial,angular,r.peb(m),moved,r.retained_refined_fixed, ...
            norm(r.attempted_fas.X-r.design{3}.X,'fro'),r.attempted_fas.seconds,count};
    end
end
assert(all(seen,'all') && cursor==7200);
if ~exist(output,'dir'), mkdir(output); end
writetable(cell2table(rows,'VariableNames',{'trial','rice_index','method','direct_power','RIS_power','RIS_direct_ratio_db', ...
    'radial_bound_m','angular_bound_m','peb_m','distance_from_refined_fixed_lambda','retained_fixed_incumbent', ...
    'attempted_FAS_distance_lambda','attempted_FAS_seconds','sample_count'}),fullfile(output,'components.csv'));
report=struct('complete',true,'manifest_id',manifest.id,'count',900,'rows',cursor, ...
    'maximum_peb_decomposition_error',maximum_error,'new_simulation_or_optimization',false);
file=fopen(fullfile(output,'components_verification.json'),'w'); assert(file>=0);
fprintf(file,'%s\n',jsonencode(report)); fclose(file); disp(report);
end
