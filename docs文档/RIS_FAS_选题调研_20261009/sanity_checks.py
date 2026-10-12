"""Research sanity checks only. Does not import or alter the MATLAB pipeline."""
from pathlib import Path
from itertools import product
import json
import numpy as np

ROOT = Path(__file__).resolve().parent
rng = np.random.default_rng(20261009)

def cn(shape):
    return (rng.standard_normal(shape) + 1j*rng.standard_normal(shape))/np.sqrt(2)

def efim(dp, dn, cov):
    d = np.concatenate([dp, dn], axis=1)
    j = 2*np.real(d.conj().T @ np.linalg.solve(cov, d))
    k = dp.shape[1]
    return j[:k,:k] - j[:k,k:] @ np.linalg.solve(j[k:,k:], j[k:,:k])

lam = 3e8/28e9
geometry = {
    'wavelength_m':lam,
    'ris_bs_separation_m':1.5*lam,
    'target_range_m':200.6,
    'separation_over_range_rad':1.5*lam/200.6,
    'separation_over_range_deg':float(np.degrees(1.5*lam/200.6)),
    'range_resolution_m':3e8/(2*1.52064e9),
    'fractional_bandwidth':1.52064e9/28e9,
}
for name, side in [('tx_4x4',3*lam/2),('rx_8x8',7*lam/2),('ris_8x8',7*lam/5)]:
    aperture = np.sqrt(2)*side
    geometry[name]={'diagonal_aperture_m':float(aperture),'fraunhofer_distance_m':float(2*aperture**2/lam)}
geometry['rx_cube_complex64_gib']=64*12672*256*8/2**30
geometry['rx_cube_complex128_gib']=64*12672*256*16/2**30

# The exact, full-rank, thermal-noise-only LS baseline has an SI-channel-
# independent absolute estimation error when the pilot and its noise are fixed.
xp = cn((4,16))
data = cn((4,32))
zp = 0.02*cn((6,16))
g1 = cn((6,4))
g2 = 0.1*cn((6,4))
right_inverse = xp.conj().T @ np.linalg.inv(xp @ xp.conj().T)
residuals=[]
for g in [g1,g2]:
    ghat = (g @ xp + zp) @ right_inverse
    residuals.append((g-ghat) @ data)
ls = {
    'original_si_power_ratio_g1_over_g2':float(np.linalg.norm(g1@data)**2/np.linalg.norm(g2@data)**2),
    'max_absolute_residual_difference':float(np.max(np.abs(residuals[0]-residuals[1]))),
    'note':'Same pilot, pilot noise and transmitted data; algebra check, not a physical FAS simulation.',
}

# Illustrative four-dimensional complex Gaussian model, real-valued parameters.
# Coordinate 1 is a nuisance amplitude; coordinates 2-4 encode position.
dp=np.eye(4,dtype=complex)[:,1:]
dn=np.eye(4,dtype=complex)[:,:1]
toy=[]
for name, si in [('A_sensitivity_overlap',[0.,9.,0.,0.]),('B_nuisance_overlap',[100.,0.,0.,0.])]:
    j=efim(dp,dn,np.diag(1+np.array(si)))
    toy.append({'case':name,'total_si_power':sum(si),'peb_normalized_units':float(np.sqrt(np.trace(np.linalg.inv(j))))})

# Check a conservative conditional BnB lower bound on synthetic additive
# derivatives. This does not establish pruning efficiency in the physical model.
nt,nports,nobs,npar=4,4,8,3
contrib=cn((nt,nports,nobs,npar))
fixed=[1,2]
a=sum(contrib[i,k] for i,k in enumerate(fixed))
rho=sum(max(np.linalg.norm(contrib[i,k],2) for k in range(nports)) for i in range(len(fixed),nt))
epsilon=1.0
sigma2=0.7
jbar=(2/sigma2)*np.real((1+epsilon)*(a.conj().T@a)+(1+1/epsilon)*rho**2*np.eye(npar))
lower=float(np.trace(np.linalg.inv(jbar)))
dn2=np.column_stack([np.eye(nobs)[:,0],1j*np.eye(nobs)[:,0]])
values=[]
violations=[]
for tail in product(range(nports),repeat=nt-len(fixed)):
    config=fixed+list(tail)
    d=sum(contrib[i,k] for i,k in enumerate(config))
    u=cn((nobs,2))
    cov=sigma2*np.eye(nobs)+u@u.conj().T
    je=efim(d,dn2,cov)
    values.append(float(np.trace(np.linalg.inv(je))))
    violations.append(float(np.max(np.linalg.eigvalsh(je-jbar))))
bound={
    'completions_checked':len(values),
    'peb_squared_lower_bound':lower,
    'minimum_completed_peb_squared':min(values),
    'maximum_eigenvalue_of_efim_minus_bound':max(violations),
    'note':'Valid but loose synthetic bound; no runtime or localization performance claim.',
}
result={'geometry':geometry,'ls_invariance':ls,'directional_si_toy':toy,'conditional_bound_check':bound}
(ROOT/'sanity_results.json').write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf-8')
print(json.dumps(result,ensure_ascii=False,indent=2))
