# Learnings

## [LRN-20261012-001] correction

**Priority**: high
**Status**: promoted
**Area**: simulation

用户明确：正式脚本必须全量、在服务器跑；本地可以跑冒烟。已加入 AGENTS.md 和持久记忆。不得把缩小规模验证当成交付的正式实验。

Corrections, insights, and knowledge gaps captured during development.

**Categories**: correction | insight | knowledge_gap | best_practice

---

## [LRN-20260916-001] correction

**Logged**: 2026-09-16T00:00:00+08:00
**Priority**: high
**Status**: resolved
**Area**: docs

### Summary
Enterprise delivery needs an understandable, maintainable codebase, not just a runnable minimal archive.

### Details
The user clarified that software engineers should be able to read comments, locate configuration ownership, and safely modify the SI implementation. The initial package retained stale research and prototype references and unused legacy settings.

### Suggested Action
Keep a single entry point, document dimensions/units and edit ownership, remove dead settings and misleading comments, validate parameter contracts, and rerun MATLAB plus archive checks after every package update.

### Metadata
- Source: user_feedback
- Related Files: ZTE_ISAC_SI_Delivery_v1.0_20260916/*.m, ZTE_ISAC_SI_Delivery_v1.0_20260916/README.md
- Tags: delivery, maintainability, matlab

### Resolution
- **Resolved**: 2026-09-16T00:00:00+08:00
- **Notes**: The package now has a constrained configuration contract, concise function interfaces, documented data dimensions and model assumptions, and regression checks from the unpacked directory.

---

## [LRN-20260729-001] correction

**Logged**: 2026-07-29T15:57:28+08:00
**Priority**: medium
**Status**: resolved
**Area**: config

### Summary
Treat a supplied plot as a style reference unless the user explicitly asks to reproduce its data and series.

### Details
The first plotting attempt copied four comparison curves from the reference, combined three panels into one figure, and exported PNG in addition to FIG. The requested output is one project-result curve per figure, three independent figures, and FIG-only graphics output.

### Suggested Action
Separate visual style from data series, figure count, and output format before implementing reference-based plots.

### Metadata
- Source: user_feedback
- Related Files: task_output_snr_sweep.m
- Tags: matlab, plotting, output-format, reference-style

### Resolution
- **Resolved**: 2026-07-29T15:57:28+08:00
- **Notes**: Updated the actual simulation plot path and removed the reference-data reproduction script.

---

## [LRN-20260731-001] correction

**Logged**: 2026-07-31T21:55:00+08:00
**Priority**: medium
**Status**: resolved
**Area**: config

### Summary
MATLAB default TeX legend interpreter corrupts Chinese labels; use 'Interpreter','none' and a CJK-capable font.

### Details
The SI-suppression RMSE-vs-SNR Nature-style figures showed garbled legend text for the Chinese method labels (traditional ZF, null-space, Lagrange). Cause: the legend Interpreter defaulted to 'tex', which cannot render CJK characters; Times New Roman also lacks CJK glyphs. Fix: legend(..., 'Interpreter','none', 'FontName','Microsoft YaHei'); axes/ticks stay Times New Roman for the Nature style.

### Suggested Action
For any MATLAB figure containing Chinese text, set 'Interpreter','none' on the legend/text objects and use a font with CJK glyphs; never rely on the default TeX interpreter for Chinese.

### Metadata
- Source: user_feedback
- Related Files: plot_si_suppression_nature.m
- Tags: matlab, plotting, legend, chinese-font, interpreter

### Resolution
- **Resolved**: 2026-07-31T21:55:00+08:00
- **Notes**: Patched the legend call in plot_si_suppression_nature.m and re-exported .fig/.png; user asked to remember this permanently.

---

## [LRN-20260825-001] correction

**Logged**: 2026-08-25T20:40:00+08:00
**Priority**: high
**Status**: resolved
**Area**: plotting

### Summary
Never generate MATLAB .fig files with Python/scipy; always use MATLAB itself to save/edit .fig.

### Details
A Python-generated `.fig` corrupted `hgM_070000.GraphicsObjects` into a generic struct. MATLAB `openfig` then failed with `Unrecognized field name "Format3Data"` because the MATLAB internal `matlab.graphics.internal.figfile.GraphicsObjects` object was not preserved. The valid fix is to generate the `.fig` through a MATLAB script (e.g. `draw_angle_rmse_snr_si_sic_7pt.m`) and let Python only output PNG/EPS.

### Suggested Action
- Python scripts may create PNG/EPS only.
- Any `.fig` creation/editing must be done in MATLAB via `savefig` / `openfig`.
- If a `.fig` must be produced without MATLAB, do not hand-serialize HG structures with scipy.

### Metadata
- Source: user_feedback
- Related Files: fig/angle_rmse_vs_snr_si_suppression_sic_7pt.fig, draw_angle_rmse_snr_si_sic_7pt.py, draw_angle_rmse_snr_si_sic_7pt.m
- Tags: matlab, fig, scipy, Format3Data, plotting

### Resolution
- **Resolved**: 2026-08-25T20:40:00+08:00
- **Notes**: Regenerated the .fig with MATLAB, updated the Python script to stop writing .fig, and logged this rule to prevent recurrence.

---

## [LRN-20260923-001] insight

**Logged**: 2026-09-23T12:00:00+08:00
**Priority**: high
**Status**: pending
**Area**: tests

### Summary
In the beta_SI sweep, Nullspace can have a higher theta-RMSE RMS than ZF at very high SI even though its typical trial is better; a small number of ESPRIT angle outliers dominate the RMS.

### Details
The aggregate uses `sqrt(mean(rmse_theta.^2,3))`, so it is sensitive to catastrophic angular trials. At beta_SI=1e6, Nullspace theta RMSE had median 12.89 deg, but P95 41.48 deg and max 69.85 deg; ZF had median 15.82 deg, P95 18.03 deg, max 19.10 deg. Diagnostic trials showed Nullspace estimates clipping to theta=90 deg after residual-SI spatial phase corruption, while range/velocity peaks remain separately detectable. The estimator sums receive antennas for RD detection but uses the full receive snapshot and adjacent-element phase differences for angle, so angle can fail independently. At beta=1, Nullspace's SI benefit is unnecessary while its SI-aware nullspace correction plus broadside transmit-reference approximation changes angular conditioning, explaining a modest baseline penalty.

### Suggested Action
Report median/P95/max alongside RMS, label the plotted metric as elevation-theta RMSE, and treat invalid direction-cosine/clipped ESPRIT outputs as angular outliers rather than evidence that all Nullspace trials are worse. Consider a target-aware MIMO matched filter or a robust spatial-angle estimator for a follow-up, without changing the paper baseline silently.

### Metadata
- Source: self_reflection
- Related Files: joint_estimator_fast.m, design_precoder.m, task_si_strength_3methods_beta1_to_1e6_mc80_aggregate.m
- Tags: matlab, angle-rmse, nullspace, zf, outliers, esp​​rit

---



## [LRN-20261002-001] best_practice

**Logged**: 2026-10-02T00:00:00+08:00
**Priority**: high
**Status**: pending
**Area**: algorithm

### Summary
Check the complex cross-term sign with a one-element scalar test before running RIS sweeps.

### Details
For a unit-modulus coordinate update, expand the objective explicitly and verify whether the update maximizes or minimizes the cross term. A monotonic objective history is a required smoke-test invariant.

### Metadata
- Source: error
- Related Files: optimize_ris_target_phase.m
- Tags: ris, complex-optimization, smoke-test

---

## [LRN-20261002-001] best_practice

**Logged**: 2026-10-02T14:40:00+08:00
**Priority**: medium
**Status**: pending
**Area**: tests

### Summary
Paired Monte Carlo comparisons must reuse the same random noise seed across schemes.

### Details
The first RIS plus self-interference smoke-test draft included the scheme index in the AWGN seed. That made each scheme statistically valid but removed strict sample pairing. Removing the scheme index preserves identical AWGN for No RIS and RIS within each trial, beta, and waveform.

### Suggested Action
Keep random-data and AWGN seeds keyed by trial and scenario only; use separate streams only when intentionally testing independent realizations.

### Metadata
- Source: simplify-and-harden
- Related Files: run_ris_isac_si_mc_smoke.m
- Tags: monte-carlo, reproducibility, paired-comparison
- Pattern-Key: tests.paired-random-seeds
- Recurrence-Count: 1

---

## [LRN-20261008-RIS] best_practice

**Logged**: 2026-10-08T19:00:00+08:00
**Priority**: high
**Status**: pending
**Area**: infra

### Summary
Long MATLAB Monte Carlo jobs need atomic per-sample checkpoints and bounded process concurrency.

### Details
The previous RIS/SIC run used four workers and kept shard state in memory. Native allocator corruption killed workers before shard completion, leaving the aggregator waiting forever. A checkpoint format with one file per completed Monte Carlo index can preserve completed work and allow restart or worker-count changes.

### Suggested Action
Implement resumable per-MC outputs, stale-worker detection, and an aggregator that only declares success when every requested sample has a valid checkpoint.

### Metadata
- Source: error
- Related Files: run_ris_rmse_snr_sic_worker.m, aggregate_ris_sic_rmse_snr_mc60.m
- Tags: matlab, monte-carlo, checkpoint, parallelism

---
