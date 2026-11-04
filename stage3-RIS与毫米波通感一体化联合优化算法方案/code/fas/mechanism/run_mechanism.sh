#!/usr/bin/env bash
set -Eeuo pipefail
cd "$(dirname "$0")"
: "${MECH_ORIGINAL:?Original completed run is required}"
: "${MECH_PRIOR:?Completed localization run is required}"
WORKERS="${MECH_WORKERS:-8}"
[[ "$WORKERS" =~ ^[1-8]$ ]] || exit 64
OUT="$PWD/results_full"
mkdir -p "$OUT/logs"
exec 9>"$OUT/run.lock"
flock -n 9 || exit 73
echo "$$" > "$OUT/supervisor.pid"
echo RUNNING > "$OUT/state"
pids=()
on_exit() {
    status=$?
    if ((status != 0)); then
        for pid in "${pids[@]}"; do kill -TERM "$pid" 2>/dev/null || true; done
        echo FAILED > "$OUT/state"
    fi
}
trap on_exit EXIT
trap 'exit 130' INT TERM
export OMP_NUM_THREADS=2 OPENBLAS_NUM_THREADS=2 MKL_NUM_THREADS=2
MATLAB_BIN=/home/jzm123/MATLAB/R2022b/bin/matlab
for ((worker=0;worker<WORKERS;worker++)); do
    "$MATLAB_BIN" -batch "run_mechanism('full','$MECH_ORIGINAL','$MECH_PRIOR','$OUT',$worker,$WORKERS); exit(0);" > "$OUT/logs/worker_$worker.log" 2>&1 &
    pids+=("$!")
done
printf '%s\n' "${pids[@]}" > "$OUT/workers.pid"
for ((worker=0;worker<WORKERS;worker++)); do wait -n || exit 1; done
"$MATLAB_BIN" -batch "aggregate_mechanism('$OUT'); exit(0);" > "$OUT/logs/aggregate.log" 2>&1
echo COMPLETE > "$OUT/state"
