#!/system/bin/sh
# ============================================================
# x11-stop.sh — para XFCE + Termux:X11 sem derrubar o container
# su -c "/data/linux/x11-stop.sh"
# ============================================================

. /data/linux/common.sh 2>/dev/null || . "$(dirname "$0")/common.sh"

TERMUX_TMP=/data/data/com.termux/files/usr/tmp
SOCK_X0="$TERMUX_TMP/.X11-unix/X0"

stop_termux_x11() {
  # pede a app para desligar a ligacao / fechar (receiver LorieApp)
  am broadcast --user 0 -a com.termux.x11.ACTION_STOP -p com.termux.x11 \
    --receiver-include-background >/dev/null 2>&1 || true
  am broadcast -a com.termux.x11.ACTION_STOP -p com.termux.x11 >/dev/null 2>&1 || true

  # matar servidor X (nice-name inclui espacos: "termux-x11 com.termux.x11 :0")
  pkill -f 'com.termux.x11.CmdEntryPoint' 2>/dev/null || true
  pkill -f 'com.termux.x11.Loader' 2>/dev/null || true
  pkill -f 'termux-x11 com.termux.x11' 2>/dev/null || true
  pkill -f 'nice-name=termux-x11' 2>/dev/null || true
  pkill -f '/termux-x11-chroot' 2>/dev/null || true
  pkill -f '/bin/termux-x11' 2>/dev/null || true

  if [ -f "$RUN/termux-x11.pid" ]; then
    kill "$(cat "$RUN/termux-x11.pid")" 2>/dev/null || true
    rm -f "$RUN/termux-x11.pid"
  fi

  # remover socket residual (senao x11-start "reutiliza" e fica ecran preto)
  rm -f "$SOCK_X0" "$TERMUX_TMP/.X11-unix/X0" 2>/dev/null || true
  rm -f /tmp/.X11-unix/X0 2>/dev/null || true

  sleep 1
}

if [ ! -f "$PIDF" ] || ! container_vivo "$(cat "$PIDF")"; then
  echo "container parado — a matar Termux:X11 residual…"
  stop_termux_x11
  echo "OK"
  exit 0
fi

PID=$(cat "$PIDF")
NSARGS=$(nsenter_ns_args "$PID")

# shellcheck disable=SC2086
$BB nsenter $NSARGS -- $BB chroot "$ROOT" /usr/bin/env -i \
  HOME=/root TERM=linux LANG=C.UTF-8 \
  PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
  dinitctl stop xfce-x11 2>/dev/null || true

# shellcheck disable=SC2086
$BB nsenter $NSARGS -- $BB chroot "$ROOT" /usr/bin/env -i \
  PATH=/usr/bin:/bin \
  /usr/local/bin/xfce-x11-session.sh stop 2>/dev/null || true

# shellcheck disable=SC2086
$BB nsenter $NSARGS -- pkill -f 'xfce4-session|startxfce4|xfwm4|xfdesktop|xfce4-panel|xfce-fit-windows' 2>/dev/null || true

stop_termux_x11

# desfazer bind do socket no container
if [ -f "$PIDF" ] && container_vivo "$(cat "$PIDF")"; then
  PID=$(cat "$PIDF")
  NSARGS=$(nsenter_ns_args "$PID")
  # shellcheck disable=SC2086
  $BB nsenter $NSARGS -- umount "$ROOT/tmp/.X11-unix" 2>/dev/null || true
  # shellcheck disable=SC2086
  $BB nsenter $NSARGS -- rm -f "$ROOT/tmp/.X11-unix/X0" 2>/dev/null || true
fi

echo "OK — X11/XFCE parado (container continua a correr)"
echo "  subir de novo: /data/linux/x11-start.sh"
echo "  parar tudo:    /data/linux/linux-stop.sh"
