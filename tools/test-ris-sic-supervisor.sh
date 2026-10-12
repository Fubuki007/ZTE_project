#!/usr/bin/env bash
# Exercise a native-style hang, forced termination, resumption and batch yields.
set -Eeuo pipefail
launcher=$(realpath "$(dirname "$0")/run-ris-sic-resumable.sh")
test_dir=$(mktemp -d)
cleanup() {
    rc=$?
    if (( rc )); then cat "$test_dir"/logs/* 2>/dev/null || true; fi
    rm -rf -- "$test_dir"
}
trap cleanup EXIT
cat > "$test_dir/fake-matlab" <<'MOCK'
#!/usr/bin/env bash
if [[ "$*" == *aggregate* ]]; then echo AGGREGATED_RESULT=test; exit 0; fi
attempt=0
[[ ! -f attempt ]] || read -r attempt < attempt
attempt=$((attempt+1))
echo "$attempt" > attempt
echo "$$" >> mock-pids
case "$attempt" in
    1)
        echo 'CASE_SAVED MC=1 SNR=0 scheme=1'
        trap '' TERM
        while true; do sleep 1; done
        ;;
    2)
        echo 'CASE_SAVED MC=1 SNR=0 scheme=2'
        echo 'malloc(): invalid size (unsorted)' >&2
        trap '' TERM
        while true; do sleep 1; done
        ;;
    3)
        echo 'CASE_SAVED MC=1 SNR=0 scheme=3'
        echo BATCH_YIELD
        trap '' TERM
        while true; do sleep 1; done
        ;;
    4) echo 'CASE_SAVED MC=1 SNR=0 scheme=4'; echo BATCH_YIELD ;;
    5) echo FINAL_RESULT=test ;;
    *) echo Unexpected_restart; exit 1 ;;
esac
MOCK
chmod +x "$test_dir/fake-matlab"
env ZTE_PROJECT_DIR="$test_dir" ZTE_MATLAB_BIN="$test_dir/fake-matlab" \
    RIS_MC_TOTAL=1 RIS_N_SHARDS=1 RIS_RUN_TAG=test RIS_MAX_RESTARTS=0 \
    RIS_STALL_TIMEOUT_SECONDS=5 RIS_EXIT_TIMEOUT_SECONDS=2 \
    RIS_WATCHDOG_POLL_SECONDS=1 bash "$launcher"
prefix=ris_sic_rmse_snr_mc1_test_double
[[ $(cat "$test_dir/.jobs/$prefix.state") == COMPLETE ]]
[[ $(cat "$test_dir/attempt") == 5 ]]
grep -q STALL_WATCHDOG "$test_dir/logs/${prefix}_shard1_supervised.out"
grep -q NATIVE_FAULT_WATCHDOG "$test_dir/logs/${prefix}_shard1_supervised.out"
grep -q EXIT_WATCHDOG "$test_dir/logs/${prefix}_shard1_supervised.out"
grep -q 'MATLAB_EXIT_CODE=137' "$test_dir/logs/${prefix}_shard1_supervised.out"
while read -r pid; do ! kill -0 "$pid" 2>/dev/null; done < "$test_dir/mock-pids"
flock -n "$test_dir/.jobs/$prefix.lock" -c true
echo SUPERVISOR_RECOVERY_TEST_PASSED
