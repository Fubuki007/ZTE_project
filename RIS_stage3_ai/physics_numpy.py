"""NumPy design physics and deployment audits; same normalization as Stage-3."""
import numpy as np
from .context import DesignContext


def phase_levels(bits=2):
    return np.exp(2j*np.pi*np.arange(2**bits)/(2**bits))


def quantize_phase(phase, bits=2):
    phase = np.asarray(phase, dtype=np.complex128)
    if phase.ndim != 1 or not np.all(np.isfinite(phase)) or np.any(np.abs(phase) < 1e-15):
        raise ValueError('RIS candidate must be a finite nonzero vector')
    normalized = phase/np.abs(phase)
    levels = phase_levels(bits)
    # Keep original nearest-chord rule including deterministic ties.
    return levels[np.argmin(np.abs(normalized[:, None]-levels), axis=1)]


def effective_user(ctx: DesignContext, phase):
    return ctx.hd + ctx.user_ris_amplitude*(ctx.user_basis@phase)[:, None]*ctx.gr.conj()


def sinr(ctx, w, phase):
    return np.abs(np.sum(effective_user(ctx, phase)*w, axis=1))**2/ctx.communication_noise


def illumination(ctx, w, phase):
    direct = np.sum(ctx.gd.conj()*w[None, :, :], axis=2)
    reflected = np.sum(ctx.gr.conj()*w, axis=1)
    coupling = ctx.basis@phase
    return np.mean(np.abs(direct)**2+ctx.eta*np.abs(coupling)**2*np.abs(reflected[None, :])**2, axis=1)


def geometric_initialization(ctx):
    initial = np.angle(np.sum(np.conj(ctx.basis[:, 0, :]), axis=0))
    phase = quantize_phase(np.exp(1j*initial), ctx.bits)
    h = effective_user(ctx, phase)
    norm = np.linalg.norm(h, axis=1)
    if np.any(norm < 1e-15):
        raise ValueError('Zero user channel at initialization')
    return h.conj()/norm[:, None], phase


def audit_design(ctx, w, phase, require_quantized=True):
    """Check every subcarrier, not an average communication metric."""
    w, phase = np.asarray(w), np.asarray(phase)
    report = dict(feasible=False, reasons=[])
    if w.shape != (ctx.ns, ctx.nt) or phase.shape != (ctx.nr,):
        report['reasons'].append('shape')
        return report
    if not np.all(np.isfinite(w)) or not np.all(np.isfinite(phase)):
        report['reasons'].append('nonfinite')
        return report
    with np.errstate(over='ignore', invalid='ignore', divide='ignore'):
        power = float(np.sum(np.abs(w)**2))
        ratios = sinr(ctx, w, phase)
        score = illumination(ctx, w, phase)
        unit_error = float(np.max(np.abs(np.abs(phase)-1)))
        quant_error = float(np.max(np.min(np.abs(phase[:, None]-phase_levels(ctx.bits)), axis=1)))
    if not np.all(np.isfinite([power, *ratios, *score, unit_error, quant_error])):
        report['reasons'].append('nonfinite_physics')
        return report
    report.update(power=power, power_budget=ctx.power_budget,
                  min_sinr=float(np.min(ratios)), min_illumination=float(np.min(score)),
                  illumination=score.tolist(), unit_modulus_error=unit_error,
                  quantization_error=quant_error)
    if power > ctx.power_budget*(1+1e-5):
        report['reasons'].append('power')
    if np.min(ratios) < ctx.gamma*(1-1e-4):
        report['reasons'].append('communication')
    if unit_error > 1e-10:
        report['reasons'].append('unit_modulus')
    if require_quantized and quant_error > 1e-10:
        report['reasons'].append('quantization')
    report['feasible'] = not report['reasons']
    return report
