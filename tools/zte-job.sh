#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT_DIR="${ZTE_PROJECT_DIR:-/home/jzm123/AAA_ZTEproject}"
MATLAB_BIN="${ZTE_MATLAB_BIN:-/home/jzm123/MATLAB/R2022b/bin/matlab}"
JOBS_DIR="$PROJECT_DIR/.jobs"
LOGS_DIR="$PROJECT_DIR/logs"

mkdir -p "$JOBS_DIR" "$LOGS_DIR"

usage() {
    cat <<'EOF'
Usage: zte-job.sh start|status|tail|bundle|cancel|adopt [arguments]
EOF
}

validate_job() {
    local job="${1:-}"
    if [[ ! "$job" =~ ^[A-Za-z][A-Za-z0-9_]*$ ]]; then
        printf 'Invalid MATLAB job name: %s\n' "$job" >&2
        exit 64
    fi
}

pid_file() {
    printf '%s/%s.pid\n' "$JOBS_DIR" "$1"
}

log_file_record() {
    printf '%s/%s.logpath\n' "$JOBS_DIR" "$1"
}

read_log_path() {
    local job="$1"
    local record
    record="$(log_file_record "$job")"
    if [[ -s "$record" ]]; then
        head -n 1 "$record"
    else
        printf '%s/%s.out\n' "$LOGS_DIR" "$job"
    fi
}

is_running() {
    local pid="$1"
    local state
    [[ "$pid" =~ ^[0-9]+$ ]] || return 1
    kill -0 "$pid" 2>/dev/null || return 1
    state="$(ps -p "$pid" -o stat= 2>/dev/null | tr -d '[:space:]')"
    [[ -n "$state" && "$state" != Z* ]]
}

find_untracked_pid() {
    local job="$1"
    pgrep -u "$(id -u)" -f "[/]MATLAB.*-batch[[:space:]]+${job}([[:space:]]|$)" | head -n 1 || true
}

status_one() {
    local job="$1"
    local pid_path pid log_path state
    validate_job "$job"
    pid_path="$(pid_file "$job")"
    log_path="$(read_log_path "$job")"
    pid=""
    [[ -s "$pid_path" ]] && pid="$(head -n 1 "$pid_path")"
    [[ -z "$pid" ]] && pid="$(find_untracked_pid "$job")"

    if [[ -n "$pid" ]] && is_running "$pid"; then
        state="RUNNING"
    elif [[ -s "$pid_path" ]]; then
        state="FINISHED"
    else
        state="NOT_FOUND"
    fi

    printf 'JOB=%s\nSTATE=%s\n' "$job" "$state"
    [[ -n "$pid" ]] && printf 'PID=%s\n' "$pid"
    if [[ "$state" == "RUNNING" ]]; then
        ps -p "$pid" -o etime=,pcpu=,pmem=,stat= | awk '{printf "ELAPSED=%s CPU=%s%% MEM=%s%% PROC_STATE=%s\n", $1, $2, $3, $4}'
    fi
    printf 'LOG=%s\n' "$log_path"
    if [[ -f "$log_path" ]]; then
        local progress
        progress="$(grep -E 'MC=[0-9]+/[0-9]+' "$log_path" | tail -n 1 || true)"
        [[ -n "$progress" ]] && printf 'PROGRESS=%s\n' "$progress"
    fi
    return 0
}

start_job() {
    local job="$1"
    local script pid_path log_path old_pid pid
    validate_job "$job"
    script="$PROJECT_DIR/$job.m"
    pid_path="$(pid_file "$job")"
    log_path="$LOGS_DIR/$job.out"

    [[ -x "$MATLAB_BIN" ]] || { printf 'MATLAB not executable: %s\n' "$MATLAB_BIN" >&2; exit 69; }
    [[ -f "$script" ]] || { printf 'MATLAB script not found: %s\n' "$script" >&2; exit 66; }

    if [[ -s "$pid_path" ]]; then
        old_pid="$(head -n 1 "$pid_path")"
        if is_running "$old_pid"; then
            printf 'Job %s is already running as PID %s.\n' "$job" "$old_pid" >&2
            exit 73
        fi
    fi

    : > "$log_path"
    printf '%s\n' "$log_path" > "$(log_file_record "$job")"
    cd "$PROJECT_DIR"
    nohup "$MATLAB_BIN" -batch "$job" -prefersoftwareopengl > "$log_path" 2>&1 < /dev/null &
    pid=$!
    printf '%s\n' "$pid" > "$pid_path.tmp"
    mv -f "$pid_path.tmp" "$pid_path"
    sleep 1
    if ! is_running "$pid"; then
        printf 'MATLAB exited during startup. Last log lines:\n' >&2
        tail -n 30 "$log_path" >&2 || true
        exit 70
    fi
    printf 'STARTED\nJOB=%s\nPID=%s\nLOG=%s\n' "$job" "$pid" "$log_path"
}

tail_job() {
    local job="$1"
    local lines="${2:-40}"
    local log_path
    validate_job "$job"
    [[ "$lines" =~ ^[1-9][0-9]*$ ]] || { printf 'Lines must be a positive integer.\n' >&2; exit 64; }
    log_path="$(read_log_path "$job")"
    [[ -f "$log_path" ]] || { printf 'Log not found: %s\n' "$log_path" >&2; exit 66; }
    tail -n "$lines" "$log_path"
}

bundle_job() {
    local job="$1" result_prefix
    local bundle log_path rel
    local -a files=()
    validate_job "$job"
    bundle="$JOBS_DIR/$job-results.tar.gz"
    # Aggregators write a shared result stem without their _aggregate suffix.
    result_prefix="${job%_aggregate}"

    while IFS= read -r -d '' file; do
        files+=("$(basename "$file")")
    done < <(find "$PROJECT_DIR" -maxdepth 1 -type f \
        \( -name "$result_prefix*.mat" -o -name "$result_prefix*.log" -o -name "$result_prefix*.csv" -o -name "$result_prefix*.txt" \) -print0)

    if [[ -d "$PROJECT_DIR/fig" ]]; then
        while IFS= read -r -d '' file; do
            files+=("fig/$(basename "$file")")
        done < <(find "$PROJECT_DIR/fig" -maxdepth 1 -type f \
            \( -name "$result_prefix*.fig" -o -name "$result_prefix*.png" -o -name "$result_prefix*.eps" \) -print0)
    fi

    log_path="$(read_log_path "$job")"
    if [[ -f "$log_path" && "$log_path" == "$PROJECT_DIR/"* ]]; then
        rel="${log_path#"$PROJECT_DIR/"}"
        files+=("$rel")
    fi
    (( ${#files[@]} > 0 )) || { printf 'No result files found for %s.\n' "$job" >&2; exit 66; }
    tar -czf "$bundle" -C "$PROJECT_DIR" -- "${files[@]}"
    printf '%s\n' "$bundle"
}

cancel_job() {
    local job="$1"
    local pid_path pid
    validate_job "$job"
    pid_path="$(pid_file "$job")"
    [[ -s "$pid_path" ]] || { printf 'No tracked PID for %s.\n' "$job" >&2; exit 66; }
    pid="$(head -n 1 "$pid_path")"
    is_running "$pid" || { printf 'Job %s is not running.\n' "$job"; exit 0; }
    kill -TERM "$pid"
    printf 'TERM_SENT\nJOB=%s\nPID=%s\n' "$job" "$pid"
}

adopt_job() {
    local job="$1"
    local pid="$2"
    local log_path="$3"
    validate_job "$job"
    [[ "$pid" =~ ^[0-9]+$ ]] || { printf 'PID must be numeric.\n' >&2; exit 64; }
    [[ "$log_path" == "$PROJECT_DIR/"* ]] || { printf 'Log must be inside %s.\n' "$PROJECT_DIR" >&2; exit 64; }
    is_running "$pid" || { printf 'PID %s is not running.\n' "$pid" >&2; exit 69; }
    printf '%s\n' "$pid" > "$(pid_file "$job")"
    printf '%s\n' "$log_path" > "$(log_file_record "$job")"
    printf 'ADOPTED\nJOB=%s\nPID=%s\nLOG=%s\n' "$job" "$pid" "$log_path"
}

command="${1:-}"
case "$command" in
    start)
        [[ $# -eq 2 ]] || { usage >&2; exit 64; }
        start_job "$2"
        ;;
    status)
        if [[ $# -eq 2 ]]; then
            status_one "$2"
        elif [[ $# -eq 1 ]]; then
            shopt -s nullglob
            pid_files=("$JOBS_DIR"/*.pid)
            if (( ${#pid_files[@]} == 0 )); then
                printf 'NO_TRACKED_JOBS\n'
            else
                for file in "${pid_files[@]}"; do
                    status_one "$(basename "$file" .pid)"
                    printf '\n'
                done
            fi
        else
            usage >&2
            exit 64
        fi
        ;;
    tail)
        [[ $# -ge 2 && $# -le 3 ]] || { usage >&2; exit 64; }
        tail_job "$2" "${3:-40}"
        ;;
    bundle)
        [[ $# -eq 2 ]] || { usage >&2; exit 64; }
        bundle_job "$2"
        ;;
    cancel)
        [[ $# -eq 2 ]] || { usage >&2; exit 64; }
        cancel_job "$2"
        ;;
    adopt)
        [[ $# -eq 4 ]] || { usage >&2; exit 64; }
        adopt_job "$2" "$3" "$4"
        ;;
    *)
        usage >&2
        exit 64
        ;;
esac
