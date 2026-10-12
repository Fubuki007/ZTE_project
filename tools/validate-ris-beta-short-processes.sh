#!/usr/bin/env bash
# Resume only the dedicated MC=1 equivalence test, in bounded processes.
set -eu
cd /home/jzm123/AAA_ZTEproject/.jobs/experiments/ris_beta_sweep_mc1_validation_20261010_double
export RIS_MC_TOTAL=1 RIS_N_SHARDS=1 RIS_SNR_LIST=-25 RIS_BETA_LIST=0.1
export RIS_RESULT_PREFIX=ris_beta_sweep_mc1_validation_20261010_double
export RIS_CASES_PER_PROCESS=1 OMP_NUM_THREADS=1 MKL_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 MALLOC_ARENA_MAX=2
for attempt in 1 2 3 4; do
    log="logs/validation-short-${attempt}.out"
    rc=0
    timeout --signal=TERM --kill-after=10 180 /home/jzm123/MATLAB/R2022b/bin/matlab \
        -singleCompThread -batch validate_ris_beta_equivalence > "$log" 2>&1 < /dev/null || rc=$?
    printf 'VALIDATION_ATTEMPT=%d EXIT=%d %s\n' "$attempt" "$rc" "$(date -Is)"
    if grep -q '^BETA_FULL_SIZE_EQUIVALENCE_PASSED' "$log" && (( rc==0 )); then exit 0; fi
done
exit 1
