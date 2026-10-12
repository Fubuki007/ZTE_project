#!/usr/bin/env bash
# Minimal isolation: no project functions, RIS, large arrays or random draws.
set -Eeuo pipefail
diag_dir="${ZTE_DIAG_DIR:-/home/jzm123/AAA_ZTEproject/.jobs/diagnostics}"
matlab_bin="${ZTE_MATLAB_BIN:-/home/jzm123/MATLAB/R2022b/bin/matlab}"
mkdir -p "$diag_dir/runtime-idle"
cd "$diag_dir/runtime-idle"
export OMP_NUM_THREADS=1 MKL_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1
export MALLOC_ARENA_MAX=2
echo "MINIMAL_IDLE_STARTED $(date -Is)"
timeout --signal=TERM --kill-after=10 420 "$matlab_bin" -singleCompThread \
    -batch "disp('MINIMAL_IDLE_BEGIN'); for k=1:24, pause(15); fprintf('IDLE_PROGRESS=%d\\n',k); end; disp('MINIMAL_IDLE_COMPLETE');"
echo "MINIMAL_IDLE_EXITED $(date -Is)"
