#!/system/bin/sh
# ============================================================
# linux-stop.sh - desliga dinit e desmonta a imagem
# ============================================================

. /data/linux/common.sh 2>/dev/null || . "$(dirname "$0")/common.sh"

ensure_dirs
touch "$RUN/stopped"

# best-effort: parar Termux:X11 / XFCE antes do shutdown
if [ -f "$PIDF" ] && kill -0 "$(cat "$PIDF")" 2>/dev/null; then
  sh /data/linux/x11-stop.sh 2>/dev/null || true
fi

if [ -f "$PIDF" ]; then
  PID=$(cat "$PIDF")
  if kill -0 "$PID" 2>/dev/null; then
    NSARGS=$(nsenter_ns_args "$PID")
    echo ">> tentando dinitctl shutdown via nsenter ($NSARGS)"
    # shellcheck disable=SC2086
    $BB nsenter $NSARGS -- \
      $BB chroot "$ROOT" /usr/bin/dinitctl shutdown 2>/dev/null \
      || $BB nsenter $NSARGS -- \
           $BB chroot "$ROOT" /bin/dinitctl shutdown 2>/dev/null \
      || true
    kill -TERM "$PID" 2>/dev/null
    i=0
    while kill -0 "$PID" 2>/dev/null && [ $i -lt 20 ]; do
      sleep 1
      i=$((i + 1))
    done
    kill -KILL "$PID" 2>/dev/null
  fi
  rm -f "$PIDF"
fi

sync
$BB umount "$ROOT" 2>/dev/null
for L in $($BB losetup -a 2>/dev/null | grep rootfs.img | cut -d: -f1); do
  $BB losetup -d "$L" 2>/dev/null
done

echo linux_server > /sys/power/wake_unlock 2>/dev/null
echo ">> parado"
