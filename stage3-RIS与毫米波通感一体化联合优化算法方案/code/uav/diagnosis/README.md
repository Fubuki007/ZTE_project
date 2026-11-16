# UAV foundation: paired cause diagnosis

This follow-up diagnoses the completed UAV hover experiment. It is a replay
of the same 300 geometries at RCS scales 1/10/100, not independent holdout
validation. No FAS, continuous UAV flight or tracking is introduced.

Before modifying code, GitHub backup `codex/pre-uav-diagnosis-20261116` was
pushed and independently verified at `5c0267d3828258020f5af9abb96464537c6b318f`.
Selected source, scripts, documents and small evidence are backed up;
credentials, local environments/caches, existing untracked historical output
and large MAT collections are excluded and preserved.

The immutable input is the 900-case server run from source release
`ad35a777ca7f697f2ea369db834f60f9f9f24277`. Input MAT hashes, its manifest
hash and all current source hashes are recorded and rechecked. Original
NoRIS and RIS results are retained. At every acquired anchor geometry,
the original no-RIS fine estimator is replayed and checked against its saved
position errors before interpreting any new estimator.

The common position is the saved Selected_NoRIS hover, selected with the
original 10 m noisy target-location prior. This removes position selection
as a confounder for the matched RIS tests. Every estimator in one condition
uses identical physical four-path data, two RIS configurations, sampled
symbols, projected noise and initial estimate. The existing `pr_dictionary`
and `pr_refine` are reused unchanged; neither requires FAS code. Candidate
selection receives parameters with truth and scattering fields removed.

Fifteen reported variants:

| ID | Method | Purpose |
|---:|---|---|
| 1 | Original_NoRIS | Saved selected no-RIS baseline |
| 2 | Original_RIS_own_position | Saved selected RIS baseline, its own position |
| 3 | RIS_matched_full | Same anchor position/acquisition, legacy four-path fit |
| 4 | RIS_matched_normalized | Fixed initial column normalization, full fit |
| 5 | RIS_matched_DD | Fit only DD to the same physical four-path data |
| 6 | RIS_matched_BIC | BIC among eight common DD-containing path masks |
| 7–8 | RIS_frozenW_full/DD | Keep original no-RIS transmit W; turn on RIS |
| 9 | NoRIS_noiseless | Remove fine-stage noise, keep noisy coarse initial point |
| 10–11 | RIS_noiseless_full/DD | Same noiseless diagnostic with RIS |
| 12 | RxBeam_NoRIS | Change acquisition receiver only; same legacy fine estimator |
| 13–15 | RxBeam_RIS_full/DD/BIC | Matched RIS estimators after receive-beam acquisition |

Variants 7–11 are diagnostics. Frozen W may fail the communication SINR
constraint after RIS is enabled; actual SINR/feasibility is recorded. Noiseless
data are not achievable performance. These variants must not be used as
deployable methods or to claim extra RIS gain. All failed acquisitions are
retained. Except saved variant 2, matched legacy variants share the original
no-RIS acquisition; receive-beam variants share their new acquisition.

BIC uses known fixed calibrated noise, eight masks containing DD, independent
retained complex amplitudes and the original ten nonlinear iterations.
The real parameter count is 4Q plus twice the retained linear rank. It adds
computation, not observed pilots. No hindsight or truth-selected model is used.

Receive-beam acquisition uses a unit-norm equal-response beam for the two
noisy-prior receive steering vectors. It replaces the single centre-element
full RD signal. The 64-channel sparse spatial samples and all original FFT,
peak threshold, angle estimation and fine-estimation rules are retained.
Full-band projected noise is jointly Gaussian with the original centre-channel
noise; at every saved spatial sample it equals the exact weighted sum of the
same 64 physical channel noises. Its variance remains the same thermal noise,
not a noise floor adjusted to a desired SNR.

This assumes coherent access to all existing 64 calibrated receive channels
over the full waveform for digital combining. It increases preprocessing
work relative to using one full RD channel plus sparse spatial samples.
It does not add antenna/RF chains, bandwidth, time or transmitted pilots.
Formal dimensions remain 12672 subcarriers, 256 coarse + 256 fine symbols,
16 Tx/64 Rx, 256 2-bit RIS elements, 1 W average power and 10 dB user SINR.
All other physical approximations of the foundation remain in force.

Two primary diagnostic contrasts are specified before this formal follow-up:
RCS=10 receive-beam versus original no-RIS failure-rate reduction; RCS=100
matched RIS BIC versus full-fit position RMSE reduction. Report paired
97.5% intervals for these two contrasts (Bonferroni for a two-contrast family)
and marginal 95% intervals for secondary comparisons. Bootstrap 4000 complete
geometries with seed 20261118. All 900 cases and 13500 metric rows are required.

Path diagnostics report projected, accumulated isolated DD/RD/DR/RR energies
divided by thermal noise, plus the coherent reflected-only to DD energy ratio.
They use truth only for offline diagnosis, never for beam/model selection.
These are not per-antenna input SNRs and not detection probabilities.

`test_uav_diagnosis` is a reduced, high-RCS local smoke test. Run it from this
module directory because the repository root contains a different function
also named `build_default_params`. The full-sized server pilot is MC0 at all
three RCS values. Neither supplies formal performance evidence.

Use the existing deployment tool from the repository root, adding
`-Experiment diagnosis` and the committed release SHA:

```powershell
./tools/uav-foundation-server.ps1 upload -Experiment diagnosis -Release <sha>
./tools/uav-foundation-server.ps1 test -Experiment diagnosis -Release <sha>
./tools/uav-foundation-server.ps1 pilot -Experiment diagnosis -Release <sha>
./tools/uav-foundation-server.ps1 run -Experiment diagnosis -Release <sha> -Workers 8
./tools/uav-foundation-server.ps1 status -Experiment diagnosis -Release <sha>
./tools/uav-foundation-server.ps1 fetch -Experiment diagnosis -Release <sha>
```

Per-case checkpoints contain parameters, priors, seeds, estimates, designs,
candidate fits/BIC choices, replay checks and physical path diagnostics.
Progress/logs are real per-worker state. Aggregation rechecks inputs/sources,
metrics, gating, retained failures, model choices, costs, radio dimensions,
power, quantized phases and feasible-design SINR before writing verification.
Large MATs and full logs stay on the server. Local retrieval is limited to
selected CSV/JSON/PNG evidence. No package installation is needed.
