# UAV-BS + fixed passive RIS: foundation experiment

This is a first deployment validation, not a new trajectory algorithm or a
demonstration of dynamic tracking. It contains no FAS, antenna selection or
added RF chains. The original Stage-3 functions are reused without modification.

## Physical model and declared approximations

- One UAV-BS hovers at 80 m during acquisition and fine estimation. Compare
  the fixed point (0,0,80) with selection from a 3x3 horizontal grid at
  x/y = -40,0,40 m. Relocation occurs before the mission; flight time, energy,
  attitude errors and in-CPI platform motion are outside this first experiment.
- Two stationary ground targets: nominal (180,-25,0), (220,35,0) m, with
  independent 8 m horizontal Gaussian variation. Two communication users are
  fixed at (70,-50,0), (90,50,0). RIS at (260,60,25) m faces global -x.
  Local +z points down, using the proper rotation diag(1,-1,-1). Target height
  is not supplied to the inherited 3D estimator as a ground-plane constraint.
- The initial placement designer receives an external coarse target-location
  prior with independent 10 m horizontal error and known communication CSI.
  It never receives target scattering, testing noise or exact target positions.
  Every method obtains the same prior. Prior acquisition cost is not modeled.
- 1 W total average radiated power; isotropic element patterns, ideal lossless
  array/RIS hardware, free-space LoS, 290 K and 7 dB receiver noise figure.
  Communication field gain is lambda/(4*pi*R). Monostatic target field gain is
  lambda*sqrt(sigma)/((4*pi)^(3/2)*R^2). RCS scales 1/10/100 m^2 multiply
  relative target RCS [1,.8]. Noise is k*T*B*F, identical across methods,
  positions and RCS scales. Numerical radar normalization uses a fixed
  200 m, 1 m^2 reference, which cancels out of physical SNR.
- RIS uses the existing aperture/angle-dependent passive panel field response,
  with the original DD/RD/DR/RR paths and unknown fitted complex path gains.
  No arbitrary RIS amplification, direct-path blockage, clutter, residual SI,
  atmospheric losses, mutual coupling or calibrated bistatic RCS is introduced.
  Centre-frequency array steering and ideal frequency-domain OFDM (without
  explicit CP violation/ISI) are inherited approximations.

## Resources, design and inference

Formal: 28 GHz, 120 kHz spacing, **12672 subcarriers**, 16 Tx/64 Rx,
256 2-bit RIS elements, 2 users with 10 dB SINR, **256 coarse + 256 fine
symbols**. The inherited full RD grid, coarse 384x64 samples and fine 256x64
samples are unchanged. The two fine RIS configurations share that fine-stage
sample budget; there are no additional observed pilots. Acquisition is 4.574 ms.

Placement maximizes a worst-target, incoherent four-path energy proxy evaluated
at the noisy prior. This is finite candidate selection, not global continuous
optimization. Beams use minimum-power communication ZF plus residual power
in a communication-nullspace sensing direction. This heuristic is shared by
all methods; it is not the original SCA solver or a claimed optimum. Two
quantized RIS configurations follow the original target-phase weighting rule.

All four methods run the original full-bandwidth DD coarse acquisition with
RIS off, then the same projected continuous-parameter fine estimator. Same
seeds pair symbols/noise across methods; fixed-position RIS/no-RIS coarse
observations are exactly identical. Noise variance is never redefined to force
a desired received SNR. Failed acquisition returns the coarse estimate and
remains in every statistic. This protocol cannot demonstrate RIS-assisted
initial acquisition or reacquisition under blockage.

Methods: Fixed_NoRIS, Fixed_RIS, Selected_NoRIS, Selected_RIS. The two selected
methods choose their own best feasible grid point using the same search budget.
Actual RMSE therefore includes the effect of the complete placement/design rule.

## Predeclared validation and execution

300 paired geometries x 3 RCS scales = **900 cases**, each containing all
four methods. Primary comparison: selected versus fixed position **without
RIS**, pooled 3D position RMSE at RCS=10 m^2. Also report all RCS scales,
coarse/fine RMSE, velocity nuisance error, capture/failure/feasibility rates,
and RIS increments with and without placement selection. A failure is missing
capture, unavailable feasible fine design or any target position error >5 m.
No failed sample is dropped. Paired bootstrap resamples complete geometries
4000 times (seed 20261117); 95% intervals are marginal, not multiplicity-adjusted.

The smallest accepted result is an audited empirical deployment gain; a useful
RIS contribution must separately beat Selected_NoRIS. A positive position gain
does not establish that RIS is useful, that a new method is novel, or that an
energy/trajectory benefit survives flight constraints.

`test_uav_foundation` is a **reduced local smoke test**, with artificially strong
RCS solely to exercise all fine-estimation branches. It supplies no performance
evidence for the formal conditions. `run_uav_foundation
('pilot',...)` runs all three RCS conditions for one complete-size server
geometry; it is not a substitute for the full experiment. `run_server.sh`
launches immutable full-size workers with per-case atomic checkpoints, source
hash/parameter manifests, UTC progress and failure propagation. Aggregation
requires all 900 cases and recomputes errors and physical design constraints.
Use `tools/uav-foundation-server.ps1` for deployment, pilot, launch and retrieval.

Before editing, GitHub backup `codex/pre-uav-foundation-20261116` was verified
at `107082692b2c0e936e2aae5c78e02015e69d518d`. Only selected source/scripts,
documentation and small audit summaries are backed up. Existing untracked
outputs, credentials, environments, caches and large raw results stay in place.

The completed 900-case server experiment and its limitations are reported in
[RESULTS_20261116.md](RESULTS_20261116.md). The source release remains
`ad35a777ca7f697f2ea369db834f60f9f9f24277`; later result-documentation commits
do not replace that immutable simulation release.
