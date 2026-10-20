"""Full-frequency NumPy feasibility repair and auditable traditional fallback.

The SCA and coordinate updates reproduce Stage-3 equations (53)-(59), with the
original scalar-dual subproblem solver. An independent regression check compares
the complete original-budget output against Model.design().
"""
from dataclasses import dataclass, asdict
import time
import numpy as np

from RIS_stage3.stage3_model import single_user_sca
from .physics_numpy import (audit_design, effective_user, geometric_initialization,
                            illumination, phase_levels, quantize_phase, sinr)


@dataclass(frozen=True)
class DesignBudget:
    ao: int = 1
    sca: int = 1
    phase_sweeps: int = 1

    def __post_init__(self):
        if any(not isinstance(v, int) or v < 0 for v in asdict(self).values()):
            raise ValueError('Iteration budgets must be nonnegative integers')


ORIGINAL_BUDGET = DesignBudget(3, 3, 2)


class InfeasibleDesign(RuntimeError):
    """Physical constraints are infeasible or final deployment audit failed."""


def project_feasible_beam(ctx, w, phase):
    """Project a rephased beam onto per-tone QoS halfspaces and total power ball.

    Rephasing each tone preserves every illumination magnitude and communication
    power. The subsequent projection solves the convex single-user intersection
    by a scalar power multiplier; it is only used outside the learned network.
    """
    w = np.asarray(w, dtype=np.complex128).copy()
    h = effective_user(ctx, phase)
    hn = np.linalg.norm(h, axis=1)
    if not np.all(np.isfinite(w)) or w.shape != h.shape or np.any(hn <= 1e-15):
        raise InfeasibleDesign('Non-finite beam, shape mismatch, or zero user channel')
    w *= np.exp(-1j*np.angle(np.sum(h*w, axis=1)))[:, None]
    v = h.conj()/hn[:, None]
    floor = np.sqrt(ctx.gamma*ctx.communication_noise)/hn
    minimum_power = float(np.sum(floor**2))
    if minimum_power > ctx.power_budget*(1+1e-12):
        raise InfeasibleDesign('Minimum communication power exceeds the total budget')
    if minimum_power >= ctx.power_budget*(1-1e-13):
        return v*floor[:, None]
    dot = np.sum(v.conj()*w, axis=1)
    parallel = dot.real
    perpendicular = w-v*dot[:, None]
    perpendicular_power = float(np.sum(np.abs(perpendicular)**2))
    def power(lam):
        return np.sum(np.maximum(parallel/(1+lam), floor)**2)+perpendicular_power/(1+lam)**2
    multiplier = 0.
    if power(0.) > ctx.power_budget:
        lo, hi = 0., 1.
        for _ in range(80):
            if power(hi) <= ctx.power_budget:
                break
            hi *= 2
        else:
            raise InfeasibleDesign('Could not bracket beam projection multiplier')
        for _ in range(65):
            middle = (lo+hi)/2
            if power(middle) > ctx.power_budget:
                lo = middle
            else:
                hi = middle
        multiplier = hi
    return (v*np.maximum(parallel/(1+multiplier), floor)[:, None]
            +perpendicular/(1+multiplier))


def optimize(ctx, w, phase, budget):
    """SCA plus discrete coordinates, starting at an audited feasible point."""
    w = np.asarray(w, dtype=np.complex128).copy()
    phase = np.asarray(phase, dtype=np.complex128).copy()
    first = audit_design(ctx, w, phase)
    if not first['feasible']:
        raise InfeasibleDesign(f"Optimizer requires feasible start: {first['reasons']}")
    history = [first['min_illumination']]
    statuses = []
    accepted_phases = 0
    levels = phase_levels(ctx.bits)
    for _ in range(budget.ao):
        h = effective_user(ctx, phase)
        w *= np.exp(-1j*np.angle(np.sum(h*w, axis=1)))[:, None]
        coupling = ctx.basis@phase
        for _ in range(budget.sca):
            d0 = np.sum(ctx.gd.conj()*w[None, :, :], axis=2)
            r0 = np.sum(ctx.gr.conj()*w, axis=1)
            eta = ctx.eta*np.abs(coupling)**2
            sw = ctx.gd*d0[:, :, None]+eta[:, :, None]*ctx.gr[None, :, :]*r0[None, :, None]
            constants = np.mean(np.abs(d0)**2+eta*np.abs(r0[None, :])**2, axis=1)
            candidate, info = single_user_sca(sw, constants, h, ctx.gamma*ctx.communication_noise)
            check = audit_design(ctx, candidate, phase)
            if not check['feasible']:
                raise InfeasibleDesign(f"SCA failed feasibility: {check['reasons']}")
            if check['min_illumination'] < history[-1]-2e-5:
                raise InfeasibleDesign('SCA decreased the illumination objective')
            w = candidate
            statuses.append(info)
            history.append(check['min_illumination'])
        for _ in range(budget.phase_sweeps):
            changed = False
            d = np.sum(ctx.gd.conj()*w[None, :, :], axis=2)
            rbeam = np.sum(ctx.gr.conj()*w, axis=1)
            dc, rc = np.abs(d)**2, ctx.eta*np.abs(rbeam)**2
            cc = ctx.basis@phase
            hu0 = np.sum(ctx.hd*w, axis=1)
            hu_r = ctx.user_ris_amplitude*np.sum(ctx.gr.conj()*w, axis=1)
            cu = ctx.user_basis@phase
            for n in range(ctx.nr):
                delta = levels-phase[n]
                ctest = cc[:, :, None]+ctx.basis[:, :, n, None]*delta
                scores = np.min(np.mean(dc[:, :, None]+rc[None, :, None]*np.abs(ctest)**2, axis=1), axis=0)
                utest = hu0[:, None]+hu_r[:, None]*(cu[:, None]+ctx.user_basis[:, n, None]*delta)
                feasible = np.min(np.abs(utest)**2/ctx.communication_noise, axis=0) >= ctx.gamma*(1-1e-5)
                scores[~feasible] = -np.inf
                j = int(np.argmax(scores))
                if scores[j] > history[-1]+1e-9:
                    cc += ctx.basis[:, :, n]*delta[j]
                    cu += ctx.user_basis[:, n]*delta[j]
                    phase[n] = levels[j]
                    history.append(float(scores[j]))
                    accepted_phases += 1
                    changed = True
            if not changed:
                break
    final = audit_design(ctx, w, phase)
    if not final['feasible']:
        raise InfeasibleDesign(f"Final deployment audit failed: {final['reasons']}")
    return w, phase, dict(history=history, statuses=statuses, final=final,
                         budget=asdict(budget), accepted_phase_updates=accepted_phases)


def traditional_design(ctx, budget=ORIGINAL_BUDGET):
    started = time.perf_counter()
    w, phase = geometric_initialization(ctx)
    initial = audit_design(ctx, w, phase)
    projected = not initial['feasible']
    if projected:
        w = project_feasible_beam(ctx, w, phase)
    w, phase, info = optimize(ctx, w, phase, budget)
    info.update(seconds=time.perf_counter()-started, initial=initial,
                initial_beam_projected=projected)
    return w, phase, info


def repair_design(ctx, candidate_w, candidate_phase, budget=DesignBudget(),
                  fallback_budget=ORIGINAL_BUDGET):
    """Return a deployable design or raise; never silently drop failed candidates."""
    started = time.perf_counter()
    raw = audit_design(ctx, candidate_w, candidate_phase, require_quantized=False)
    report = dict(raw=raw, quantized=None, final=None, fallback_used=False,
                  fallback_reason=None, correction=None, fallback=None,
                  correction_seconds=0., fallback_seconds=0.)
    try:
        if any(reason in raw['reasons'] for reason in ('shape', 'nonfinite', 'nonfinite_physics')):
            raise InfeasibleDesign(f"Invalid candidate: {raw['reasons']}")
        phase = quantize_phase(candidate_phase, ctx.bits)
        report['quantized'] = audit_design(ctx, candidate_w, phase)
        w = project_feasible_beam(ctx, candidate_w, phase)
        w, phase, report['correction'] = optimize(ctx, w, phase, budget)
    except (ValueError, FloatingPointError, InfeasibleDesign, RuntimeError) as error:
        report['correction_seconds'] = time.perf_counter()-started
        report['fallback_used'] = True
        report['fallback_reason'] = f'{type(error).__name__}: {error}'
        fallback_started = time.perf_counter()
        w, phase, report['fallback'] = traditional_design(ctx, fallback_budget)
        report['fallback_seconds'] = time.perf_counter()-fallback_started
    else:
        report['correction_seconds'] = time.perf_counter()-started
    report['final'] = audit_design(ctx, w, phase)
    report['total_seconds'] = time.perf_counter()-started
    if not report['final']['feasible']:
        raise InfeasibleDesign('Correction and fallback did not produce a deployable design')
    return w, phase, report
