"""Small local mathematical checks. No formal training or RMSE claims."""
from dataclasses import fields, replace
import unittest
import numpy as np
from scipy.optimize import minimize
import torch
from threadpoolctl import threadpool_limits

from RIS_stage3.stage3_model import Config, Model
from .context import context_from_model
from .physics_numpy import (audit_design, effective_user, geometric_initialization,
                            illumination, quantize_phase, sinr)
from .physics_torch import TorchPhysics
from .repair import (DesignBudget, InfeasibleDesign, project_feasible_beam,
                     repair_design, traditional_design)
from .unfolded_design import UnfoldedConfig, UnfoldedDesigner, network_candidate


def fixture(ns=12, tx=2, ris=3):
    cfg = replace(Config(), ns=ns, tx_nx=tx, tx_ny=tx, ris_nx=ris, ris_ny=ris,
                  rx_nx=2, rx_ny=2, lc=8, lf=8, ao_iterations=2, sca_iterations=2,
                  phase_sweeps=2)
    model = Model(cfg)
    # Known values are used here only to independently check mathematical code.
    coarse = np.asarray(cfg.truth)+np.array([[.03, .2, .4, -.3], [-.02, -.1, -.3, .2]])
    return cfg, model, coarse, context_from_model(model, coarse)


class DesignTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        torch.set_num_threads(1)
        cls.thread_limits = threadpool_limits(limits=1)

    @classmethod
    def tearDownClass(cls):
        cls.thread_limits.restore_original_limits()

    def test_numpy_and_torch_match_existing_model(self):
        _, model, coarse, ctx = fixture()
        rng = np.random.default_rng(23)
        w = rng.normal(size=(ctx.ns, ctx.nt))+1j*rng.normal(size=(ctx.ns, ctx.nt))
        p = np.exp(1j*rng.uniform(-np.pi, np.pi, ctx.nr))
        gd, basis = model.target_design(coarse)
        expected = model.illumination(w, p, gd, basis)
        np.testing.assert_allclose(illumination(ctx, w, p), expected, rtol=1e-13)
        np.testing.assert_allclose(effective_user(ctx, p), model.effective_user(p), rtol=1e-13)
        np.testing.assert_allclose(sinr(ctx, w, p), model.sinr(w, p), rtol=1e-13)
        phy = TorchPhysics.from_context(ctx)
        tw, tp = torch.tensor(w), torch.tensor(p)
        np.testing.assert_allclose(phy.illumination(tw, tp).numpy(), expected, rtol=1e-12)
        np.testing.assert_allclose(phy.sinr(tw, tp).numpy(), model.sinr(w, p), rtol=1e-12)
        shuffled = replace(ctx, gd=ctx.gd[::-1], basis=ctx.basis[::-1])
        other = TorchPhysics.from_context(shuffled)
        torch.testing.assert_close(phy.loss(tw, tp), other.loss(tw, tp))

    def test_physical_complex_and_phase_gradients(self):
        _, _, _, ctx = fixture(ns=3, ris=2)
        phy = TorchPhysics.from_context(ctx)
        generator = torch.Generator().manual_seed(18)
        # Low-amplitude beams activate QoS penalties away from the ReLU boundary.
        w = (.02*torch.randn((ctx.ns, ctx.nt), dtype=torch.complex128, generator=generator)).requires_grad_()
        angles = torch.randn(ctx.nr, dtype=torch.float64, generator=generator, requires_grad=True)
        self.assertTrue(torch.autograd.gradcheck(
            lambda ww, aa: phy.loss(ww, torch.exp(1j*aa)), (w, angles),
            eps=1e-6, atol=2e-5, rtol=2e-4))

    def test_context_has_no_truth_dependency(self):
        cfg, model, coarse, ctx = fixture()
        poisoned = replace(cfg, truth=((np.nan,)*4, (np.nan,)*4))
        second = context_from_model(Model(poisoned), coarse)
        for field in fields(ctx):
            np.testing.assert_equal(getattr(ctx, field.name), getattr(second, field.name))
        self.assertNotIn('truth', {field.name for field in fields(ctx)})
        self.assertNotIn('model', {field.name for field in fields(ctx)})
        before = ctx.hd.copy()
        model.hd[:] = 0
        np.testing.assert_array_equal(ctx.hd, before)
        self.assertFalse(ctx.hd.flags.writeable)

    def test_traditional_solver_matches_original_end_to_end(self):
        cfg, model, coarse, ctx = fixture(ns=24, ris=4)
        expected_w, expected_p, expected = model.design(coarse)
        w, p, actual = traditional_design(ctx, DesignBudget(cfg.ao_iterations, cfg.sca_iterations, cfg.phase_sweeps))
        np.testing.assert_allclose(w, expected_w, rtol=1e-9, atol=1e-10)
        np.testing.assert_allclose(p, expected_p, rtol=0, atol=1e-12)
        np.testing.assert_allclose(actual['history'], expected['history'], rtol=1e-10, atol=1e-11)
        self.assertFalse(actual['initial_beam_projected'])

    def test_projection_against_independent_slsqp(self):
        _, _, _, ctx = fixture(ns=3, ris=2)
        rng = np.random.default_rng(324)
        _, p = geometric_initialization(ctx)
        candidate = 3*(rng.normal(size=(ctx.ns, ctx.nt))+1j*rng.normal(size=(ctx.ns, ctx.nt)))
        h = effective_user(ctx, p)
        target = candidate*np.exp(-1j*np.angle(np.sum(h*candidate, axis=1)))[:, None]
        w = project_feasible_beam(ctx, candidate, p)
        count = w.size
        def unpack(x):
            return (x[:count]+1j*x[count:]).reshape(w.shape)
        def objective(x):
            return np.sum(np.abs(unpack(x)-target)**2)
        target_vector = np.r_[target.real.ravel(), target.imag.ravel()]
        channel_rows = np.zeros((ctx.ns, count), dtype=complex)
        for i in range(ctx.ns):
            channel_rows[i, i*ctx.nt:(i+1)*ctx.nt] = h[i]
        real_jac = np.column_stack((channel_rows.real, -channel_rows.imag))
        imag_jac = np.column_stack((channel_rows.imag, channel_rows.real))
        constraints = [
            dict(type='ineq', fun=lambda x: np.r_[ctx.power_budget-np.sum(np.abs(unpack(x))**2),
                 np.sum(h*unpack(x), axis=1).real-np.sqrt(ctx.gamma*ctx.communication_noise)],
                 jac=lambda x: np.vstack((-2*x, real_jac))),
            dict(type='eq', fun=lambda x: np.sum(h*unpack(x), axis=1).imag,
                 jac=lambda x: imag_jac)]
        # Start the independent solver from a different feasible MRT design.
        initial, _ = geometric_initialization(ctx)
        initial = np.r_[initial.real.ravel(), initial.imag.ravel()]
        solved = minimize(objective, initial, jac=lambda x: 2*(x-target_vector),
                          constraints=constraints, method='SLSQP',
                          options=dict(ftol=1e-10, maxiter=350))
        self.assertTrue(solved.success, solved.message)
        np.testing.assert_allclose(w, unpack(solved.x), atol=5e-6, rtol=5e-6)
        self.assertTrue(audit_design(ctx, w, p)['feasible'])

    def test_audit_checks_every_tone(self):
        _, _, _, ctx = fixture()
        w, p = geometric_initialization(ctx)
        self.assertTrue(audit_design(ctx, w, p)['feasible'])
        w[ctx.ns//2] = 0
        audit = audit_design(ctx, w, p)
        self.assertFalse(audit['feasible'])
        self.assertIn('communication', audit['reasons'])
        self.assertEqual(audit['min_sinr'], 0.)

    def test_quantization_projection_correction_and_fallback(self):
        _, _, _, ctx = fixture(ns=10)
        w, p = geometric_initialization(ctx)
        unquantized = p*np.exp(.21j)
        fixed_w, fixed_p, report = repair_design(ctx, 5*w, unquantized)
        self.assertFalse(report['raw']['feasible'])
        self.assertIn('power', report['raw']['reasons'])
        self.assertFalse(report['quantized']['feasible'])
        self.assertFalse(report['fallback_used'])
        self.assertTrue(report['final']['feasible'])
        np.testing.assert_allclose(fixed_p, quantize_phase(fixed_p), atol=1e-12)
        self.assertTrue(np.all(np.diff(report['correction']['history']) >= -2e-5))
        self.assertGreaterEqual(report['total_seconds'], report['correction_seconds'])
        invalid = w.copy()
        invalid[0, 0] = np.nan
        _, _, failed = repair_design(ctx, invalid, p, fallback_budget=DesignBudget(1, 1, 1))
        self.assertTrue(failed['fallback_used'])
        self.assertIn('nonfinite', failed['fallback_reason'])
        self.assertTrue(failed['final']['feasible'])
        self.assertGreater(failed['fallback_seconds'], 0)
        self.assertGreaterEqual(failed['total_seconds'], failed['correction_seconds']+failed['fallback_seconds'])

    def test_genuinely_infeasible_context_raises(self):
        _, _, _, ctx = fixture()
        ctx = replace(ctx, gamma=1e8)
        w, p = geometric_initialization(ctx)
        with self.assertRaises(InfeasibleDesign):
            repair_design(ctx, w, p)

    def test_unfolded_parameter_gradient_and_update(self):
        _, _, _, ctx = fixture(ns=6, ris=3)
        phy = TorchPhysics.from_context(ctx)
        w0, p0 = geometric_initialization(ctx)
        w0 = torch.tensor(w0)
        angles = torch.angle(torch.tensor(p0))
        network = UnfoldedDesigner(UnfoldedConfig(layers=2))
        def objective():
            w, p = network(phy, w0, angles)
            return phy.loss(w, p)
        loss = objective()
        loss.backward()
        for parameter in network.parameters():
            self.assertTrue(torch.isfinite(parameter.grad).all())
            self.assertGreater(float(parameter.grad.abs().max()), 1e-9)
        # Central difference of the complete two-layer map, including curvature.
        for parameter in network.parameters():
            analytic = parameter.grad[0].item()
            original = parameter[0].item()
            with torch.no_grad():
                parameter[0] = original+1e-5
            plus = objective().item()
            with torch.no_grad():
                parameter[0] = original-1e-5
            minus = objective().item()
            with torch.no_grad():
                parameter[0] = original
            self.assertAlmostEqual(analytic, (plus-minus)/2e-5, delta=max(2e-6, abs(analytic)*2e-3))
        before = {name: value.detach().clone() for name, value in network.named_parameters()}
        optimizer = torch.optim.Adam(network.parameters(), lr=.01)
        for _ in range(4):
            optimizer.zero_grad()
            ww, pp = network(phy, w0, angles, straight_through=True)
            phy.loss(ww, pp).backward()
            optimizer.step()
        self.assertTrue(any(not torch.equal(before[name], value.detach()) for name, value in network.named_parameters()))
        for step, bound in zip(network.step_sizes(), [.5, .5]):
            self.assertTrue(torch.all((step > 0) & (step < bound)))
        network.eval()
        candidate_w, candidate_p, timing = network_candidate(ctx, network)
        self.assertLessEqual(np.sum(np.abs(candidate_w)**2), ctx.power_budget*(1+1e-12))
        np.testing.assert_allclose(candidate_p, quantize_phase(candidate_p), atol=1e-12)
        _, _, final = repair_design(ctx, candidate_w, candidate_p)
        self.assertTrue(final['final']['feasible'])
        self.assertGreater(timing['candidate_seconds'], 0)


if __name__ == '__main__':
    unittest.main(verbosity=2)
