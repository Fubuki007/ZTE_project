"""Learned bounded step sizes in alternating physical gradient updates.

Evaluation still requires first derivatives of the physical objective. Training
also differentiates through those updates. Neither mode consumes target truth.
"""
from dataclasses import dataclass, asdict
import math
import time
import torch
from torch import nn

from .physics_numpy import geometric_initialization
from .physics_torch import TorchPhysics


@dataclass(frozen=True)
class UnfoldedConfig:
    layers: int = 6
    temperature: float = .03
    qos_weight: float = 5.
    initial_w_step: float = .1
    initial_phase_step: float = .2
    max_w_step: float = .5
    max_phase_step: float = .5  # radians after RMS gradient normalization
    gradient_epsilon: float = 1e-12

    def __post_init__(self):
        if not isinstance(self.layers, int) or self.layers < 1:
            raise ValueError('At least one layer is required')
        values = [value for key, value in asdict(self).items() if key != 'layers']
        if not all(math.isfinite(value) for value in values):
            raise ValueError('Non-finite unfolding configuration')
        if self.temperature <= 0 or self.qos_weight < 0 or self.gradient_epsilon <= 0:
            raise ValueError('Invalid loss/normalization configuration')
        if not 0 < self.initial_w_step < self.max_w_step or not 0 < self.initial_phase_step < self.max_phase_step:
            raise ValueError('Initial steps must lie strictly inside positive bounds')


class UnfoldedDesigner(nn.Module):
    def __init__(self, config=UnfoldedConfig()):
        super().__init__()
        self.config = config
        def logit(initial, bound):
            fraction = initial/bound
            return math.log(fraction/(1-fraction))
        self.raw_w_steps = nn.Parameter(torch.full((config.layers,), logit(config.initial_w_step, config.max_w_step), dtype=torch.float64))
        self.raw_phase_steps = nn.Parameter(torch.full((config.layers,), logit(config.initial_phase_step, config.max_phase_step), dtype=torch.float64))

    def step_sizes(self):
        return (self.config.max_w_step*self.raw_w_steps.sigmoid(),
                self.config.max_phase_step*self.raw_phase_steps.sigmoid())

    def forward(self, physics, initial_w, initial_angles, *, straight_through=False, create_graph=None):
        if torch.is_inference_mode_enabled():
            raise RuntimeError('Physical gradient updates need autograd; use eval(), not inference_mode().')
        cfg = self.config
        if create_graph is None:
            create_graph = self.training
        if initial_w.dtype != torch.complex128 or initial_angles.dtype != torch.float64:
            raise ValueError('v1 uses complex128 waves and float64 phases')
        if initial_w.shape != physics.hd.shape or initial_angles.shape != (physics.basis.shape[-1],):
            raise ValueError('Malformed initial configuration')
        if self.raw_w_steps.device != initial_w.device or physics.hd.device != initial_w.device:
            raise ValueError('Network, physics and initial values must use the same device')
        with torch.enable_grad():
            w = initial_w.detach().clone().requires_grad_(True)
            angles = initial_angles.detach().clone().requires_grad_(True)
            w_steps, phase_steps = self.step_sizes()
            if not create_graph:
                w_steps, phase_steps = w_steps.detach(), phase_steps.detach()
            for index in range(cfg.layers):
                phase = physics.phase(angles, straight_through)
                loss_w = physics.loss(w, phase, cfg.temperature, cfg.qos_weight)
                grad_w, = torch.autograd.grad(loss_w, w, create_graph=create_graph)
                # RMS Euclidean norm per subcarrier; not per real scalar.
                scale_w = torch.sqrt(grad_w.abs().square().sum(dim=1).mean()+cfg.gradient_epsilon**2)
                w = physics.project_power(w-w_steps[index]*grad_w/scale_w)
                if not create_graph:
                    w = w.detach().requires_grad_(True)
                phase = physics.phase(angles, straight_through)
                loss_phase = physics.loss(w, phase, cfg.temperature, cfg.qos_weight)
                grad_phase, = torch.autograd.grad(loss_phase, angles, create_graph=create_graph)
                scale_phase = torch.sqrt(grad_phase.square().mean()+cfg.gradient_epsilon**2)
                angles = angles-phase_steps[index]*grad_phase/scale_phase
                if not create_graph:
                    angles = angles.detach().requires_grad_(True)
            phase = physics.phase(angles, straight_through)
        if not torch.isfinite(w).all() or not torch.isfinite(phase).all():
            raise FloatingPointError('Non-finite unfolding output')
        return (w, phase) if create_graph else (w.detach(), phase.detach())


def network_candidate(ctx, network, *, straight_through=True):
    """Timed forward pass including input transfer and output transfer.

    This helper does not label an arbitrary initialized network as trained.
    Checkpoint selection/identity belongs to the training and comparison runners.
    """
    device = network.raw_w_steps.device
    if device.type == 'cuda':
        torch.cuda.synchronize(device)
    started = time.perf_counter()
    physics = TorchPhysics.from_context(ctx, device)
    w0, p0 = geometric_initialization(ctx)
    w = torch.tensor(w0, dtype=torch.complex128, device=device)
    angles = torch.angle(torch.tensor(p0, dtype=torch.complex128, device=device))
    with torch.no_grad():
        w, phase = network(physics, w, angles, straight_through=straight_through, create_graph=False)
    w_np, phase_np = w.cpu().numpy().copy(), phase.cpu().numpy().copy()
    if device.type == 'cuda':
        torch.cuda.synchronize(device)
    w_steps, phase_steps = network.step_sizes()
    return w_np, phase_np, dict(
        candidate_seconds=time.perf_counter()-started,
        includes='physics tensor transfer, initialization, gradient updates, output transfer',
        device=str(device), config=asdict(network.config), straight_through=straight_through,
        w_steps=w_steps.detach().cpu().tolist(), phase_steps=phase_steps.detach().cpu().tolist())
