#!/usr/bin/env bash
set -Eeuo pipefail
repair=/home/jzm123/AAA_ZTEproject/.jobs/matlab_repair/20261010_1037
target=/home/jzm123/MATLAB/R2022b/bin/glnxa64/matlab_startup_plugins/lmgrimpl/libmwlmgrimpl.so
backup="$repair/critical_backup/libmwlmgrimpl.so"
test -f "$repair/BACKUP_COMPLETE"
if pgrep -u "$(id -u)" -x MATLAB > /dev/null; then
    echo 'Stop MATLAB processes before rollback.'
    exit 73
fi
[[ $(sha256sum "$backup" | cut -d' ' -f1) == bea285ad9864b2ba7a98e7802a36213bb4d91c9c94013f4060a1a57344d25407 ]]
current=$(sha256sum "$target" | cut -d' ' -f1)
case "$current" in
    4e52640dbf8401b04f13b435becb382100de61c91eef48409da33faaa020c498|bea285ad9864b2ba7a98e7802a36213bb4d91c9c94013f4060a1a57344d25407) ;;
    *) echo 'Unexpected installed library; refusing overwrite.'; exit 65 ;;
esac
cp -a "$backup" "${target}.restore-tmp"
mv -f "${target}.restore-tmp" "$target"
cmp "$backup" "$target"
printf 'ROLLED_BACK %s\n' "$(date -Is)" > "$repair/repair.state"
cat "$repair/repair.state"
