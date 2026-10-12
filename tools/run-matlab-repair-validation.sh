#!/usr/bin/env bash
set -Eeuo pipefail
repair=/home/jzm123/AAA_ZTEproject/.jobs/matlab_repair/20261010_1037
grep -q '^IDLE_VALIDATED' "$repair/repair.state"
prefix=ris_beta_sweep_mc4_repair_validation_20261010_double
experiment="/home/jzm123/AAA_ZTEproject/.jobs/experiments/$prefix"
cd "$experiment"
export RIS_MC_TOTAL=4 RIS_N_SHARDS=4 RIS_SNR_LIST=-25,-20 RIS_BETA_LIST=0.1
export RIS_RESULT_PREFIX="$prefix" RIS_CASES_PER_PROCESS=100
export RIS_WORKER_FUNCTION=validate_ris_repaired_runtime RIS_AGGREGATE_FUNCTION=aggregate_ris_beta_sweep
export ZTE_PROJECT_DIR="$experiment" RIS_MAX_RESTARTS=0
bash tools/run-ris-sic-resumable.sh
# Any native failure invalidates the stability claim, even if a retry saved data.
if grep -Eq 'NATIVE_FAULT|WATCHDOG|MATLAB_EXIT_CODE=[1-9]' logs/*shard*_supervised.out; then exit 70; fi
for shard in 1 2 3 4; do
    grep -q "REPAIRED_RUNTIME_FULL_SIZE_PASSED MC=$shard" "logs/${prefix}_shard${shard}_supervised.out"
    [[ $(grep -c 'MATLAB_EXIT_CODE=0' "logs/${prefix}_shard${shard}_supervised.out") == 1 ]]
done
printf 'FULL_SIZE_FOUR_WORKERS_VALIDATED %s\n' "$(date -Is)" > "$repair/repair.state"
cat "$repair/repair.state"
