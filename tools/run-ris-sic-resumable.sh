#!/usr/bin/env bash
# Run under nohup. Each failed MATLAB process restarts from per-case files.
set -Eeuo pipefail
PROJECT_DIR="${ZTE_PROJECT_DIR:-/home/jzm123/AAA_ZTEproject}"
MATLAB_BIN="${ZTE_MATLAB_BIN:-/home/jzm123/MATLAB/R2022b/bin/matlab}"
export RIS_MC_TOTAL="${RIS_MC_TOTAL:-60}"
export RIS_N_SHARDS="${RIS_N_SHARDS:-4}"
export RIS_USE_SINGLE="${RIS_USE_SINGLE:-0}"
export RIS_RUN_TAG="${RIS_RUN_TAG:-resume_v3}"
MAX_RESTARTS="${RIS_MAX_RESTARTS:-3}"
STALL_TIMEOUT="${RIS_STALL_TIMEOUT_SECONDS:-900}"
CASES_PER_PROCESS="${RIS_CASES_PER_PROCESS:-1}"
EXIT_TIMEOUT="${RIS_EXIT_TIMEOUT_SECONDS:-60}"
WATCHDOG_POLL="${RIS_WATCHDOG_POLL_SECONDS:-10}"
export RIS_CASES_PER_PROCESS="$CASES_PER_PROCESS"
for value in "$RIS_MC_TOTAL" "$RIS_N_SHARDS"; do
    [[ "$value" =~ ^[1-9][0-9]*$ ]] || { echo 'Invalid MC/shard count'; exit 64; }
done
[[ "$MAX_RESTARTS" =~ ^[0-9]+$ ]] || exit 64
[[ "$STALL_TIMEOUT" =~ ^[1-9][0-9]*$ ]] || exit 64
[[ "$CASES_PER_PROCESS" =~ ^[1-9][0-9]*$ ]] || exit 64
[[ "$EXIT_TIMEOUT" =~ ^[1-9][0-9]*$ ]] || exit 64
[[ "$WATCHDOG_POLL" =~ ^[1-9][0-9]*$ ]] || exit 64
[[ "$RIS_N_SHARDS" -le "$RIS_MC_TOTAL" ]] || exit 64
[[ "$RIS_RUN_TAG" =~ ^[A-Za-z0-9_]+$ ]] || exit 64
[[ "$RIS_USE_SINGLE" == 0 || "$RIS_USE_SINGLE" == 1 ]] || exit 64
precision=double
[[ "$RIS_USE_SINGLE" == 1 ]] && precision=single
prefix="ris_sic_rmse_snr_mc${RIS_MC_TOTAL}_${RIS_RUN_TAG}_${precision}"
prefix="${RIS_RESULT_PREFIX:-$prefix}"
worker_function="${RIS_WORKER_FUNCTION:-run_ris_rmse_snr_sic_worker}"
aggregate_function="${RIS_AGGREGATE_FUNCTION:-aggregate_ris_sic_rmse_snr_mc60}"
[[ "$prefix" =~ ^[A-Za-z0-9_]+$ ]] || exit 64
[[ "$worker_function" =~ ^[A-Za-z][A-Za-z0-9_]*$ ]] || exit 64
[[ "$aggregate_function" =~ ^[A-Za-z][A-Za-z0-9_]*$ ]] || exit 64
worker_flags=(-singleCompThread)
if [[ "${RIS_WORKER_NO_JVM:-0}" == 1 ]]; then worker_flags+=(-nojvm); fi
cd "$PROJECT_DIR"
mkdir -p .jobs logs
# Prevent duplicate writers, including after SSH disconnection.
exec 9> ".jobs/${prefix}.lock"
flock -n 9 || { echo 'This experiment already has an active supervisor.'; exit 73; }
echo "$$" > ".jobs/${prefix}.supervisor.pid"
state_file=".jobs/${prefix}.state"
write_state() { printf '%s\n' "$1" > "${state_file}.tmp"; mv -f "${state_file}.tmp" "$state_file"; }
pids=()
terminate_group() {
    local target_pid="$1"
    kill -TERM -- "-$target_pid" 2>/dev/null || true
    for ((grace=0; grace<10; grace++)); do
        # The launcher can exit before a native MATLAB child.  Check the
        # entire group so orphaned children still receive the final KILL.
        kill -0 -- "-$target_pid" 2>/dev/null || return 0
        sleep 1
    done
    kill -KILL -- "-$target_pid" 2>/dev/null || true
}
shutdown() {
    trap - TERM INT
    for pid in "${pids[@]}"; do
        if kill -0 "$pid" 2>/dev/null; then
            kill -TERM "$pid" 2>/dev/null || true
            kill -TERM -- "-$pid" 2>/dev/null || true
        fi
    done
    wait || true
    write_state STOPPED
    exit 143
}
trap shutdown TERM INT
write_state RUNNING
# Bound native threads. Double precision preserves the original experiment.
export OMP_NUM_THREADS=1 MKL_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1
export MALLOC_ARENA_MAX=2
run_worker() {
    shard="$1"
    child=""
    watchdog=""
    stop_worker() {
        trap - TERM INT
        if [[ -n "$watchdog" ]]; then kill -TERM "$watchdog" 2>/dev/null || true; fi
        if [[ -n "$child" ]]; then terminate_group "$child"; fi
        wait || true
        exit 143
    }
    trap stop_worker TERM INT
    log="logs/${prefix}_shard${shard}_supervised.out"
    for ((attempt=0; attempt<=MAX_RESTARTS; attempt++)); do
        saved_before=$(grep -c '^CASE_SAVED ' "$log" 2>/dev/null || true)
        saved_before=${saved_before:-0}
        yields_before=$(grep -c '^BATCH_YIELD' "$log" 2>/dev/null || true)
        yields_before=${yields_before:-0}
        finals_before=$(grep -c '^FINAL_RESULT=' "$log" 2>/dev/null || true)
        finals_before=${finals_before:-0}
        printf '\n[%s] shard=%s attempt=%s\n' "$(date -Is)" "$shard" "$attempt" >> "$log"
        attempt_line=$(wc -l < "$log")
        setsid "$MATLAB_BIN" "${worker_flags[@]}" -batch "$worker_function($shard);" >> "$log" 2>&1 < /dev/null &
        child=$!
        echo "$child" > ".jobs/${prefix}_shard${shard}.pid"
        # MATLAB can remain alive after a native abort/deadlock.  Monitor
        # output/checkpoint mtime and terminate the whole process group when
        # no computational progress is observed for the configured interval.
        (
            # Polling sleeps must not keep the experiment lock held after
            # the supervisor and MATLAB have already exited.
            exec 9>&-
            exit_deadline=0
            while kill -0 "$child" 2>/dev/null; do
                sleep "$WATCHDOG_POLL"
                [[ -d "/proc/$child" ]] || exit 0
                now=$(date +%s)
                last=$(stat -c %Y "$log" 2>/dev/null || echo "$now")
                attempt_output=$(sed -n "$((attempt_line+1)),\$p" "$log")
                if grep -Eq '(^|[[:space:]])(malloc\(\):|free\(\):|double free or corruption|corrupted (size|double-linked)|munmap_chunk\(\):)' <<< "$attempt_output"; then
                    printf '[%s] NATIVE_FAULT_WATCHDOG allocator error; terminating MATLAB pid=%s\n' "$(date -Is)" "$child" >> "$log"
                    terminate_group "$child"
                    exit 0
                fi
                if (( exit_deadline == 0 )) && grep -Eq '^(BATCH_YIELD|FINAL_RESULT=)' <<< "$attempt_output"; then
                    exit_deadline=$((now+EXIT_TIMEOUT))
                fi
                if (( exit_deadline > 0 && now >= exit_deadline )); then
                    printf '[%s] EXIT_WATCHDOG committed batch did not exit in %ss; terminating MATLAB pid=%s\n' "$(date -Is)" "$EXIT_TIMEOUT" "$child" >> "$log"
                    terminate_group "$child"
                    exit 0
                fi
                if (( now - last >= STALL_TIMEOUT )); then
                    printf '[%s] STALL_WATCHDOG no log progress for %ss; terminating MATLAB pid=%s\n' "$(date -Is)" "$STALL_TIMEOUT" "$child" >> "$log"
                    terminate_group "$child"
                    exit 0
                fi
            done
        ) &
        watchdog=$!
        rc=0
        wait "$child" || rc=$?
        kill -TERM "$watchdog" 2>/dev/null || true
        wait "$watchdog" 2>/dev/null || true
        watchdog=""
        child=""
        printf '[%s] MATLAB_EXIT_CODE=%s\n' "$(date -Is)" "$rc" >> "$log"
        if (( rc == 0 )); then
            yields_after=$(grep -c '^BATCH_YIELD' "$log" || true)
            finals_after=$(grep -c '^FINAL_RESULT=' "$log" || true)
            if (( finals_after > finals_before )); then exit 0; fi
            if (( yields_after > yields_before )); then
                # A deliberate short-batch exit is resumable progress, not a
                # failed attempt and must not consume the restart budget.
                attempt=-1
                sleep 1
                continue
            fi
            rc=65
            printf 'Missing FINAL_RESULT on successful MATLAB exit.\n' >> "$log"
        fi
        # Invalid or incompatible data needs investigation, not endless retries.
        if tail -n 30 "$log" | grep -Eq 'RIS:InvalidCheckpoint|Configuration mismatch'; then exit "$rc"; fi
        saved_after=$(grep -c '^CASE_SAVED ' "$log" 2>/dev/null || true)
        if (( saved_after > saved_before )); then attempt=-1; fi
        if (( attempt < MAX_RESTARTS )); then sleep 5; fi
    done
    exit "$rc"
}
for ((shard=1; shard<=RIS_N_SHARDS; shard++)); do
    run_worker "$shard" &
    pids+=("$!")
done
failed=0
for pid in "${pids[@]}"; do wait "$pid" || failed=1; done
pids=()
if (( failed )); then write_state FAILED; echo 'Worker failed after bounded retries; checkpoints retained.'; exit 1; fi
write_state AGGREGATING
setsid timeout --signal=TERM --kill-after=10 "${RIS_AGGREGATE_PROCESS_TIMEOUT_SECONDS:-600}" \
    "$MATLAB_BIN" -singleCompThread -batch "$aggregate_function;" > "logs/${prefix}_aggregate.out" 2>&1 < /dev/null &
pids=("$!")
if wait "${pids[0]}"; then
    write_state COMPLETE
    echo "COMPLETE: $PROJECT_DIR/${prefix}_results.mat"
else
    write_state FAILED
    echo 'Aggregation failed; see aggregate log. Checkpoints retained.'
    exit 1
fi
