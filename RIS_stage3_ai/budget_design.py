"""Audited anytime checkpoints; late atomic updates never enter the budget result.

This measures solutions AVAILABLE by a wall-clock budget, not a hard real-time
interruptible solver. CPU SCA/network calls may overrun; stopping time is separate.
"""
import math
import time
import numpy as np
import torch

from .physics_numpy import audit_design, geometric_initialization, quantize_phase
from .repair import DesignBudget, InfeasibleDesign, optimize, project_feasible_beam
from .unfolded_design import network_candidate

METHODS = ('traditional_anytime', 'untrained_anytime', 'learned_anytime')
BUDGETS = (.5, 2., 8.)


class NoTimelyDesign(InfeasibleDesign):
    def __init__(self, timing):
        super().__init__('No audited feasible checkpoint available within budget')
        self.timing = timing


def timed_design(make_context, method, network, seconds, *, clock=time.perf_counter):
    if method not in METHODS or not math.isfinite(seconds) or seconds <= 0:
        raise ValueError('Invalid method or wall-clock budget')
    device = None if network is None else network.raw_w_steps.device
    def sync():
        if device is not None and device.type == 'cuda':
            torch.cuda.synchronize(device)
    sync()
    start = clock()
    ctx = make_context()
    best = None
    events, failures = [], []

    def publish(w, phase, label):
        nonlocal best
        # Copy and final audit are charged before declaring the checkpoint ready.
        w, phase = np.array(w, copy=True), np.array(phase, copy=True)
        audit = audit_design(ctx, w, phase)
        sync()
        elapsed = clock()-start
        timely = elapsed <= seconds
        improved = audit['feasible'] and (best is None or
                      audit['min_illumination'] > best[2]['min_illumination'])
        events.append(dict(label=label, ready_seconds=elapsed, timely=timely,
                           feasible=audit['feasible'], min_illumination=audit['min_illumination']))
        if timely and improved:
            best = (w, phase, audit, elapsed, label)
        return timely

    w = phase = None
    try:
        w, phase = geometric_initialization(ctx)
        w = project_feasible_beam(ctx, w, phase)
        publish(w, phase, 'common_feasible_initialization')
    except (InfeasibleDesign, FloatingPointError, np.linalg.LinAlgError) as exc:
        failures.append(str(exc))
    if method != 'traditional_anytime' and clock()-start < seconds:
        try:
            cw, cp, _ = network_candidate(ctx, network, straight_through=True)
            cp = quantize_phase(cp, ctx.bits)
            cw = project_feasible_beam(ctx, cw, cp)
            if publish(cw, cp, 'network_and_projection'):
                # Refine the best feasible point, never replace it with a worse one.
                if best is not None:
                    w, phase = best[:2]
        except (InfeasibleDesign, FloatingPointError, np.linalg.LinAlgError) as exc:
            failures.append(str(exc))
    iterations = 0
    while w is not None and clock()-start < seconds:
        try:
            w, phase, _ = optimize(ctx, w, phase, DesignBudget(1, 1, 1))
            iterations += 1
            if not publish(w, phase, f'ao_{iterations}'):
                break
        except (InfeasibleDesign, FloatingPointError, np.linalg.LinAlgError) as exc:
            failures.append(str(exc))
            break
    sync()
    stopped = clock()-start
    timing = dict(budget_seconds=seconds, actual_stop_seconds=stopped,
                  atomic_overrun_seconds=max(0., stopped-seconds),
                  candidate_ready_seconds=None if best is None else best[3],
                  semantics='best audited checkpoint ready by deadline; not a hard realtime stop',
                  iterations=iterations, events=events, failures=failures)
    if best is None:
        raise NoTimelyDesign(timing)
    return ctx, best[0], best[1], dict(final=best[2], fallback_used=bool(failures),
                                    selected_checkpoint=best[4], budget_timing=timing)
