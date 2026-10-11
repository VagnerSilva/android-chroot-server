#!/system/bin/sh
# ============================================================
# linux-stop.sh - desliga dinit e desmonta a imagem
# ============================================================

. /data/linux/common.sh 2>/dev/null || . "$(dirname "$0")/common.sh"

set -eu

ensure_dirs
must touch "$RUN/stopped" || exit 1

# best-effort: parar Termux:X11 / XFCE antes do shutdown
if [ -f "$PIDF" ] && kill -0 "$(cat "$PIDF")" 2>/dev/null; then
  sh /data/linux/x11-stop.sh 2>/dev/null || true
fi

if [ -f "$PIDF" ]; then
  PID=$(cat "$PIDF" 2>/dev/null || printf '')
  if [ -n "$PID" ] && kill -0 "$PID" 2>/dev/null; then
    echo ">> tentando dinitctl shutdown via run_in_chroot"
    run_in_chroot /usr/bin/dinitctl shutdown 2>/dev/null || \
      run_in_chroot /bin/dinitctl shutdown 2>/dev/null || true
    kill -TERM "$PID" 2>/dev/null || true
    i=0
    while kill -0 "$PID" 2>/dev/null && [ $i -lt 20 ]; do
      sleep 1
      i=$((i + 1))
    done
    kill -KILL "$PID" 2>/dev/null || true
  fi
  rm -f "$PIDF"
fi

sync || true
$BB umount "$ROOT" 2>/dev/null || true
for L in $($BB losetup -a 2>/dev/null | grep rootfs.img | cut -d: -f1 || true); do
  $BB losetup -d "$L" 2>/dev/null || true
done

echo linux_server > /sys/power/wake_unlock 2>/dev/null || true
echo ">> parado"
