"""Observable design inputs. No target truth, received future data, or Model handle."""
from dataclasses import dataclass
import numpy as np

from RIS_stage3.stage3_model import Model


@dataclass(frozen=True)
class DesignContext:
    gd: np.ndarray             # target, subcarrier, transmit element
    basis: np.ndarray          # target, subcarrier, RIS element
    gr: np.ndarray             # subcarrier, transmit element
    hd: np.ndarray             # direct user row channel (not conjugated)
    user_basis: np.ndarray     # subcarrier, RIS element
    eta: float
    user_ris_amplitude: float
    communication_noise: float
    gamma: float
    bits: int

    def __post_init__(self):
        for name in ('gd', 'basis', 'gr', 'hd', 'user_basis'):
            array = np.array(getattr(self, name), dtype=np.complex128, copy=True)
            if not np.all(np.isfinite(array)):
                raise ValueError(f'Non-finite physical input: {name}')
            array.setflags(write=False)
            object.__setattr__(self, name, array)
        if self.gd.ndim != 3 or self.gd.shape[0] != 2:
            raise ValueError('v1 requires exactly two targets')
        _, ns, nt = self.gd.shape
        if ns < 1 or nt < 1 or self.basis.ndim != 3:
            raise ValueError('Empty or malformed physical arrays')
        nr = self.basis.shape[-1]
        if nr < 1 or self.basis.shape != (2, ns, nr):
            raise ValueError('Target RIS response shape mismatch')
        if self.gr.shape != (ns, nt) or self.hd.shape != (ns, nt):
            raise ValueError('Transmit/user channel shape mismatch')
        if self.user_basis.shape != (ns, nr):
            raise ValueError('User RIS response shape mismatch')
        values = [self.eta, self.user_ris_amplitude, self.communication_noise, self.gamma]
        if not np.all(np.isfinite(values)) or self.eta < 0 or self.user_ris_amplitude < 0:
            raise ValueError('Invalid channel scalars')
        if self.communication_noise <= 0 or self.gamma <= 0 or self.bits != 2:
            raise ValueError('v1 requires positive noise/QoS and 2-bit RIS')

    @property
    def ns(self):
        return self.gd.shape[1]

    @property
    def nt(self):
        return self.gd.shape[2]

    @property
    def nr(self):
        return self.basis.shape[2]

    @property
    def power_budget(self):
        # Same total normalized power as the existing single-user SCA solver.
        return float(self.ns)


def context_from_model(model: Model, coarse):
    """Only coarse estimates are used to construct target directions/responses."""
    coarse = np.asarray(coarse, dtype=float)
    if coarse.shape != (2, 4) or not np.all(np.isfinite(coarse)):
        raise ValueError('Expected two finite [R, v, theta_from_z, phi] coarse estimates')
    if np.any(coarse[:, 0] <= 0):
        raise ValueError('Coarse ranges must be positive')
    gd, basis = model.target_design(coarse)
    cfg = model.cfg
    return DesignContext(
        gd=gd, basis=basis, gr=model.atbr/np.sqrt(len(model.tx)),
        hd=model.hd, user_basis=model.user_basis, eta=cfg.hop_amplitude**2,
        user_ris_amplitude=cfg.user_ris_amplitude,
        communication_noise=cfg.communication_noise, gamma=cfg.gamma, bits=cfg.bits)
