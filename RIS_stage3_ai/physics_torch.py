"""Differentiable full-frequency version of the existing design physics."""
from dataclasses import dataclass
import torch

from .context import DesignContext


@dataclass
class TorchPhysics:
    gd: torch.Tensor
    basis: torch.Tensor
    gr: torch.Tensor
    hd: torch.Tensor
    user_basis: torch.Tensor
    eta: float
    user_ris_amplitude: float
    communication_noise: float
    gamma: float
    bits: int
    power_budget: float

    @classmethod
    def from_context(cls, ctx: DesignContext, device='cpu'):
        arrays = {name: torch.tensor(getattr(ctx, name), dtype=torch.complex128, device=device)
                  for name in ('gd', 'basis', 'gr', 'hd', 'user_basis')}
        return cls(**arrays, eta=ctx.eta, user_ris_amplitude=ctx.user_ris_amplitude,
                   communication_noise=ctx.communication_noise, gamma=ctx.gamma,
                   bits=ctx.bits, power_budget=ctx.power_budget)

    def effective_user(self, phase):
        return self.hd+self.user_ris_amplitude*(self.user_basis@phase)[:, None]*self.gr.conj()

    def sinr(self, w, phase):
        return torch.abs(torch.sum(self.effective_user(phase)*w, dim=1)).square()/self.communication_noise

    def illumination(self, w, phase):
        direct = torch.sum(self.gd.conj()*w[None, :, :], dim=2)
        reflected = torch.sum(self.gr.conj()*w, dim=1)
        coupling = self.basis@phase
        return (direct.abs().square()+self.eta*coupling.abs().square()*reflected.abs().square()[None, :]).mean(dim=1)

    def loss(self, w, phase, temperature=.03, qos_weight=5.):
        if temperature <= 0 or qos_weight < 0:
            raise ValueError('Invalid loss parameters')
        j = self.illumination(w, phase)
        soft_min = -temperature*torch.logsumexp(-j/temperature, dim=0)
        violation = torch.relu(1-self.sinr(w, phase)/self.gamma)
        return -soft_min+qos_weight*violation.square().mean()

    def project_power(self, w):
        ceiling = torch.as_tensor(self.power_budget, dtype=torch.float64, device=w.device)
        return w*torch.sqrt(ceiling/torch.maximum(w.abs().square().sum(), ceiling))

    def phase(self, angles, straight_through=False):
        continuous = torch.exp(1j*angles)
        if not straight_through:
            return continuous
        levels = torch.exp(2j*torch.pi*torch.arange(2**self.bits, dtype=torch.float64, device=angles.device)/(2**self.bits))
        indices = (continuous[:, None]-levels).abs().argmin(dim=1)
        hard = levels[indices]
        # Forward is deployable; backward is an explicitly biased surrogate.
        return continuous+(hard-continuous).detach()
