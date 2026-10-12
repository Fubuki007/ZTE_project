# Errors

Command failures and integration errors.

---

## [ERR-20260916-001] powershell_git_path_filter

**Logged**: 2026-09-16T00:00:00+08:00
**Priority**: low
**Status**: resolved
**Area**: infra

### Summary
A PowerShell regular expression intended to exclude `.git` paths ended with an unescaped backslash and failed during a read-only inventory.

### Error
```
Invalid pattern '\\.git\\' at offset 6. Illegal \\ at end of pattern.
```

### Context
- No files were modified.
- The replacement uses an ordinal path-prefix check rather than a regular expression.

### Suggested Fix
For Windows path exclusion, use `StartsWith()` with an explicit directory path or escape the trailing slash in a regex.

### Metadata
- Reproducible: yes
- Related Files: none

### Resolution
- **Resolved**: 2026-09-16T00:00:00+08:00
- **Notes**: Re-ran the inventory with an ordinal path-prefix check.

---

## [ERR-20260916-004] apply_patch_same_file_replace

**Logged**: 2026-09-16T00:00:00+08:00
**Priority**: low
**Status**: resolved
**Area**: infra

### Summary
The patch tool rejected deletion and creation of the same file in a single patch.

### Error
```
apply_patch verification failed: multiple operations target build_default_params.m
```

### Context
- A scoped replacement of the delivered parameter builder was needed.
- The failed patch made no file changes.

### Suggested Fix
Use separate patch calls for delete and add, then immediately verify the file.

### Metadata
- Reproducible: yes
- Related Files: ZTE_ISAC_SI_Delivery_v1.0_20260916/build_default_params.m

### Resolution
- **Resolved**: 2026-09-16T00:00:00+08:00
- **Notes**: Applied the replacement in two patch operations and verified the new file with MATLAB checkcode and regression.

---

## [ERR-20260916-003] matlab_delivery_name_shadowing

**Logged**: 2026-09-16T00:00:00+08:00
**Priority**: high
**Status**: resolved
**Area**: tests

### Summary
MATLAB regression launched in the source-project root picked up same-named original functions instead of the delivered copies.

### Error
```
assert failed: reduced delivery scenario retained the root builder's default B and FFT length.
```

### Context
- `addpath(delivery_dir)` did not override MATLAB's precedence for functions in the current directory.
- Static checking read the delivery files directly, but functional tests called the root functions.

### Suggested Fix
Change the working directory to the unpacked package, verify `which` for each function, and run regression there.

### Metadata
- Reproducible: yes
- Related Files: ZTE_ISAC_SI_Delivery_v1.0_20260916/README.md

### Resolution
- **Resolved**: 2026-09-16T00:00:00+08:00
- **Notes**: Functional tests now switch to the delivery directory and assert function resolution before exercising its API.

---

## [ERR-20260916-002] matlab_delivery_validation_startup

**Logged**: 2026-09-16T00:00:00+08:00
**Priority**: medium
**Status**: resolved
**Area**: tests

### Summary
MATLAB delivery validation aborted during startup because its toolbox cache under the user profile was inaccessible in the restricted execution environment.

### Error
```
Unable to load/write the MATLAB toolbox cache under AppData; MATLAB exited with status 0x00000003 (abort).
```

### Context
- The batch command was intended to run `checkcode` and a reduced end-to-end SI/SIC smoke test.
- MATLAB exited before package code produced any validation output.

### Suggested Fix
Run MATLAB validation with access to the normal MATLAB preferences and toolbox-cache directories.

### Metadata
- Reproducible: unknown
- Related Files: ZTE_ISAC_SI_Delivery_v1.0_20260916/*.m

### Resolution
- **Resolved**: 2026-09-16T00:00:00+08:00
- **Notes**: Re-ran MATLAB with access to its normal toolbox cache. Static analysis passed with zero messages, the reduced SI/SIC smoke test passed, and the full-size default main flow completed successfully.

---

## [ERR-20260916-001] delivery_document_inventory

**Logged**: 2026-09-16T00:00:00+08:00
**Priority**: medium
**Status**: resolved
**Area**: docs

### Summary
The project README listed `run_si_mse_analysis.m`, but that file is not present in the workspace.

### Error
```
Get-Content: Cannot find path 'run_si_mse_analysis.m' because it does not exist.
```

### Context
- The mismatch was found while resolving the minimal file set for the SI enterprise delivery package.
- Relying on the README alone would have produced an incomplete or misleading manifest.

### Suggested Fix
Generate delivery manifests from files that actually exist and verify every documented entry before packaging.

### Metadata
- Reproducible: yes
- Related Files: README.md, ZTE_ISAC_SI_Delivery_v1.0_20260916/MANIFEST.md

### Resolution
- **Resolved**: 2026-09-16T00:00:00+08:00
- **Notes**: The delivery README and manifest list only files included in the verified minimal package.

---

## [ERR-20260729-001] apply_patch

**Logged**: 2026-07-29T15:58:48+08:00
**Priority**: low
**Status**: resolved
**Area**: config

### Summary
An initial multi-file patch did not apply because one expected MATLAB line differed from the file.

### Error
```
apply_patch verification failed: Failed to find expected lines in task_output_snr_sweep.m
```

### Context
- Attempted to update plotting, equalization, learning log, and delete the obsolete plotting script in one patch.
- No partial file changes were made.

### Suggested Fix
Read the exact target block and apply smaller patches with exact context.

### Metadata
- Reproducible: no
- Related Files: task_output_snr_sweep.m

### Resolution
- **Resolved**: 2026-07-29T15:59:00+08:00
- **Notes**: Re-read the function tail and successfully applied the changes in smaller patches.

---

## [ERR-20260729-002] powershell_remove_item

**Logged**: 2026-07-29T16:00:00+08:00
**Priority**: low
**Status**: resolved
**Area**: config

### Summary
The command policy blocked a PowerShell command that removed two known obsolete plot files.

### Error
```
rejected: blocked by policy
```

### Context
- The requested targets were one obsolete FIG and one obsolete PNG inside the workspace.
- Other parallel verification commands did not run because orchestration stopped on the rejection.

### Suggested Fix
Use MATLAB's `delete` for these MATLAB-generated artifacts, then run verification separately.

### Metadata
- Reproducible: unknown
- Related Files: fig/fig_output_snr_reference_style.fig, png/fig_output_snr_reference_style.png

### Resolution
- **Resolved**: 2026-07-29T16:00:00+08:00
- **Notes**: Switched cleanup to MATLAB and separated it from static analysis.

---

## [ERR-20260729-003] matlab_output_snr_sweep

**Logged**: 2026-07-29T16:01:41+08:00
**Priority**: medium
**Status**: resolved
**Area**: tests

### Summary
The first full MATLAB run failed in transmit-signal normalization because `max(vector, eps)` returned a vector.

### Error
```
Array sizes are incompatible.
task_output_snr_sweep>local_equalize_rx
```

### Context
- The failure occurred during the first Monte Carlo sample of the receive-antenna sweep.
- Element-wise division expected a scalar normalization factor.

### Suggested Fix
Compute the maximum magnitude first, then compare that scalar with `eps`.

### Metadata
- Reproducible: yes
- Related Files: task_output_snr_sweep.m

### Resolution
- **Resolved**: 2026-07-29T16:02:00+08:00
- **Notes**: Changed both normalization branches to use `max(max(abs(values(:))), eps)`.

---


## [ERR-20260626-001] powershell_rg_search

**Logged**: 2026-06-26T00:00:00+08:00
**Priority**: low
**Status**: pending
**Area**: infra

### Summary
Initial repository search failed because rg is unavailable and one parallel PowerShell search hit a Windows sandbox CreateProcessWithLogonW 1056 error.

### Error
```nrg not recognized; windows sandbox: CreateProcessWithLogonW failed: 1056
```n
### Context
- Attempted file and text search before falling back to native PowerShell commands.

### Suggested Fix
Use Get-ChildItem and Select-String in this environment when rg is unavailable; avoid parallel shell search if the sandbox rejects it.

### Metadata
- Reproducible: unknown
- Related Files: none

---

## [ERR-20260825-001] python_scipy_fig_corruption

**Logged**: 2026-08-25T20:40:00+08:00
**Priority**: high
**Status**: resolved
**Area**: plotting

### Summary
A MATLAB `.fig` generated via Python/scipy could not be opened by MATLAB.

### Error
```
Unrecognized field name "Format3Data"
```

### Context
- The Python script wrote `hgM_070000.GraphicsObjects` as a generic struct instead of preserving `MatlabOpaque`.
- MATLAB's fig reader then failed while trying to read `matlab.graphics.internal.figfile.GraphicsObjects`.

### Suggested Fix
- Do not use Python/scipy to write MATLAB `.fig` files.
- Use a MATLAB script with `openfig` / `savefig` / `exportgraphics`.
- Python should be limited to PNG/EPS output.

### Metadata
- Reproducible: yes
- Related Files: fig/angle_rmse_vs_snr_si_suppression_sic_7pt.fig, draw_angle_rmse_snr_si_sic_7pt.py
- Tags: matlab, fig, scipy, Format3Data

### Resolution
- **Resolved**: 2026-08-25T20:40:00+08:00
- **Notes**: Re-created the .fig with MATLAB and updated the Python script to stop generating .fig.

---

## [ERR-20260922-001] zte_aggregate_bundle_prefix

**Logged**: 2026-09-22T11:00:00+08:00
**Priority**: medium
**Status**: resolved
**Area**: infra

### Summary
Fetching a completed aggregate MATLAB job initially returned only its log because the job name ended in `_aggregate` while its output files used the shared result stem.

### Error
```
The result archive omitted the aggregate MAT, CSV, and figures.
```

### Context
- `task_si_strength_3methods_beta1_to_1e6_mc80_aggregate` writes files beginning with `task_si_strength_3methods_beta1_to_1e6_mc80`.
- `tools/zte-job.sh bundle` previously searched only for files beginning with the full job name.

### Suggested Fix
Derive a result prefix by removing a terminal `_aggregate` suffix and include matching FIG/PNG/EPS files from `fig/`.

### Metadata
- Reproducible: yes
- Related Files: tools/zte-job.sh

### Resolution
- **Resolved**: 2026-09-22T11:00:00+08:00
- **Notes**: Updated the bundle rule, reinstalled it on the server, and verified the regenerated archive contains MAT, CSV, FIG, PNG, EPS, and aggregate log files.

---


## [ERR-20261002-001] matlab_ris_model_smoke

**Logged**: 2026-10-02T00:00:00+08:00
**Priority**: medium
**Status**: resolved
**Area**: tests

### Summary
MATLAB rejected direct indexing of a parenthesized expression in the new RIS model.

### Error
```text
Invalid use of operator near build_ris_target_model.m line 64
```

### Context
The first quick run of `run_ris_isac_no_interference('quick')` used `(ax * ay.').(:)`.

### Suggested Fix
Assign the matrix to a temporary variable before applying `(:)`; this is compatible with MATLAB R2024a.

### Metadata
- Reproducible: yes
- Related Files: build_ris_target_model.m

---

## [ERR-20261002-002] ris_phase_coordinate_ascent_sign

**Logged**: 2026-10-02T00:00:00+08:00
**Priority**: high
**Status**: resolved
**Area**: algorithm

### Summary
The first RIS target-enhancement run used the wrong phase sign in coordinate ascent.

### Error
The continuous phase objective decreased while quantized configurations appeared stronger, which contradicted the maximization objective.

### Context
For `r = r0 + b*phi`, the cross term is `2*real(conj(r0)*b*phi)`, so the maximizing unit phase is `exp(-1j*angle(c))`, not `exp(+1j*angle(c))`.

### Suggested Fix
Use the negative phase sign for both continuous updates and discrete codebook scores.

### Metadata
- Reproducible: yes
- Related Files: optimize_ris_target_phase.m

---

## [ERR-20261002-003] ris_discrete_phase_score_sign

**Logged**: 2026-10-02T00:00:00+08:00
**Priority**: high
**Status**: resolved
**Area**: algorithm

### Summary
The discrete RIS coordinate update scored the conjugate codebook while assigning the original codeword, causing non-monotonic objective histories.

### Error
Discrete histories oscillated and decreased between sweeps even though each coordinate was intended to maximize the local objective.

### Context
For `r0+b*exp(j*grid)`, the score is `real(exp(j*grid)*c)` with `c=sum(conj(r0).*b)`; the selected codeword is `exp(j*grid(k))`.

### Suggested Fix
Use the same positive-grid convention in the score and codeword assignment, while retaining `exp(-j*angle(c))` for the continuous branch.

### Metadata
- Reproducible: yes
- Related Files: optimize_ris_target_phase.m

---

## [ERR-20261002-004] si_regression_smoke_parameter

**Logged**: 2026-10-02T00:00:00+08:00
**Priority**: low
**Status**: resolved
**Area**: tests

### Summary
A temporary SI smoke-test command referenced a non-existent `params.Tcp` field.

### Error
```text
Unrecognized field name "Tcp"
```

### Context
The test reduced `N` and `K` manually; the project stores only the derived `Ts`, so the CP duration must be supplied explicitly for the temporary override.

### Suggested Fix
Use `p.Ts=1/(p.B/p.N)+0.6e-6` in reduced smoke tests.

### Metadata
- Reproducible: yes
- Related Files: build_default_params.m

---

## [ERR-20261008-RIS] MATLAB native heap corruption under four workers

**Logged**: 2026-10-08T19:00:00+08:00
**Priority**: high
**Status**: in_progress
**Area**: infra

### Summary
The four-worker RIS plus matrix-SI plus pilot-LS-SIC run aborted with native allocator errors before completing the first Monte Carlo shard.

### Error
`free(): invalid next size (normal)`; `malloc(): invalid size (unsorted)`; `double free or corruption (!prev)`.

### Context
The worker processes each completed several SNR points for one MC index, then exited before writing a complete shard. The aggregate process waited indefinitely for all four shards. No MATLAB process remained afterward.

### Suggested Fix
Use bounded per-MC checkpoint files, atomic writes, explicit worker isolation, conservative concurrency, and a resume-aware aggregator. Add a single-worker smoke test before increasing concurrency.

### Metadata
- Reproducible: yes
- Related Files: run_ris_rmse_snr_sic_worker.m, aggregate_ris_sic_rmse_snr_mc60.m

### Follow-up evidence (2026-10-08)
The failure is not proven to be an OOM or specifically caused by four workers. A single worker with about 38 GiB available reproduced allocator corruption; GDB showed `libmwlmgrimpl.so` freeing memory, then MATLAB's signal handler blocking in `malloc`. The supervisor now terminates no-progress process groups, runs short batches, and resumes from per-MC/per-case atomic checkpoints. The initial 12/12 smoke cases were recovered and aggregated successfully.

### Direct write evidence (2026-10-10)
Four tiny idle controls (base MATLAB, one Hann call, one QAM call, and Hann without JVM) reproduced native allocator faults at about two minutes. Valgrind then recorded invalid writes in `vNAZCAVud41d` inside the installed `libmwlmgrimpl.so`, at offsets 0, 1 and 2 bytes beyond a 326-byte calloc allocation made by that function. This identifies an actual corrupting write rather than only a detection site. See `server-results/native_heap_diagnosis_20261010/memcheck-native.3824481.log`. The installed library needs comparison with a clean official installation/update; short per-case processes are mitigation, not a native-library repair. Do not infer a universal R2022b defect or a modified binary without further evidence.

---
