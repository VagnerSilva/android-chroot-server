#!/system/bin/sh
# Host wrapper: corre gpu-run DENTRO do chroot
. /data/linux/common.sh 2>/dev/null || . "$(dirname "$0")/common.sh"

if [ ! -f "$PIDF" ] || ! container_vivo "$(cat "$PIDF")"; then
  echo "!! container parado — /data/linux/linux-start.sh"
  exit 1
fi

PID=$(cat "$PIDF")
NSARGS=$(nsenter_ns_args "$PID")
# shellcheck disable=SC2086
exec $BB nsenter $NSARGS -- $BB chroot "$ROOT" /usr/bin/env -i \
  HOME=/root TERM="${TERM:-linux}" LANG=C.UTF-8 \
  DISPLAY="${DISPLAY:-:0}" XDG_RUNTIME_DIR=/tmp TMPDIR=/tmp \
  GPU_USE_ZINK="${GPU_USE_ZINK:-}" \
  PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
  /usr/local/bin/gpu-run "$@"
