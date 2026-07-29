# Learnings

Corrections, insights, and knowledge gaps captured during development.

**Categories**: correction | insight | knowledge_gap | best_practice

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

