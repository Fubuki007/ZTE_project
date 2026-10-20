#!/usr/bin/env bash
set -Eeuo pipefail
cd "$(dirname "$0")"
PYTHON_BIN="${STAGE3_PYTHON:-$PWD/.venv311/bin/python}"
RUN_NAME="${STAGE3_RUN_NAME:-results_full_mc100}"
MC="${STAGE3_MC:-100}"
WORKERS="${STAGE3_WORKERS:-2}"
THREADS="${STAGE3_THREADS:-4}"
SNR="${STAGE3_SNR:--30,-25,-20,-15,-10,-5,0,5,10,15,20}"
[[ "$RUN_NAME" =~ ^[A-Za-z0-9_]+$ ]] || exit 64
[[ "$MC" =~ ^[1-9][0-9]*$ && "$WORKERS" =~ ^[1-9][0-9]*$ && "$THREADS" =~ ^[1-9][0-9]*$ ]] || exit 64
mkdir -p "$RUN_NAME/logs"
exec 9>"$RUN_NAME/run.lock"
flock -n 9 || { echo 'This experiment is already running'; exit 73; }
echo "$$" > "$RUN_NAME/supervisor.pid"
echo RUNNING > "$RUN_NAME/state"
pids=()
on_exit() {
    code=$?
    if ((code != 0)); then
        for pid in "${pids[@]}"; do kill -TERM "$pid" 2>/dev/null || true; done
        echo FAILED > "$RUN_NAME/state"
    fi
}
trap on_exit EXIT
trap 'exit 130' INT TERM
export OPENBLAS_NUM_THREADS="$THREADS" OMP_NUM_THREADS="$THREADS" MKL_NUM_THREADS="$THREADS"
for ((worker=0;worker<WORKERS;worker++)); do
    "$PYTHON_BIN" -u run_stage3.py --mc "$MC" --snr="$SNR" --output "$RUN_NAME" \
        --workers "$WORKERS" --worker "$worker" --threads "$THREADS" \
        >> "$RUN_NAME/logs/worker_$worker.log" 2>&1 &
    pids+=("$!")
done
printf '%s\n' "${pids[@]}" > "$RUN_NAME/workers.pid"
failed=0
for pid in "${pids[@]}"; do wait "$pid" || failed=1; done
((failed==0)) || exit 1
"$PYTHON_BIN" run_stage3.py --aggregate-only --output "$RUN_NAME" > "$RUN_NAME/logs/aggregate.log" 2>&1
"$PYTHON_BIN" collect_rmse.py --source "$RUN_NAME" > "$RUN_NAME/logs/range_velocity_metrics.log" 2>&1
echo COMPLETE > "$RUN_NAME/state"
