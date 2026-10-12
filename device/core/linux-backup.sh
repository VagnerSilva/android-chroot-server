#!/system/bin/sh

SCRIPT=/data/linux/backup-rootfs.sh
[ -f "$SCRIPT" ] || SCRIPT="$(dirname "$0")/backup-rootfs.sh"
exec sh "$SCRIPT" "$@"