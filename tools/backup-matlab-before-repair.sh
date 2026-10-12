#!/usr/bin/env bash
set -Eeuo pipefail
umask 077
repair_root=/home/jzm123/AAA_ZTEproject/.jobs/matlab_repair/20261010_1037
source_matlab=/home/jzm123/MATLAB/R2022b
source_experiment=/home/jzm123/AAA_ZTEproject/.jobs/experiments/ris_beta_sweep_mc50_20261010_double
mkdir -p "$repair_root"
exec 9> "$repair_root/backup.lock"
flock -n 9
test ! -e "$repair_root/BACKUP_COMPLETE"
test ! -e "$repair_root/backup"
mkdir "$repair_root/backup"
printf 'BACKUP_BEGIN %s\n' "$(date -Is)"
cp -a --reflink=auto "$source_matlab" "$repair_root/backup/MATLAB_R2022b"
printf 'MATLAB_COPY_COMPLETE %s\n' "$(date -Is)"
cp -a --reflink=auto "$source_experiment" "$repair_root/backup/experiment"
cp -a /home/jzm123/AAA_ZTEproject/.jobs/diagnostics/toolbox-isolation-20261010 "$repair_root/backup/diagnostics"
plugin_relative=bin/glnxa64/matlab_startup_plugins/lmgrimpl/libmwlmgrimpl.so
cmp "$source_matlab/$plugin_relative" "$repair_root/backup/MATLAB_R2022b/$plugin_relative"
(
    cd "$repair_root/backup"
    find MATLAB_R2022b -type f -print0 | sort -z | xargs -0 sha256sum > MATLAB_SHA256SUMS.txt
    find experiment -type f ! -name '*.lock' -print0 | sort -z | xargs -0 sha256sum > EXPERIMENT_SHA256SUMS.txt
)
printf 'BACKUP_COMPLETE %s\n' "$(date -Is)" > "$repair_root/BACKUP_COMPLETE"
cat "$repair_root/BACKUP_COMPLETE"
du -sh "$repair_root/backup"
