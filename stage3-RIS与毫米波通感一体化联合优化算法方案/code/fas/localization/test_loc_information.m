function test_loc_information(output)
root=fileparts(mfilename('fullpath')); code=fileparts(fileparts(root));
previous=pwd; cleanup=onCleanup(@() cd(previous)); cd(code); addpath(root,fileparts(root),code);
maxNumCompThreads(2); options=fas_options('smoke'); p=fas_parameters(options,0,10); p.ris_enabled=true;
[p,d,info]=fas_optimize_array(p.truth,p,options,true); assert(info.feasible);
[obs,~]=fas_fine_observations(p.truth,p,0,123);
t=tic; cache=loc_information_cache(p.truth,p,obs,p.alpha,true); cache_seconds=toc(t);
[peb,out]=loc_information(cache,p.tx_positions,d,1);
[~,~,gradient]=loc_information(cache,p.tx_positions,d,1);
numeric=[]; analytic=[]; h=1e-5;
for coordinate=1:2
    for antenna=1:size(p.tx_positions,1)
        plus=p.tx_positions; minus=plus;
        plus(antenna,coordinate)=plus(antenna,coordinate)+h*p.lambda;
        minus(antenna,coordinate)=minus(antenna,coordinate)-h*p.lambda;
        numeric(end+1)=(log(loc_information(cache,plus,d))-log(loc_information(cache,minus,d)))/(2*h);
        analytic(end+1)=gradient.positions_lambda(antenna,coordinate);
    end
end
for s=1:2
    for k=1:numel(d{s}.W)
        for direction=[1,1j]
            plus=d; minus=d; plus{s}.W(k)=plus{s}.W(k)+h*direction; minus{s}.W(k)=minus{s}.W(k)-h*direction;
            numeric(end+1)=(log(loc_information(cache,p.tx_positions,plus))-log(loc_information(cache,p.tx_positions,minus)))/(2*h);
            analytic(end+1)=real(conj(gradient.W{s}(k))*direction);
        end
    end
end
gradient_error=norm(numeric-analytic)/norm(numeric); assert(gradient_error<1e-5,'Control gradient is incorrect.');
D=cell(2,1); J=cell(2,1); y=cell(2,1);
for s=1:2
    D{s}=cache.left{s}*out.D{s}; J{s}=cache.left{s}*out.J_unprojected{s};
    [~,y{s}]=fas_echo(p,obs{s},d{s},0,zeros(p.Mx*p.My,size(obs{s}.symbol,2)));
end
D=vertcat(D{:}); J=vertcat(J{:}); y=vertcat(y{:});
amplitudes=repelem(p.alpha(:),4); echo_error=norm(y-D*amplitudes)/norm(y);
assert(echo_error<1e-10,'Cached dictionary disagrees with original echo.');
steps=[1e-5 1e-4 1e-5 1e-5]; numerical=zeros(size(J));
for j=1:4
    for q=1:p.Q
        plus=p; minus=p; plus.truth(q,j)=plus.truth(q,j)+steps(j); minus.truth(q,j)=minus.truth(q,j)-steps(j);
        yp=cell(2,1); ym=cell(2,1);
        for s=1:2
            noise=zeros(p.Mx*p.My,size(obs{s}.symbol,2));
            [~,yp{s}]=fas_echo(plus,obs{s},d{s},0,noise); [~,ym{s}]=fas_echo(minus,obs{s},d{s},0,noise);
        end
        numerical(:,q+(j-1)*p.Q)=(vertcat(yp{:})-vertcat(ym{:}))/(2*steps(j));
    end
end
derivative_error=norm(J-numerical,'fro')/norm(numerical,'fro');
assert(derivative_error<1e-5,'Cached derivatives disagree with physical finite differences.');
projected=numerical-D*(pinv(D,1e-10)*numerical); F=2*real(projected'*projected);
fisher_error=norm(out.F-F,'fro')/norm(F,'fro'); assert(fisher_error<1e-5);
assert(abs(loc_information(cache,p.tx_positions,d,2)/peb-sqrt(2))<1e-10);
half=d; for s=1:2, half{s}.W=half{s}.W/2; end
assert(abs(loc_information(cache,p.tx_positions,half,1)/peb-2)<1e-8);
altered=p; altered.truth(:)=999; altered.alpha(:)=999;
cache2=loc_information_cache(cache.z,altered,obs,cache.amplitudes);
assert(abs(loc_information(cache2,p.tx_positions,d)/peb-1)<1e-10,'Design cache leaked truth.');
t=tic; for k=1:100, loc_information(cache,p.tx_positions,d); end; seconds=toc(t)/100;
evidence=struct('passed',true,'profile','smoke','echo_relative_error',echo_error, ...
    'derivative_relative_error',derivative_error,'fisher_relative_error',fisher_error, ...
    'control_gradient_relative_error',gradient_error,'peb_noise1_m',peb, ...
    'cache_seconds',cache_seconds,'seconds_per_evaluation',seconds,'matlab',version);
if nargin>0, fas_write_json(output,evidence); end
disp(evidence);
end
