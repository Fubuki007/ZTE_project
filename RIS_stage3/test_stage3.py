"""Small local mathematical checks; this never runs the full experiment."""
from dataclasses import replace
import tempfile
from pathlib import Path
import numpy as np
from scipy.optimize import minimize
from threadpoolctl import threadpool_limits
from stage3_model import Config,Model,single_user_sca
from streaming import Observation,simulate_block,coefficients


def run_tests():
    cfg=replace(Config(),ns=24,lc=8,lf=8,rx_nx=3,rx_ny=3,ris_nx=4,ris_ny=4,
                ao_iterations=1,sca_iterations=2,refinement_iterations=10)
    model=Model(cfg)
    truth=np.array(cfg.truth)
    phase=np.exp(2j*np.pi*(np.arange(len(model.ris))%4)/4)
    times=np.arange(cfg.lf)*cfg.symbol_time
    w=model.wzf
    block=(w,phase,np.ones((cfg.ns,cfg.lf)),times)
    dense=model.dictionary(truth,[block])
    f,t=model.factors(truth,w,phase,times)
    separated=(f.transpose(1,0,2)[:,:,None,:]*t[None,None,:,:]).reshape(-1,8)
    np.testing.assert_allclose(dense,separated,rtol=1e-12,atol=1e-12)
    for z in truth:
        _,_,tau,fd=model.geometry(z)
        assert abs(tau[1]-tau[2])<1e-15 and abs(tau[3]-2*tau[1]+tau[0])<1e-15
        assert abs(fd[1]-fd[2])<1e-12 and abs(fd[3]-2*fd[1]+fd[0])<1e-10
    with tempfile.TemporaryDirectory() as tmp:
        y=simulate_block(cfg,w,phase,times,0.,5,Path(tmp)/'y.npy',batch=7)
        record=dict(y=y,w=w,phase=phase,times=times)
        obs=Observation(cfg,[record],batch=7)
        gram,rhs=obs.statistics(truth)
        dy=dense@coefficients(cfg)
        np.testing.assert_allclose(gram,dense.conj().T@dense,rtol=1e-10,atol=1e-9)
        np.testing.assert_allclose(rhs,dense.conj().T@dy,rtol=1e-10,atol=1e-9)
        alpha,_,_=obs.fit(truth)
        gext,bext=obs.statistics(truth,alpha=alpha)
        # Independent full-template finite differences check projected GN math.
        jac=np.zeros((len(dy),truth.size),complex)
        steps=[.002,.005,.001,.001]
        for q in range(2):
            for j in range(4):
                plus,minus=truth.copy(),truth.copy()
                plus[q,j]+=steps[j];minus[q,j]-=steps[j]
                jac[:,q*4+j]=((model.dictionary(plus,[block])-model.dictionary(minus,[block]))@alpha)/(2*steps[j])
        full=np.column_stack((dense,jac))
        np.testing.assert_allclose(gext,full.conj().T@full,rtol=3e-6,atol=1e-5)
        np.testing.assert_allclose(bext,full.conj().T@dy,rtol=3e-6,atol=1e-5)
        start=truth+np.array([[.03,.1,.1,.1],[-.03,-.1,-.1,-.1]])
        est,info=obs.refine(start)
        assert np.max(abs(est-truth))<.005,(est,truth)
        assert np.all(np.diff(info['costs'])<=0)
        del obs,record,y
    optimized,pp,info=model.design(truth)
    assert min(info['history'])>0
    assert np.min(np.diff(info['history']))>-2e-5
    assert info['power']<=cfg.ns*(1+1e-5)
    assert info['min_sinr']>=cfg.gamma*(1-1e-4)
    np.testing.assert_allclose(np.abs(pp),1,atol=1e-12)
    phase_index=np.angle(pp)/(2*np.pi)*2**cfg.bits
    np.testing.assert_allclose(phase_index,np.rint(phase_index),atol=1e-10)
    # Independent SLSQP cross-check of a random tiny Eq. (57) subproblem.
    rng=np.random.default_rng(9)
    h=(rng.normal(size=(3,3))+1j*rng.normal(size=(3,3)))/3
    sw=rng.normal(size=(2,3,3))+1j*rng.normal(size=(2,3,3))
    constants=np.array([.2,.3])
    threshold=.01
    ww,dual=single_user_sca(sw,constants,h,threshold)
    def unpack(x):return (x[:9]+1j*x[9:18]).reshape(3,3)
    def constraints(x):
        wv=unpack(x)
        lower=2*np.real(np.einsum('qij,ij->q',sw.conj(),wv))/3-constants
        response=np.sum(h*wv,axis=1)
        return np.r_[3-np.sum(abs(wv)**2),response.real-np.sqrt(threshold),lower-x[-1]]
    initial=np.r_[ww.real.ravel(),ww.imag.ravel(),min(2*np.real(np.einsum('qij,ij->q',sw.conj(),ww))/3-constants)]
    result=minimize(lambda x:-x[-1],initial,method='SLSQP',
                    constraints=[dict(type='ineq',fun=constraints),dict(type='eq',fun=lambda x:np.sum(h*unpack(x),axis=1).imag)],
                    options=dict(ftol=1e-10,maxiter=300))
    assert result.success,result.message
    assert abs(result.x[-1]-initial[-1])<2e-5
    print('PASS: separable=dense, geometric identities, streamed Gram/Jacobian, noiseless recovery, power/SINR/quantization, independent SCA solver check',flush=True)


if __name__=='__main__':
    with threadpool_limits(limits=1):run_tests()
