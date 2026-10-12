"""Stage-3 equations (5)-(76), with explicit simulation assumptions.

One communication stream; frequency-dependent digital beamformers; one common
quantized RIS vector. No true target parameters enter beam design or estimation.
The RIS channels are normalized rank-one LoS channels, not a calibrated link budget.
"""
from dataclasses import dataclass, asdict
import numpy as np
from scipy.optimize import linear_sum_assignment, minimize_scalar


@dataclass
class Config:
    fc: float = 28e9
    c: float = 3e8
    df: float = 120e3
    cp_time: float = 0.6e-6
    ns: int = 12672
    lc: int = 128
    lf: int = 128
    tx_nx: int = 4
    tx_ny: int = 4
    rx_nx: int = 8
    rx_ny: int = 8
    ris_nx: int = 8
    ris_ny: int = 8
    bits: int = 2
    ris_position: tuple = (12., -10., 8.)
    # R, BS-radial velocity, elevation-from-z, azimuth; degrees and metres.
    truth: tuple = ((200.6, 15.1, 60.83, 28.51), (210.4, -5.4, 15.94, 11.53))
    user_angles: tuple = (35., 20.)
    hop_amplitude: float = 0.7
    user_ris_amplitude: float = 0.15
    communication_noise: float = 0.02
    gamma: float = 2.0
    ao_iterations: int = 3
    sca_iterations: int = 3
    phase_sweeps: int = 2
    refinement_iterations: int = 12
    seed: int = 20261012

    @property
    def symbol_time(self):
        return 1 / self.df + self.cp_time


def unit(theta, phi):
    t, p = np.deg2rad([theta, phi])
    return np.array([np.sin(t)*np.cos(p), np.sin(t)*np.sin(p), np.cos(t)])


def ura(nx, ny, spacing):
    x, y = np.meshgrid(np.arange(nx), np.arange(ny), indexing='ij')
    return np.column_stack((x.ravel()-(nx-1)/2, y.ravel()-(ny-1)/2,
                            np.zeros(nx*ny))) * spacing


def single_user_sca(sw, constants, h, threshold):
    """Solve (57) exactly for K=1, Q=2 via its scalar convex dual.

    Dual target weights lie on a 2-simplex. For each weight, the support
    problem is a linear objective over a power ball and communication
    halfspaces. Its power multiplier is found by bisection. This avoids
    constructing a 400k-real-variable conic problem at full OFDM size.
    """
    if len(sw) != 2:
        raise ValueError('The single-user dual solver requires exactly two targets')
    ns = len(h)
    hn = np.linalg.norm(h, axis=1)
    v = h.conj()/hn[:, None]
    floor = np.sqrt(threshold)/hn
    if np.sum(floor**2) >= ns:
        raise ValueError('Communication constraints infeasible under total power')
    def support(weight, details=False):
        s = weight*sw[0]+(1-weight)*sw[1]
        dot = np.sum(v.conj()*s, axis=1)
        parallel = dot.real
        perpendicular = s-v*dot[:, None]
        pp = float(np.sum(np.abs(perpendicular)**2))
        def power(lam):
            return np.sum(np.maximum(parallel/lam, floor)**2)+pp/lam**2
        lo, hi = 0., max(float(np.linalg.norm(s)), 1.)
        for _ in range(55):
            middle = (lo+hi)/2
            if power(middle) > ns:
                lo = middle
            else:
                hi = middle
        w = v*np.maximum(parallel/hi, floor)[:, None]+perpendicular/hi
        lower = 2*np.real(np.einsum('qij,ij->q', sw.conj(), w))/ns-constants
        dual = weight*lower[0]+(1-weight)*lower[1]
        return (w, lower, dual) if details else dual
    result = minimize_scalar(support, bounds=(0., 1.), method='bounded',
                             options={'xatol': 1e-8, 'maxiter': 60})
    candidates = [0., result.x, 1.]
    weight = min(candidates, key=support)
    w, lower, dual = support(weight, True)
    gap = float(dual-np.min(lower))
    if gap > 2e-5:
        raise RuntimeError(f'Single-user SCA duality gap too large: {gap}')
    return w, dict(solver='single-user scalar dual', duality_gap=gap, target_weight=float(weight))


class Model:
    def __init__(self, cfg, indices=None):
        self.cfg = cfg
        self.indices = np.arange(cfg.ns) if indices is None else np.asarray(indices)
        self.freq = cfg.fc + self.indices*cfg.df
        self.k = 2*np.pi*self.freq/cfg.c
        self.offset = self.indices*cfg.df
        self.tx = ura(cfg.tx_nx, cfg.tx_ny, cfg.c/cfg.fc/2)
        self.rx = ura(cfg.rx_nx, cfg.rx_ny, cfg.c/cfg.fc/2)
        self.ris = ura(cfg.ris_nx, cfg.ris_ny, cfg.c/cfg.fc/2)
        self.r = np.array(cfg.ris_position)
        self.dbr = np.linalg.norm(self.r)
        self.ubr = self.r/self.dbr
        self.atbr = self.steer(self.tx, self.ubr, 1)
        self.brbr = self.steer(self.rx, self.ubr, -1)
        self.hd = self.steer(self.tx, unit(*cfg.user_angles), -1)/np.sqrt(len(self.tx))
        user_position = 160*unit(*cfg.user_angles)
        ur = (user_position-self.r)/np.linalg.norm(user_position-self.r)
        self.user_basis = self.ris_basis(ur)
        self.wzf = self.hd.conj()/np.linalg.norm(self.hd, axis=1)[:, None]

    def steer(self, positions, u, sign):
        # shape: subcarrier x element
        return np.exp(sign*1j*self.k[:, None]*(positions@u)[None, :])

    def ris_basis(self, ur):
        # Eq. (46), one phase for all subcarriers; no conjugation of phi.
        return np.exp(-1j*self.k[:, None]*(self.ris@(ur-self.ubr))[None, :])/len(self.ris)

    def geometry(self, z):
        radius, velocity, theta, phi = z
        ub = unit(theta, phi)
        position = radius*ub
        rr = np.linalg.norm(position-self.r)
        ur = (position-self.r)/rr
        # The PDF gives only one velocity scalar. Close the model explicitly:
        # target velocity vector is radial w.r.t. BS; v_R = v_B u_B dot u_R.
        vr = velocity*float(ub@ur)
        delays = np.array([2*radius, self.dbr+radius+rr,
                           self.dbr+radius+rr, 2*(self.dbr+rr)])/self.cfg.c
        dopplers = np.array([2*velocity, velocity+vr, velocity+vr, 2*vr])*self.cfg.fc/self.cfg.c
        return ub, ur, delays, dopplers

    def effective_user(self, phase):
        if phase is None:
            return self.hd
        cu = self.user_basis@phase
        return self.hd + self.cfg.user_ris_amplitude*cu[:, None]*self.atbr.conj()/np.sqrt(len(self.tx))

    def sinr(self, w, phase):
        return np.abs(np.sum(self.effective_user(phase)*w, axis=1))**2/self.cfg.communication_noise

    def target_design(self, coarse):
        gd, basis = [], []
        for z in coarse:
            ub, ur, _, _ = self.geometry(z)
            gd.append(self.steer(self.tx, ub, 1)/np.sqrt(len(self.tx)))
            basis.append(self.ris_basis(ur))
        return np.array(gd), np.array(basis)

    def illumination(self, w, phase, gd, basis):
        direct = np.sum(gd.conj()*w[None, :, :], axis=2)
        gr = self.atbr/np.sqrt(len(self.tx))
        reflected = np.sum(gr.conj()*w, axis=1)
        coupling = basis@phase
        return np.mean(np.abs(direct)**2+self.cfg.hop_amplitude**2*
                       np.abs(coupling)**2*np.abs(reflected[None, :])**2, axis=1)

    def design(self, coarse):
        """Eqs. (48)-(59): quantized multi-target initialization, SCA + CD."""
        cfg = self.cfg
        gd, basis = self.target_design(coarse)
        levels = np.exp(2j*np.pi*np.arange(2**cfg.bits)/(2**cfg.bits))
        initial = np.angle(np.sum(np.conj(basis[:, 0, :]), axis=0))
        phase = levels[np.argmin(np.abs(np.exp(1j*initial[:, None])-levels), axis=1)]
        h = self.effective_user(phase)
        w = h.conj()/np.linalg.norm(h, axis=1)[:, None]
        gr = self.atbr/np.sqrt(len(self.tx))
        history = [float(np.min(self.illumination(w, phase, gd, basis)))]
        statuses = []
        for _ in range(cfg.ao_iterations):
            h = self.effective_user(phase)
            # Rotate each user's desired response to be real nonnegative.
            w *= np.exp(-1j*np.angle(np.sum(h*w, axis=1)))[:, None]
            coupling = basis@phase
            for _ in range(cfg.sca_iterations):
                d0 = np.sum(gd.conj()*w[None, :, :], axis=2)
                r0 = np.sum(gr.conj()*w, axis=1)
                eta = cfg.hop_amplitude**2*np.abs(coupling)**2
                sw = gd*d0[:, :, None]+eta[:, :, None]*gr[None, :, :]*r0[None, :, None]
                constants = np.mean(np.abs(d0)**2+eta*np.abs(r0[None, :])**2, axis=1)
                candidate, dual_info = single_user_sca(sw, constants, h, cfg.gamma*cfg.communication_noise)
                statuses.append(dual_info)
                score = float(np.min(self.illumination(candidate, phase, gd, basis)))
                if (np.sum(np.abs(candidate)**2) > cfg.ns*(1+1e-5) or
                        np.min(self.sinr(candidate, phase)) < cfg.gamma*(1-1e-4)):
                    raise RuntimeError('SCA returned infeasible transmit beamformer')
                if score < history[-1]-2e-5:
                    raise RuntimeError('SCA illumination decreased')
                w = candidate
                history.append(score)
            for _ in range(cfg.phase_sweeps):
                changed = False
                # Vectorized candidate evaluation while keeping W fixed (59).
                d = np.sum(gd.conj()*w[None, :, :], axis=2)
                rbeam = np.sum(gr.conj()*w, axis=1)
                dc = np.abs(d)**2
                rc = cfg.hop_amplitude**2*np.abs(rbeam)**2
                cc = basis@phase
                hu0 = np.sum(self.hd*w, axis=1)
                hu_r = cfg.user_ris_amplitude*np.sum(self.atbr.conj()*w, axis=1)/np.sqrt(len(self.tx))
                cu = self.user_basis@phase
                for n in range(len(phase)):
                    delta = levels-phase[n]
                    ctest = cc[:, :, None]+basis[:, :, n, None]*delta
                    scores = np.min(np.mean(dc[:, :, None]+rc[None, :, None]*np.abs(ctest)**2, axis=1), axis=0)
                    utest = hu0[:, None]+hu_r[:, None]*(cu[:, None]+self.user_basis[:, n, None]*delta)
                    feasible = np.min(np.abs(utest)**2/cfg.communication_noise, axis=0) >= cfg.gamma*(1-1e-5)
                    scores[~feasible] = -np.inf
                    j = int(np.argmax(scores))
                    if scores[j] > history[-1]+1e-9:
                        cc += basis[:, :, n]*delta[j]
                        cu += self.user_basis[:, n]*delta[j]
                        phase[n] = levels[j]
                        history.append(float(scores[j]))
                        changed = True
                if not changed:
                    break
        return w, phase, dict(history=history, min_sinr=float(np.min(self.sinr(w, phase))),
                             power=float(np.sum(np.abs(w)**2)), statuses=statuses)

    def target_dictionary(self, z, blocks, paths=True):
        ub, ur, tau, doppler = self.geometry(z)
        at = self.steer(self.tx, ub, 1)
        bd = self.steer(self.rx, ub, -1)
        basis = self.ris_basis(ur)
        output = []
        for w, phase, symbols, times in blocks:
            fd = np.sum(at.conj()*w, axis=1)
            if phase is None:
                cc = np.zeros(len(self.freq), complex)
            else:
                cc = basis@phase
            fr = cc*np.sum(self.atbr.conj()*w, axis=1)
            br = self.brbr*cc[:, None]
            columns = []
            for a in range(4 if paths else 1):
                recv = bd if a < 2 else br
                tx = fd if a in (0, 2) else fr
                envelope = (tx*np.exp(-2j*np.pi*self.offset*tau[a]))[:, None]*symbols
                envelope *= np.exp(2j*np.pi*doppler[a]*times[None, :])
                columns.append((recv.T[:, :, None]*envelope[None, :, :]).ravel())
            output.append(np.column_stack(columns))
        return np.concatenate(output, axis=0)

    def factors(self, theta, w, phase, times, paths=True):
        """Exact separable factors D[i,r,l,p] = F[i,r,p] T[l,p].

        Known unit-modulus QPSK symbols have been removed from observations.
        All subcarriers, receive elements and OFDM symbols remain in the fit.
        """
        spatial, temporal = [], []
        for z in theta:
            ub, ur, tau, doppler = self.geometry(z)
            at = self.steer(self.tx, ub, 1)
            bd = self.steer(self.rx, ub, -1)
            cc = np.zeros(len(self.freq), complex) if phase is None else self.ris_basis(ur)@phase
            br = self.brbr*cc[:, None]
            fd = np.sum(at.conj()*w, axis=1)
            fr = cc*np.sum(self.atbr.conj()*w, axis=1)
            for a in range(4 if paths else 1):
                recv = bd if a < 2 else br
                tx = fd if a in (0, 2) else fr
                spatial.append(recv*(tx*np.exp(-2j*np.pi*self.offset*tau[a]))[:, None])
                temporal.append(np.exp(2j*np.pi*doppler[a]*times))
        return np.stack(spatial, axis=2), np.stack(temporal, axis=1)

    def dictionary(self, theta, blocks, paths=True):
        return np.concatenate([self.target_dictionary(z, blocks, paths) for z in theta], axis=1)

    def clean(self, theta, blocks, paths=True):
        # Separate complex path coefficients, fixed across observation blocks.
        qamp = [1., .8]
        hop = self.cfg.hop_amplitude
        coeff = []
        for q in range(len(theta)):
            coeff.extend(qamp[q]*np.array([1, hop*np.exp(.4j), hop*np.exp(-.7j),
                                          hop**2*np.exp(.9j)]) if paths else [qamp[q]])
        return self.dictionary(theta, blocks, paths)@np.array(coeff)


def coarse_fft(model, observation, symbols, q=2):
    """DD-only blind range/Doppler detection followed by spatial phase slopes.

    Noncoherent spatial power pooling avoids the broadside cancellation of the
    legacy spatial sum. Q is assumed known, as in the existing project.
    """
    cfg = model.cfg
    nr, ns, length = len(model.rx), cfg.ns, symbols.shape[1]
    cube = observation.reshape(nr, ns, length)*symbols.conj()[None, :, :]
    nv = max(128, 4*length)
    nf = 4*ns
    window = np.hanning(ns)[None, :, None]*np.hanning(length)[None, None, :]
    spec = np.fft.fftshift(np.fft.fft(np.fft.ifft(cube*window, n=nf, axis=1), n=nv, axis=2), axes=2)
    power = np.sum(np.abs(spec)**2, axis=0)
    ranges = np.arange(nf)*cfg.c/(2*cfg.df*nf)
    velocities = np.fft.fftshift(np.fft.fftfreq(nv, cfg.symbol_time))*cfg.c/(2*cfg.fc)
    power[(ranges < 20)|(ranges > 600), :] = 0
    estimates = []
    for _ in range(q):
        ir, iv = np.unravel_index(np.argmax(power), power.shape)
        def parabola(values, idx):
            a, b, c = np.log(np.maximum(values[(idx+np.array([-1, 0, 1])) % len(values)], 1e-30))
            return float(np.clip(.5*(a-c)/(a-2*b+c), -.5, .5)) if abs(a-2*b+c)>1e-15 else 0.
        dr = parabola(power[:, iv], ir)
        dv = parabola(power[ir], iv)
        rr = (ir+dr)*cfg.c/(2*cfg.df*nf)
        vv = velocities[iv]+dv*cfg.c/(2*cfg.fc*cfg.symbol_time*nv)
        er = np.exp(4j*np.pi*model.offset*rr/cfg.c)
        ev = np.exp(-4j*np.pi*cfg.fc*vv/cfg.c*np.arange(length)*cfg.symbol_time)
        spatial = np.einsum('ril,i,l->r', cube, er, ev).reshape(cfg.rx_nx, cfg.rx_ny)
        ux = -np.angle(np.sum(spatial[1:]*spatial[:-1].conj()))/np.pi
        uy = -np.angle(np.sum(spatial[:, 1:]*spatial[:, :-1].conj()))/np.pi
        theta = np.rad2deg(np.arcsin(np.minimum(np.hypot(ux, uy), .99999)))
        phi = np.rad2deg(np.arctan2(uy, ux))
        estimates.append([rr, vv, theta, phi])
        # Range-separated targets: suppress half a native range cell, all v.
        power[max(0, ir-3):min(nf, ir+4), :] = 0
    return np.array(estimates)


def refine(model, observation, blocks, initial, paths=True):
    """Variable projection, nuisance amplitudes re-fit at every step (69)-(76)."""
    z = np.array(initial, float).copy()
    # Predetermined search neighborhoods, independent of target truth.
    widths = np.tile([model.cfg.c/(2*model.cfg.ns*model.cfg.df)*1.5, 40., 18., 35.], (len(z), 1))
    low, high = z-widths, z+widths
    low[:, 0] = np.maximum(low[:, 0], 20.)
    high[:, 0] = np.minimum(high[:, 0], 600.)
    low[:, 2] = np.maximum(low[:, 2], .1)
    high[:, 2] = np.minimum(high[:, 2], 89.5)
    z = np.clip(z, low, high)
    scales = np.tile([1., 5., 1., 2.], len(z))
    eps = np.array([.002, .005, .001, .001])
    width = 4 if paths else 1
    def fit(candidate):
        d = model.dictionary(candidate, blocks, paths)
        a = np.linalg.lstsq(d, observation, rcond=1e-9)[0]
        residual = observation-d@a
        return d, a, residual, float(np.vdot(residual, residual).real)
    d, a, residual, cost = fit(z)
    costs = [cost]
    for _ in range(model.cfg.refinement_iterations):
        jac = np.empty((len(observation), z.size), complex)
        for q in range(len(z)):
            for j in range(4):
                plus, minus = z[q].copy(), z[q].copy()
                plus[j] += eps[j]
                minus[j] -= eps[j]
                deriv = (model.target_dictionary(plus, blocks, paths)-
                         model.target_dictionary(minus, blocks, paths))/(2*eps[j])
                jac[:, q*4+j] = deriv@a[q*width:(q+1)*width]
        jeff = jac-d@np.linalg.lstsq(d, jac, rcond=1e-9)[0]
        js = jeff*scales[None, :]
        lhs = (js.conj().T@js).real
        rhs = (js.conj().T@residual).real
        step = np.linalg.lstsq(lhs+1e-7*np.trace(lhs)/len(lhs)*np.eye(len(lhs)), rhs, rcond=1e-10)[0]*scales
        step = step.reshape(z.shape)
        accepted = False
        for rate in (1., .5, .25, .125, .0625, .03125):
            candidate = np.clip(z+rate*step, low, high)
            dn, an, rn, cn = fit(candidate)
            if cn < cost:
                displacement = np.max(np.abs(candidate-z))
                improvement = cost-cn
                z, d, a, residual, cost = candidate, dn, an, rn, cn
                costs.append(cost)
                accepted = True
                break
        if not accepted or displacement < 1e-4 or improvement < 1e-9*max(cost, 1):
            break
    return z, dict(costs=costs, at_boundary=bool(np.any(np.isclose(z, low, atol=1e-3)) or
                                                np.any(np.isclose(z, high, atol=1e-3))))


def angle_errors(estimates, truth):
    """Optimal assignment by 3D direction; return theta/phi and geodesic errors."""
    ue = np.array([unit(*z[2:]) for z in estimates])
    ut = np.array([unit(*z[2:]) for z in truth])
    cost = np.rad2deg(np.arccos(np.clip(ut@ue.T, -1, 1)))
    rows, cols = linear_sum_assignment(cost)
    aligned = estimates[cols]
    errors = aligned[:, 2:]-np.asarray(truth)[:, 2:]
    errors[:, 1] = (errors[:, 1]+180)%360-180
    return errors, cost[rows, cols]
