function test_mechanism(output,fullsample)
root=fileparts(mfilename('fullpath')); code=fileparts(fileparts(root));
cd(code); addpath(code,fileparts(root),fullfile(fileparts(root),'localization'),root); maxNumCompThreads(2);
profile='smoke';
if nargin<2
    options=fas_options('smoke'); p=fas_parameters(options,0,10); p.ris_enabled=true;
    [p,d,di]=fas_optimize_array(p.truth,p,options,false); assert(di.feasible);
else
    assert(~ispc,'Full-size validation is server-only.'); a=load(fullsample,'result');
    p=a.result.p; p.ris_enabled=true; p.tx_positions=a.result.design_info{2}.positions; d=a.result.design{2};
    assert(p.N==12672 && p.K==256 && p.Mx*p.My==64); profile='server-full-size-math-check';
end
[obs,noise]=fas_fine_observations(p.truth,p,0,123);
cache=loc_information_cache(p.truth,p,obs,p.alpha,true); weights=mech_weights(40);
assert(isequal(mech_weights(0),ones(1,4)) && norm(weights-[.01 .1 .1 1])<1e-14);
base=loc_information(cache,p.tx_positions,d); cache.path_weights=ones(1,4);
assert(abs(loc_information(cache,p.tx_positions,d)/base-1)<1e-12);
cache.path_weights=.3*ones(1,4); assert(abs(loc_information(cache,p.tx_positions,d)/base-1/.3)<1e-8);
cache.path_weights=weights;
[peb,out,gradient]=loc_information(cache,p.tx_positions,d);
DD=cell(2,1); JJ=DD; yy=DD; echo_error=0;
for s=1:2
    original=fas_echo(p,obs{s},d{s},.01,noise{s});
    current=mech_echo(p,obs{s},d{s},.01,noise{s},ones(1,4));
    echo_error=max(echo_error,norm(original-current)/norm(original));
    DD{s}=cache.left{s}*out.D{s}; JJ{s}=cache.left{s}*out.J_unprojected{s};
    [~,yy{s}]=mech_echo(p,obs{s},d{s},0,noise{s},weights);
end
D=vertcat(DD{:}); J=vertcat(JJ{:}); amplitude=reshape((p.alpha(:)*weights).',[],1);
weighted_echo_error=norm(vertcat(yy{:})-D*amplitude)/norm(vertcat(yy{:}));
assert(echo_error<1e-12 && weighted_echo_error<1e-10);
steps=[1e-5 1e-4 1e-5 1e-5]; numerical=zeros(size(J));
for j=1:4
    for q=1:p.Q
        plus=p; minus=p; plus.truth(q,j)=plus.truth(q,j)+steps(j); minus.truth(q,j)=minus.truth(q,j)-steps(j);
        yp=cell(2,1); ym=yp;
        for s=1:2
            [~,yp{s}]=mech_echo(plus,obs{s},d{s},0,noise{s},weights);
            [~,ym{s}]=mech_echo(minus,obs{s},d{s},0,noise{s},weights);
        end
        numerical(:,q+(j-1)*p.Q)=(vertcat(yp{:})-vertcat(ym{:}))/(2*steps(j));
    end
end
derivative_error=norm(J-numerical,'fro')/norm(numerical,'fro'); assert(derivative_error<1e-5);
projected=numerical-D*(pinv(D,1e-10)*numerical); F=2*real(projected'*projected);
fisher_error=norm(out.F-F,'fro')/norm(F,'fro'); assert(fisher_error<1e-5);
numeric=[]; analytic=[]; h=1e-5;
for coordinate=1:2
    for antenna=1:size(p.tx_positions,1)
        plus=p.tx_positions; minus=plus; plus(antenna,coordinate)=plus(antenna,coordinate)+h*p.lambda;
        minus(antenna,coordinate)=minus(antenna,coordinate)-h*p.lambda;
        numeric(end+1)=(log(loc_information(cache,plus,d))-log(loc_information(cache,minus,d)))/(2*h);
        analytic(end+1)=gradient.positions_lambda(antenna,coordinate);
    end
end
for s=1:2
    for k=1:numel(d{s}.W)
        for direction=[1 1j]
            plus=d; minus=d; plus{s}.W(k)=plus{s}.W(k)+h*direction; minus{s}.W(k)=minus{s}.W(k)-h*direction;
            numeric(end+1)=(log(loc_information(cache,p.tx_positions,plus))-log(loc_information(cache,p.tx_positions,minus)))/(2*h);
            analytic(end+1)=real(conj(gradient.W{s}(k))*direction);
        end
    end
end
gradient_error=norm(numeric-analytic)/norm(numeric); assert(gradient_error<1e-5);
evidence=struct('passed',true,'profile',profile,'zero_loss_echo_error',echo_error, ...
    'weighted_echo_error',weighted_echo_error,'derivative_error',derivative_error,'fisher_error',fisher_error, ...
    'control_gradient_error',gradient_error,'peb',peb,'matlab',version);
if nargin>0, fas_write_json(output,evidence); end
disp(evidence);
end
