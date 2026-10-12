#!/usr/bin/env bash
# Run only after the complete backup and a clean stop of the experiment.
set -Eeuo pipefail
umask 077
repair=/home/jzm123/AAA_ZTEproject/.jobs/matlab_repair/20261010_1037
installation=/home/jzm123/MATLAB/R2022b
relative=bin/glnxa64/matlab_startup_plugins/lmgrimpl/libmwlmgrimpl.so
target="$installation/$relative"
original="$repair/original_component/clean/$relative"
backup="$repair/critical_backup/libmwlmgrimpl.so"
experiment=/home/jzm123/AAA_ZTEproject/.jobs/experiments/ris_beta_sweep_mc50_20261010_double
# The checksum manifest is opened only after every copy succeeded. Full-file
# hashing can continue against the immutable backup while this test runs.
if [[ ! -f "$repair/BACKUP_COMPLETE" ]]; then
    test -f "$repair/backup/MATLAB_SHA256SUMS.txt"
    test -d "$repair/backup/experiment"
    test -d "$repair/backup/diagnostics"
    cmp "$backup" "$repair/backup/MATLAB_R2022b/$relative"
fi
cmp "$target" "$backup"
[[ $(sha256sum "$original" | cut -d' ' -f1) == 4e52640dbf8401b04f13b435becb382100de61c91eef48409da33faaa020c498 ]]
exec 8> "$experiment/.jobs/ris_beta_sweep_mc50_20261010_double.lock"
flock -n 8
# This repair owns only the RIS experiment. Refuse to affect unrelated MATLABs.
if pgrep -u "$(id -u)" -x MATLAB > /dev/null; then
    echo 'MATLAB processes still active; replacement not performed.'
    exit 73
fi
cp -a "$experiment" "$repair/pre_switch_experiment"
changed=0
rollback() {
    rc=$?
    if (( changed )); then
        cp -a "$backup" "${target}.restore-tmp"
        mv -f "${target}.restore-tmp" "$target"
        cmp "$backup" "$target"
        printf 'ROLLED_BACK %s\n' "$(date -Is)" > "$repair/repair.state"
    fi
    exit "$rc"
}
trap rollback EXIT
cp -a "$original" "${target}.repair-tmp"
chmod --reference="$target" "${target}.repair-tmp"
changed=1
mv -f "${target}.repair-tmp" "$target"
printf 'ORIGINAL_LIBRARY_INSTALLED %s\n' "$(date -Is)" > "$repair/repair.state"
cd "$repair"
rc=0
env RIS_DIAG_MODE=base OMP_NUM_THREADS=1 MKL_NUM_THREADS=1 MALLOC_ARENA_MAX=2 \
    timeout --signal=TERM --kill-after=10 260 "$installation/bin/matlab" \
    -singleCompThread -batch diagnose_toolbox_runtime > restored-library-idle.out 2>&1 < /dev/null || rc=$?
printf 'ORIGINAL_LIBRARY_IDLE_EXIT=%d\n' "$rc"
if (( rc != 0 )); then tail -n 35 restored-library-idle.out; exit "$rc"; fi
grep -q '^ISOLATION_COMPLETE' restored-library-idle.out
if grep -Eq 'malloc\(\):|free\(\):|double free or corruption|corrupted (size|double-linked)' restored-library-idle.out; then exit 70; fi
changed=0
printf 'IDLE_VALIDATED %s\n' "$(date -Is)" > "$repair/repair.state"
cat "$repair/repair.state"
