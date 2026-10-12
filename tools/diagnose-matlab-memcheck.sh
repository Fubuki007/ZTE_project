#!/usr/bin/env bash
# Inspect invalid memory accesses without modifying the MATLAB installation.
set -eu
diag=/home/jzm123/AAA_ZTEproject/.jobs/diagnostics
cd "$diag/toolbox-isolation-20261010"
export VALGRIND_LIB="$diag/valgrind-runtime/usr/libexec/valgrind"
export OMP_NUM_THREADS=1 MKL_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 MALLOC_ARENA_MAX=2
export RIS_DIAG_MODE=base
# Valgrind 3.19 adds the ELF object's path to --extra-debuginfo-path;
# expose matching build-id symbols under that path in this private directory.
symbol_root="$diag/valgrind-runtime/usr/lib/debug"
mkdir -p "$symbol_root/usr/lib/x86_64-linux-gnu"
for module_file in /usr/lib/x86_64-linux-gnu/ld-linux-x86-64.so.2 /usr/lib/x86_64-linux-gnu/libc.so.6; do
    build_id=$(readelf -n "$module_file" | awk '/Build ID:/ {print $3; exit}')
    symbol_file="$symbol_root/.build-id/${build_id:0:2}/${build_id:2}.debug"
    test -f "$symbol_file"
    ln -sfn "$symbol_file" "$symbol_root/usr/lib/x86_64-linux-gnu/${build_id:2}.debug"
done
cat > memcheck-wrapper.sh <<'WRAPPER'
#!/usr/bin/env bash
exec /home/jzm123/AAA_ZTEproject/.jobs/diagnostics/valgrind-runtime/usr/bin/valgrind \
    --extra-debuginfo-path=/home/jzm123/AAA_ZTEproject/.jobs/diagnostics/valgrind-runtime/usr/lib/debug \
    --tool=memcheck --leak-check=no --track-origins=no --num-callers=30 \
    --error-limit=yes --log-file=memcheck-native.%p.log "$@"
WRAPPER
chmod +x memcheck-wrapper.sh
rc=0
timeout --signal=TERM --kill-after=10 600 /home/jzm123/MATLAB/R2022b/bin/matlab \
    -singleCompThread -nojvm -batch diagnose_toolbox_runtime \
    -D"$PWD/memcheck-wrapper.sh" > memcheck-matlab.out 2>&1 < /dev/null || rc=$?
printf 'MEMCHECK_EXIT=%d %s\n' "$rc" "$(date -Is)"
