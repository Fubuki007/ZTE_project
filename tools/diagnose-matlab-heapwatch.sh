#!/usr/bin/env bash
# Focused native debugging of a disposable idle process; no model changes.
set -eu
diag=/home/jzm123/AAA_ZTEproject/.jobs/diagnostics
cd "$diag/toolbox-isolation-20261010"
export OMP_NUM_THREADS=1 MKL_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 MALLOC_ARENA_MAX=2 RIS_DIAG_MODE=base
timeout -k 10 240 /home/jzm123/MATLAB/R2022b/bin/matlab \
    -singleCompThread -nojvm -batch diagnose_toolbox_runtime > heapwatch-matlab.out 2>&1 < /dev/null &
timeout_pid=$!
for k in {1..40}; do
    if grep -q TRIGGER_RETURNED heapwatch-matlab.out; then break; fi
    sleep 1
done
native_pid=$(pgrep -P "$timeout_pid" MATLAB | head -n 1)
test -n "$native_pid"
rc=0
env LD_LIBRARY_PATH="$diag/gdb-runtime/usr/lib/x86_64-linux-gnu" \
    timeout -k 5 170 "$diag/gdb-runtime/usr/bin/gdb" -batch \
    -x diagnose-matlab-heapwatch.gdb -p "$native_pid" > heapwatch-native.out 2>&1 || rc=$?
printf 'HEAPWATCH_GDB_EXIT=%d %s\n' "$rc" "$(date -Is)"
wait "$timeout_pid" || true
