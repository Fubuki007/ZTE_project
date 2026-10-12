"""Memory-bounded exact contractions for the full 12672 x 64 x 256 experiment."""
from pathlib import Path
import numpy as np
from stage3_model import Model


def chunks(ns, batch=128):
    for first in range(0, ns, batch):
        yield slice(first, min(first+batch, ns))


def coefficients(cfg):
    hop = cfg.hop_amplitude
    single = np.array([1, hop*np.exp(.4j), hop*np.exp(-.7j), hop**2*np.exp(.9j)])
    return np.concatenate([single, .8*single])


def reference_power(cfg, batch=128):
    total, count = 0., 0
    times = np.arange(cfg.lc+cfg.lf)*cfg.symbol_time
    for sl in chunks(cfg.ns, batch):
        model = Model(cfg, np.arange(cfg.ns)[sl])
        f, t = model.factors(cfg.truth, model.wzf, None, times, False)
        y = (f.reshape(-1, 2)*np.array([1, .8]))@t.T
        total += np.vdot(y, y).real
        count += y.size
    return float(total/count)


def simulate_block(cfg, w, phase, times, noise_variance, seed, path, batch=128):
    """Only this simulator receives truth. Estimators receive saved observations."""
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    shape = (cfg.ns, cfg.rx_nx*cfg.rx_ny, len(times))
    y = np.lib.format.open_memmap(path, mode='w+', dtype=np.complex128, shape=shape)
    rng = np.random.default_rng(seed)
    alpha = coefficients(cfg)
    for sl in chunks(cfg.ns, batch):
        model = Model(cfg, np.arange(cfg.ns)[sl])
        f, t = model.factors(cfg.truth, w[sl], phase, times)
        clean = ((f.reshape(-1, len(alpha))*alpha)@t.T).reshape(len(model.freq), shape[1], shape[2])
        # Method-independent seeds/chunking give exactly paired AWGN.
        noise = (rng.standard_normal(clean.shape)+1j*rng.standard_normal(clean.shape))*np.sqrt(noise_variance/2)
        y[sl] = clean+noise
    y.flush()
    return y


class Observation:
    def __init__(self, cfg, records, batch=128):
        self.cfg, self.records, self.batch = cfg, records, batch
        self.norm2 = 0.
        for record in records:
            for sl in chunks(cfg.ns, batch):
                yy = np.asarray(record['y'][sl])
                self.norm2 += float(np.vdot(yy, yy).real)

    def statistics(self, theta, paths=True, alpha=None):
        """Accumulate [D,J]^H[D,J], [D,J]^Hy, without materializing D or J."""
        width = 4 if paths else 1
        p = width*len(theta)
        dimension = p if alpha is None else p+theta.size
        gram = np.zeros((dimension, dimension), complex)
        rhs = np.zeros(dimension, complex)
        eps = [.002, .005, .001, .001]
        for record in self.records:
            for sl in chunks(self.cfg.ns, self.batch):
                model = Model(self.cfg, np.arange(self.cfg.ns)[sl])
                w, phase, times = record['w'][sl], record['phase'], record['times']
                f, t = model.factors(theta, w, phase, times, paths)
                fparts, tparts = [f], [t]
                mapping = np.eye(p, dimension, dtype=complex)
                if alpha is not None:
                    rows = [mapping]
                    for q in range(len(theta)):
                        ids = slice(q*width, (q+1)*width)
                        for j in range(4):
                            plus, minus = theta[q].copy(), theta[q].copy()
                            plus[j] += eps[j]
                            minus[j] -= eps[j]
                            fp, tp = model.factors([plus], w, phase, times, paths)
                            fm, tm = model.factors([minus], w, phase, times, paths)
                            # Differentiate the factors before taking inner products:
                            # avoids cancellation of nearly equal enormous Grams.
                            fparts.extend([(fp-fm)/(2*eps[j]), f[:, :, ids]])
                            tparts.extend([t[:, ids], (tp-tm)/(2*eps[j])])
                            row = np.zeros((2*width, dimension), complex)
                            row[:, p+q*4+j] = np.tile(alpha[ids], 2)
                            rows.append(row)
                    mapping = np.concatenate(rows)
                ff = np.concatenate(fparts, axis=2).reshape(-1, sum(part.shape[2] for part in fparts))
                tt = np.concatenate(tparts, axis=1)
                fullgram = (ff.conj().T@ff)*(tt.conj().T@tt)
                yy = np.asarray(record['y'][sl]).reshape(len(ff), len(times))
                cross = np.sum(ff.conj()*(yy@tt.conj()), axis=0)
                gram += mapping.conj().T@fullgram@mapping
                rhs += mapping.conj().T@cross
        return gram, rhs

    def fit(self, theta, paths=True):
        g, b = self.statistics(theta, paths)
        # Normalize columns before solving, especially when an RIS path is weak.
        scale = np.sqrt(np.maximum(g.diagonal().real, 1e-30))
        normalized = g/scale[:, None]/scale[None, :]
        inverse = np.linalg.pinv(normalized, rcond=1e-10, hermitian=True)/scale[:, None]/scale[None, :]
        alpha = inverse@b
        cost = max(float(self.norm2-np.vdot(b, alpha).real), 0.)
        return alpha, cost, inverse

    def refine(self, initial, paths=True):
        cfg = self.cfg
        z = np.array(initial, float).copy()
        widths = np.tile([cfg.c/(2*cfg.ns*cfg.df)*1.5, 40., 18., 35.], (len(z), 1))
        low, high = z-widths, z+widths
        low[:, 0] = np.maximum(low[:, 0], 20.)
        high[:, 0] = np.minimum(high[:, 0], 600.)
        low[:, 2] = np.maximum(low[:, 2], .1)
        high[:, 2] = np.minimum(high[:, 2], 89.5)
        z = np.clip(z, low, high)
        p = len(z)*(4 if paths else 1)
        scales = np.tile([max(cfg.c/(2*cfg.ns*cfg.df), .05), 5., 1., 2.], len(z))
        alpha, cost, inverse = self.fit(z, paths)
        costs = [cost]
        for _ in range(cfg.refinement_iterations):
            g, b = self.statistics(z, paths, alpha)
            cross = g[:p, p:]
            lhs = (g[p:, p:]-cross.conj().T@inverse@cross).real
            rhs = (b[p:]-cross.conj().T@alpha).real
            lhs = lhs*scales[:, None]*scales[None, :]
            rhs *= scales
            damping = 1e-8*max(np.trace(lhs), 1)/len(lhs)
            delta = (np.linalg.lstsq(lhs+damping*np.eye(len(lhs)), rhs, rcond=1e-10)[0]*scales).reshape(z.shape)
            accepted = False
            for rate in (1., .5, .25, .125, .0625, .03125):
                candidate = np.clip(z+rate*delta, low, high)
                an, cn, invn = self.fit(candidate, paths)
                if cn < cost:
                    displacement = float(np.max(np.abs(candidate-z)/scales.reshape(z.shape)))
                    improvement = cost-cn
                    z, alpha, cost, inverse = candidate, an, cn, invn
                    costs.append(cost)
                    accepted = True
                    break
            if not accepted or displacement < 1e-4 or improvement < 1e-10*max(cost, 1):
                break
        return z, dict(costs=costs, at_boundary=bool(np.any(np.isclose(z, low, atol=1e-4)) or
                                                    np.any(np.isclose(z, high, atol=1e-4))))


def coarse_from_records(cfg, records, q=2):
    """Full-data range/Doppler FFT followed by wideband spatial-angle fit.

    Pool antenna powers instead of broadside sums to avoid array nulls. Arrays
    are processed one antenna at a time, using every subcarrier and symbol.
    """
    from scipy.optimize import minimize
    ns, length = cfg.ns, sum(len(r['times']) for r in records)
    nf, nv = 2*ns, max(256, 2*length)
    power = np.zeros((nf, nv))
    wr, wl = np.hanning(ns), np.hanning(length)
    for antenna in range(cfg.rx_nx*cfg.rx_ny):
        yy = np.concatenate([r['y'][:, antenna, :] for r in records], axis=1)
        spec = np.fft.fftshift(np.fft.fft(np.fft.ifft(yy*wr[:, None]*wl, n=nf, axis=0), n=nv, axis=1), axes=1)
        power += np.abs(spec)**2
    ranges = np.arange(nf)*cfg.c/(2*cfg.df*nf)
    vel = np.fft.fftshift(np.fft.fftfreq(nv, cfg.symbol_time))*cfg.c/(2*cfg.fc)
    power[(ranges<20)|(ranges>600)] = 0
    result = []
    for _ in range(q):
        ir, iv = np.unravel_index(np.argmax(power), power.shape)
        def shift(values, index):
            a,b,c = np.log(np.maximum(values[(index+np.array([-1,0,1]))%len(values)],1e-30))
            return float(np.clip(.5*(a-c)/(a-2*b+c),-.5,.5)) if abs(a-2*b+c)>1e-15 else 0.
        rr = (ir+shift(power[:,iv],ir))*cfg.c/(2*cfg.df*nf)
        vv = vel[iv]+shift(power[ir],iv)*cfg.c/(2*cfg.fc*cfg.symbol_time*nv)
        # Form spatial snapshot over all samples, range and Doppler compensated.
        spatial = np.zeros(cfg.rx_nx*cfg.rx_ny, complex)
        # Center-carrier angle approximation only initializes a wideband fit.
        for rec in records:
            ev = np.exp(-4j*np.pi*cfg.fc*vv/cfg.c*rec['times'])
            for sl in chunks(ns):
                offsets=np.arange(ns)[sl]*cfg.df
                er=np.exp(4j*np.pi*offsets*rr/cfg.c)
                spatial += np.einsum('irl,i,l->r',rec['y'][sl],er,ev,optimize=True)
        ss = spatial.reshape(cfg.rx_nx,cfg.rx_ny)
        frequency_ratio = (cfg.fc+(ns-1)*cfg.df/2)/cfg.fc
        ux=-np.angle(np.sum(ss[1:]*ss[:-1].conj()))/(np.pi*frequency_ratio)
        uy=-np.angle(np.sum(ss[:,1:]*ss[:,:-1].conj()))/(np.pi*frequency_ratio)
        theta=np.rad2deg(np.arcsin(min(np.hypot(ux,uy),.99999)))
        phi=np.rad2deg(np.arctan2(uy,ux))
        result.append([rr,vv,theta,phi])
        power[max(ir-2,0):min(ir+3,nf)] = 0
    return np.array(result)
