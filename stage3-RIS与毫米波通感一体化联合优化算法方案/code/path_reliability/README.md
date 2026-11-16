# Weak-path reliability: existence experiment

2026-11-15. This is a screening experiment for a research hypothesis, not a
newly established method, a proof of novelty, or an expected performance gain.

Full run completed and audited on 2026-11-16: see
[results and limitations](RESULTS_20261116.md). Original simulation release and
checkpoints were preserved; a separate finalizer release repaired the report schema.

Before editing, the unchanged tracked project was pushed to
`codex/pre-path-reliability-20261115`; the remote SHA was independently read
from the server and equals `f62f8929fd2f8ee848af7339f4fa0374bdc7b23a`.
The backup includes tracked source, scripts, documentation and selected
results. Existing untracked historical output, credentials, environments,
caches and large raw MAT collections are preserved locally and excluded.

## Question and fixed resources

Can handling weak nuisance paths improve actual position estimation beyond
the existing four-independent-complex-amplitude fit? Do ordinary AIC/BIC or
ridge already explain any benefit, and is a RIS better than a strong no-RIS
reference under the same radio budget?

- Baseline: the user-specified Stage-3 code. All original functions remain
  unchanged. `pr_dictionary.m` is an isolated copy of its local dictionary
  (only function name and trailing whitespace changed); the smoke test
  verifies this provenance.
- Formal: all original 300 paired geometries x 13 SNR (-50:5:10), 3900 cases.
  Preserve 28 GHz, 16 Tx/64 Rx, 256 RIS/2 bit, 12672 subcarriers, coarse 256 +
  fine 256 symbols, fine 256 subcarriers/64 sampled symbols, power and 10 dB
  user SINR constraints. No FAS, extra aperture, added pilots or guard budget.
- Reuse original input release `aafa68081d27ee7b0fb379f4823c9fb48ea06194` and
  fixed-array localization release `554ff78b42b720939272c60e0d9f0cc37acd82a9`.
  Seeds, coarse estimates, fixed designs, fine symbols and noise are replayed.
- Two RIS conditions: existing energy-directed design and existing PEB-directed
  fixed design. Every candidate within a condition receives exactly the same
  physical four-path data, projection basis and coarse initial point.
- Original acquisition gating remains: unlocked cases return the coarse
  estimate and remain in every statistic. This does not test RIS-assisted
  initial acquisition or reacquisition under blockage.
- Original center-frequency array approximation, radial-velocity model,
  spatial geometry and normalized noise/pathloss are retained. Actual
  localization RMSE is the metric; no deployment accuracy claim is implied.

## Estimators and diagnostic

For each RIS condition:

1. `Full_legacy`: unmodified Stage-3 four-path fit, checked against its saved
   estimate after target matching. It isolates implementation/numerical drift.
2. `Full_normalized`: four-path fit with fixed initial column normalization.
3. `DD_only`: direct path fit to the same physical four-path observations.
4. `AIC` and `BIC`: choose among the eight masks containing DD and any subset
   of RD/DR/RR. A common mask is used for both targets; per-target 64-mask
   search is outside this screening experiment. All models use the original
   ten nonlinear iterations and local interval, with independent retained
   path amplitudes across targets, shared across two configurations.
5. `Ridge_GCV`: choose full-model lambda from 0, 1e-6, 1e-4, 1e-2, 1, 100,
   10000. DD amplitudes are unpenalized. Reflected amplitudes are shrunk after
   whitening and fixed initial column normalization. This is an ordinary
   coordinate-defined ridge prior, not a physical prior on target RCS.
6. `Oracle_bank_hindsight`: choose the candidate with smallest actual XYZ
   error on that realized noise. This uses truth, is optimistic selection,
   and is neither achievable nor a rigorous upper/lower bound. It does not
   demonstrate that a feasible selector can capture the apparent headroom.

AIC/BIC use known calibrated noise variance (the original simulation noise)
and the complex-Gaussian likelihood. Real parameter count is 4Q plus twice
the selected linear rank. GCV uses local geometric degrees of freedom 4Q
plus twice the linear ridge hat trace. This is a nonlinear-risk approximation;
the actual RMSE, not GCV or selected-model CRB, determines the result.
Selectors receive no test truth, true gains or realized errors. Those fields
are removed before calling the candidate bank.
Saved per-path SNR diagnostics are isolated projected total signal energies
divided by noise variance, including accumulation; they are not the original
per-sample input SNR and exclude coherent cross terms. Dictionary coherence
is also saved to separate strength from path distinguishability.

The no-RIS energy reference reuses the original full fine estimator. An
additional fixed no-RIS PEB beam design uses the common coarse estimate,
equal nominal gains, original SQP (40 iterations per segment, up to three
starts), and DD fine fitting. It has the same RF/radio resources, with search
time separately recorded. No-RIS signals are explicitly a physical
counterfactual; signals within each RIS condition always retain all paths.

Original synthesis uses a common target alpha across the four paths, while
all retained amplitudes are estimated independently. No gain is attributed to
tying those four true amplitudes. Robustness to other target scattering
models is a subsequent question, not covered by this experiment.

## Verification, statistics and execution

Local runs are reduced smoke tests only: dictionary provenance, exact
physical synthesis, legacy replay, normalization sensitivity, signal/noise
scaling invariance, selector minima, constrained no-RIS design and end-to-end
outputs. Server pilots replay complete-size MC0 at -20 and +10 dB. Neither
smoke nor pilot results substitute for the formal 3900 cases.

The formal runner hashes sources and both immutable input checkpoints,
saves every case atomically, rejects manifest mismatches on resume, and
records per-worker phase, PID, genuine count and UTC timestamp. The launcher
uses a process lock and detached supervision with failure propagation.

Final aggregation requires all 3900 cases and independently recomputes
position errors, selectors and hindsight choices, validates reference replay,
input hashes, seeds, failures, power, SINR, 2-bit phases and cost histories.
Only then are `verification.json` and COMPLETE written. All coarse failures
and infeasible designs are retained; no sample is silently discarded.

Before seeing formal results, the primary statistic is specified as the
equal-weight mean of per-SNR RMSE percentage reductions over -20:5:10 dB,
relative to Full_normalized within each RIS condition. Show all 13 SNRs and
both no-RIS baselines as well. Bootstrap 4000 times with seed 20261115,
resampling complete MC geometries to preserve pairing across SNR and methods.
Intervals are exploratory marginal intervals, not multiplicity-adjusted.
Oracle selection is excluded from the primary confidence comparisons.

Use `tools/ris-path-reliability-server.ps1` with upload/test/pilot/run/status/fetch.
Formal output is `path_reliability/results_full`; large raw MATs stay on the
server. After verified submission, do not poll until the user requests it.

If normalized full fitting alone explains the change, classify it as a
numerical issue. If ordinary regularization/model selection captures all
benefit, do not claim a new joint method. Hindsight-only benefit, no net
advantage over no-RIS, or no meaningful headroom weakens the research case.
