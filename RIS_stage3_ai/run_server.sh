#!/usr/bin/env bash
set -euo pipefail
if [[ $# -lt 2 || $# -gt 3 ]]; then
  echo 'Usage: bash RIS_stage3_ai/run_server.sh ABSOLUTE_PYTHON ABSOLUTE_RUN_DIR [cuda:0]' >&2
  exit 2
fi
runtime="$1"
run_dir="$2"
device="${3:-cuda:0}"
[[ "$runtime" = /* && "$run_dir" = /* ]] || { echo 'Absolute paths required' >&2; exit 2; }
cd "$(dirname "${BASH_SOURCE[0]}")/.."
mkdir -p "$run_dir"
log="$run_dir/launcher_$(date -u +%Y%m%dT%H%M%S)_$$.log"
nohup "$runtime" -X utf8 -u -m RIS_stage3_ai.server_pipeline --output "$run_dir" --device "$device" >"$log" 2>&1 < /dev/null &
pid=$!
echo "DISPATCHED_PID=$pid LOG=$log"
sleep 2
if ! kill -0 "$pid" 2>/dev/null; then
  echo 'Runner exited during startup; inspect launcher log.' >&2
  tail -n 30 "$log" >&2
  exit 1
fi
"$runtime" -X utf8 -m RIS_stage3_ai.status --output "$run_dir"
