function r=paper_case(p,trial,rice_db,settings,notify)
if nargin<5, notify=@(s) []; end
t=tic; seed=2026110400+trial; c=paper_scene(p,seed,rice_db);
r=struct('trial',trial,'seed',seed,'rice_db',rice_db,'p',p,'scene',c, ...
    'methods',{{'Fixed_uniform_RIS','Fixed_edge_RIS','Fixed_best_RIS_refined','FAS_RIS_guard0','FAS_RIS_guard4', ...
    'Fixed_uniform_noRIS','FAS_noRIS_guard0','FAS_noRIS_guard4'}});
notify('fixed uniform RIS'); du=paper_design(c,c.uniform,false,settings);
if p.Ntx==4 && p.Nty==4
    [x,y]=ndgrid([0 .4 1.1 1.5]); edge=[x(:),y(:)];
else, edge=c.uniform; end
notify('fixed nonuniform RIS'); de=paper_design(c,edge,false,settings);
incumbent=du; if de.score>du.score, incumbent=de; end
notify('fixed best layout matched extra rounds'); dc=paper_design(c,incumbent.X,false,settings,incumbent);
notify('FAS RIS'); df=paper_design(c,incumbent.X,true,settings,incumbent);
r.attempted_fas=df; r.retained_refined_fixed=dc.score>df.score;
if dc.score>df.score, df=dc; end % Retain the matched fixed-design incumbent.
off=c; off.reflected=0;
notify('fixed noRIS'); dn=paper_design(off,c.uniform,false,settings);
notify('FAS noRIS'); da=paper_design(off,c.uniform,true,settings,dn);
r.design={du,de,dc,df,dn,da}; index=[1 2 3 4 4 5 6 6]; guards=[0 0 0 0 4 0 0 4];
r.snr_db=zeros(1,8); r.net_energy_snr_db=zeros(1,8); r.peb=inf(1,8); r.sinr=zeros(1,8);
for m=1:8
    cc=c; if m>5, cc=off; end
    d=r.design{index(m)}; b=paper_controls(cc,d.X,d.v,d.w);
    r.snr_db(m)=10*log10(b.score/cc.radar_noise);
    r.net_energy_snr_db(m)=r.snr_db(m)+10*log10((p.K-guards(m))/p.K);
    [r.peb(m),info]=paper_information(cc,d,guards(m)); r.information{m}=info;
    r.sinr(m)=abs(b.h'*d.w)^2/cc.comm_noise;
end
assert(df.score>=dc.score*(1-1e-8) && da.score>=dn.score*(1-1e-8));
r.seconds=toc(t); notify(sprintf('case ready seconds=%.1f',r.seconds));
end
