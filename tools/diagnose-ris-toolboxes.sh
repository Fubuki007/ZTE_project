#!/usr/bin/env bash
# Compare one toolbox call followed by idling with a base-MATLAB control.
set -u
cd "$(dirname "$0")"
export OMP_NUM_THREADS=1 MKL_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 MALLOC_ARENA_MAX=2
matlab_bin=/home/jzm123/MATLAB/R2022b/bin/matlab
for label in base signal comm signal_nojvm; do
    flags=(-singleCompThread)
    mode="$label"
    if [[ "$label" == signal_nojvm ]]; then mode=signal; flags+=(-nojvm); fi
    (
        printf 'PROCESS_START %s\n' "$(date -Is)"
        env RIS_DIAG_MODE="$mode" timeout --signal=TERM --kill-after=10 260 \
            "$matlab_bin" "${flags[@]}" -batch diagnose_toolbox_runtime
        rc=$?
        printf 'PROCESS_EXIT=%s %s\n' "$rc" "$(date -Is)"
    ) > "$label.out" 2>&1 < /dev/null &
done
wait
echo ISOLATION_RUN_FINISHED
