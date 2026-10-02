#!/system/bin/sh
# ============================================================
# gpu-desktop.sh — activar / desactivar desktop com GPU (Zink)
#
# Uso:
#   /data/linux/gpu-desktop.sh          # = start
#   /data/linux/gpu-desktop.sh start    # setup GPU se falta + Zink + x11-start
#   /data/linux/gpu-desktop.sh stop     # x11-stop
#   /data/linux/gpu-desktop.sh cpu     # XFCE_USE_ZINK=0 + restart XFCE
#   /data/linux/gpu-desktop.sh status  # markers + conf + status
#
# Boot automatico NAO sobe XFCE — so o container (99-linux.sh).
# ============================================================

. /data/linux/common.sh 2>/dev/null || . "$(dirname "$0")/common.sh"

ensure_dirs

CMD="${1:-start}"
CONF_HOST="$ROOT/etc/artix-x11.conf"
MARKER_GLES="$ROOT/etc/artix-gpu-gles.ok"
MARKER_HYBRIS="$ROOT/etc/artix-gpu-hybris.ok"
MARKER_ZINK="$ROOT/etc/artix-gpu-zink.ok"

die() {
  echo "!! $*"
  exit 1
}

ensure_container() {
  if [ ! -f "$PIDF" ] || ! container_vivo "$(cat "$PIDF" 2>/dev/null)"; then
    echo ">> container parado — linux-start..."
    sh "$BASE/linux-start.sh" || die "linux-start falhou — /data/linux/linux-status.sh"
  fi
  mount_rootfs_rw >/dev/null 2>&1 || true
}

set_xfce_zink() {
  val="$1"
  [ -f "$CONF_HOST" ] || die "falta $CONF_HOST — corre bootstrap ou run-setup-xfce"
  if grep -q '^XFCE_USE_ZINK=' "$CONF_HOST"; then
    sed -i "s/^XFCE_USE_ZINK=.*/XFCE_USE_ZINK=$val/" "$CONF_HOST"
  else
    echo "XFCE_USE_ZINK=$val" >> "$CONF_HOST"
  fi
  echo ">> XFCE_USE_ZINK=$val em /etc/artix-x11.conf"
}

restart_xfce_only() {
  ensure_container
  PID=$(cat "$PIDF")
  NSARGS=$(nsenter_ns_args "$PID")
  run_chroot() {
    # shellcheck disable=SC2086
    $BB nsenter $NSARGS -- $BB chroot "$ROOT" /usr/bin/env -i \
      HOME=/root TERM=linux LANG=C.UTF-8 DISPLAY=:0 \
      PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
      "$@"
  }
  echo ">> a reiniciar sessao XFCE..."
  run_chroot dinitctl stop xfce-x11 2>/dev/null || true
  run_chroot /usr/local/bin/xfce-x11-session.sh stop 2>/dev/null || true
  sleep 2
  run_chroot dinitctl start xfce-x11 2>/dev/null \
    || run_chroot /usr/local/bin/xfce-x11-session.sh start &
  sleep 4
  am start --user 0 -n com.termux.x11/com.termux.x11.MainActivity >/dev/null 2>&1 || true
  if run_chroot dinitctl is-started xfce-x11 >/dev/null 2>&1; then
    echo ">> xfce-x11 OK"
  else
    echo "!! xfce-x11 nao activo — tenta: /data/linux/x11-start.sh"
    return 1
  fi
}

cmd_status() {
  echo "=== gpu-desktop status ==="
  ensure_container 2>/dev/null || true
  for m in artix-gpu-gles.ok artix-gpu-hybris.ok artix-gpu-zink.ok artix-mesa25.ok; do
    if [ -f "$ROOT/etc/$m" ]; then
      echo "[ok]  /etc/$m"
    else
      echo "[--]  /etc/$m ausente"
    fi
  done
  if [ -f "$CONF_HOST" ]; then
    echo "--- artix-x11.conf ---"
    grep -E '^(X11_USER|X11_DISPLAY|XFCE_USE_ZINK)=' "$CONF_HOST" 2>/dev/null || cat "$CONF_HOST"
  else
    echo "[--]  artix-x11.conf ausente"
  fi
  echo "--- linux-status (GPU/X11) ---"
  /data/linux/linux-status.sh 2>/dev/null | grep -E 'X11|xfce|Termux|GPU|Mali|Zink|hybris|mesa' || true
}

cmd_stop() {
  [ -x "$BASE/x11-stop.sh" ] || die "x11-stop.sh ausente"
  sh "$BASE/x11-stop.sh"
}

cmd_cpu() {
  ensure_container
  set_xfce_zink 0
  if [ -S /data/data/com.termux/files/usr/tmp/.X11-unix/X0 ] \
    || [ -S "$ROOT/tmp/.X11-unix/X0" ]; then
    restart_xfce_only || sh "$BASE/x11-start.sh"
  else
    echo ">> sem X11 activo — sobe com softGL:"
    sh "$BASE/x11-start.sh" || die "x11-start falhou"
  fi
  echo ">> desktop em softGL (CPU). GPU: /data/linux/gpu-desktop.sh start"
}

cmd_start() {
  ensure_container

  need_setup=0
  [ -f "$MARKER_GLES" ] || need_setup=1
  [ -f "$MARKER_HYBRIS" ] || need_setup=1

  if [ "$need_setup" = 1 ]; then
    echo ">> GPU setup em falta — a correr run-setup-gpu-hybris.sh..."
    [ -x "$BASE/run-setup-gpu-hybris.sh" ] || die "run-setup-gpu-hybris.sh ausente — prepare.sh"
    # DISPLAY para Fase G (Zink) se X11 ja existir; senao setup soft-fail Zink
    export DISPLAY="${DISPLAY:-:0}"
    sh "$BASE/run-setup-gpu-hybris.sh" || die "GPU setup falhou — ver log / gpu-check.sh"
  else
    echo ">> GPU markers OK (gles + hybris)"
  fi

  if [ -f "$MARKER_ZINK" ]; then
    set_xfce_zink 1
  else
    echo "!! sem artix-gpu-zink.ok — desktop softGL (CPU)"
    echo "   Com X11 activo: DISPLAY=:0 /data/linux/run-setup-gpu-hybris.sh"
    echo "   Depois: /data/linux/gpu-desktop.sh start"
    if [ -f "$CONF_HOST" ] && ! grep -q '^XFCE_USE_ZINK=' "$CONF_HOST"; then
      set_xfce_zink 0
    fi
  fi

  [ -x "$BASE/x11-start.sh" ] || die "x11-start.sh ausente"
  echo ">> a subir Termux:X11 + XFCE..."
  sh "$BASE/x11-start.sh" || die "x11-start falhou"

  echo
  echo "=== desktop ==="
  if [ -f "$MARKER_ZINK" ]; then
    echo " GL: Zink → Vulkan Mali (XFCE_USE_ZINK=1)"
  else
    echo " GL: softpipe (CPU) — Zink marker ausente"
  fi
  echo " ecran: app Termux:X11"
  echo " status: /data/linux/gpu-desktop.sh status"
  echo " parar:  /data/linux/gpu-desktop.sh stop"
  echo " CPU:    /data/linux/gpu-desktop.sh cpu"
}

case "$CMD" in
  start)  cmd_start ;;
  stop)   cmd_stop ;;
  cpu)    cmd_cpu ;;
  status) cmd_status ;;
  -h|--help|help)
    cat <<'EOF'
uso: gpu-desktop.sh [start|stop|cpu|status]
  start   setup GPU se preciso + XFCE_USE_ZINK=1 + x11-start
  stop    para Termux:X11 / XFCE
  cpu     desktop softGL (XFCE_USE_ZINK=0)
  status  markers + conf + resumo
EOF
    ;;
  *)
    die "comando desconhecido: $CMD (start|stop|cpu|status)"
    ;;
esac
exit 0
