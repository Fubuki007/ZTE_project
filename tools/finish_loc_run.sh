#!/usr/bin/env bash
# Finish the already-running experiment; never launch or restart its workers.
set -Eeuo pipefail
[[ $# == 4 ]] || exit 64
code=$1
original=$2
run=$3
postprocess=$4
for path in "$code" "$original" "$run" "$postprocess"; do
    [[ "$path" == /* && "$path" != *"'"* && -d "$path" ]] || exit 64
done
mkdir -p "$run/audit"
exec 9>"$run/audit/finalize.lock"
flock -n 9 || exit 73
on_exit() {
    status=$?
    if ((status != 0)); then echo FAILED > "$run/audit/state"; fi
}
trap on_exit EXIT
trap 'exit 130' INT TERM
echo "$$" > "$run/audit/supervisor.pid"
echo WAITING > "$run/audit/state"
while true; do
    state=$(cat "$run/state")
    if [[ "$state" == COMPLETE ]]; then break; fi
    [[ "$state" == RUNNING ]] || { echo "Input experiment state: $state"; exit 1; }
    pid=$(cat "$run/supervisor.pid")
    [[ "$pid" =~ ^[0-9]+$ ]] && kill -0 "$pid" || { echo 'Input supervisor is no longer alive'; exit 1; }
    sleep 30
done
echo VERIFYING > "$run/audit/state"
cd "$postprocess"
export OMP_NUM_THREADS=2 OPENBLAS_NUM_THREADS=2 MKL_NUM_THREADS=2
/home/jzm123/MATLAB/R2022b/bin/matlab -batch "finalize_loc_aggregation('$code','$run'); audit_loc_results('$code','$run','$run/audit','$original'); exit(0);" > "$run/audit/audit.log" 2>&1
echo COMPLETE > "$run/audit/state"
echo 'Corrected aggregation and full checkpoint audit completed'
