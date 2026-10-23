#!/usr/bin/env bash
set -Eeuo pipefail
cd "$(dirname "$0")"
MATLAB_BIN="${FAS_MATLAB:-/home/jzm123/MATLAB/R2022b/bin/matlab}"
RUN_NAME="${FAS_RUN_NAME:-full_mc300}"
MC="${FAS_MC:-300}"
WORKERS="${FAS_WORKERS:-2}"
SNR="${FAS_SNR:--50,-45,-40,-35,-30,-25,-20,-15,-10,-5,0,5,10}"
[[ "$RUN_NAME" =~ ^[A-Za-z0-9_]+$ && "$MC" =~ ^[1-9][0-9]*$ && "$WORKERS" =~ ^[1-4]$ ]] || exit 64
[[ "$SNR" =~ ^[-0-9.,]+$ ]] || exit 64
mkdir -p "results_$RUN_NAME/logs"
OUT="$PWD/results_$RUN_NAME"
exec 9>"$OUT/run.lock"
flock -n 9 || { echo 'Experiment already running'; exit 73; }
echo "$$" > "$OUT/supervisor.pid"
echo RUNNING > "$OUT/state"
pids=()
on_exit() {
    code=$?
    if ((code != 0)); then
        for pid in "${pids[@]}"; do kill -TERM "$pid" 2>/dev/null || true; done
        echo FAILED > "$OUT/state"
    fi
}
trap on_exit EXIT
trap 'exit 130' INT TERM
export OMP_NUM_THREADS=2 OPENBLAS_NUM_THREADS=2 MKL_NUM_THREADS=2
for ((worker=0;worker<WORKERS;worker++)); do
    "$MATLAB_BIN" -batch "run_fas_experiment('full','$OUT',$worker,$WORKERS,$MC,[$SNR])" \
        > "$OUT/logs/worker_$worker.log" 2>&1 &
    pids+=("$!")
done
printf '%s\n' "${pids[@]}" > "$OUT/workers.pid"
for ((worker=0;worker<WORKERS;worker++)); do wait -n || exit 1; done
"$MATLAB_BIN" -batch "aggregate_fas('$OUT',false)" > "$OUT/logs/aggregate.log" 2>&1
echo COMPLETE > "$OUT/state"
