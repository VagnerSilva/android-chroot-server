#!/system/bin/sh
# ============================================================
# x11-start.sh — Termux:X11 (GPU) + sessao XFCE no chroot
# su -c "/data/linux/x11-start.sh"
#
# Requer:
#   1) APK Termux:X11 (com.termux.x11)
#   2) companion loader (instalado automaticamente se ausente)
#   3) ARTIX_USER=<user> /data/linux/run-setup-xfce.sh  (1a vez)
# ============================================================

. /data/linux/common.sh 2>/dev/null || . "$(dirname "$0")/common.sh"

ensure_dirs

START_SH="$BASE/linux-start.sh"
[ -x "$START_SH" ] || START_SH="$(dirname "$0")/linux-start.sh"

TERMUX_PREFIX=/data/data/com.termux/files/usr
TERMUX_HOME=/data/data/com.termux/files/home
LOADER_APK="$TERMUX_PREFIX/libexec/termux-x11/loader.apk"
TERMUX_X11_BIN="$TERMUX_PREFIX/bin/termux-x11"
TERMUX_X11_WRAPPER="$TERMUX_PREFIX/bin/termux-x11-chroot"
TERMUX_UID=$(stat -c %u /data/data/com.termux 2>/dev/null || echo 10425)
# Socket no TMPDIR nativo do Termux (mesmo path do arranque normal)
TERMUX_TMP="$TERMUX_PREFIX/tmp"
SOCK_DIR="$TERMUX_TMP/.X11-unix"
SOCK_X0="$SOCK_DIR/X0"
TERMUX_PROPS="$TERMUX_HOME/.termux/termux.properties"

require_termux_x11_apk() {
  APK_PATH=$(pm path com.termux.x11 2>/dev/null | head -n1 | cut -d: -f2)
  if [ -z "$APK_PATH" ] || [ ! -f "$APK_PATH" ]; then
    echo "!! falta a app Termux:X11 (pacote com.termux.x11)"
    echo
    echo "   O Termux base (com.termux) NAO chega — precisa da app Termux:X11."
    echo "   Instala via:"
    echo "     - F-Droid: Termux:X11"
    echo "     - GitHub:  https://github.com/termux/termux-x11/releases"
    echo "       (recomendado: termux-x11-universal-debug.apk da tag nightly)"
    echo
    echo "   Depois de instalar, corre de novo:"
    echo "     /data/linux/x11-start.sh"
    exit 1
  fi
  echo "$APK_PATH"
}

ensure_loader() {
  # companion: loader.apk + script (Android 14+ exige dex nao-writable)
  mkdir -p "$TERMUX_PREFIX/libexec/termux-x11" "$TERMUX_PREFIX/bin"
  if [ ! -f "$LOADER_APK" ] && [ -f "$BASE/termux-x11/loader.apk" ]; then
    cp "$BASE/termux-x11/loader.apk" "$LOADER_APK"
  fi
  if [ -f "$BASE/termux-x11/termux-x11" ]; then
    cp "$BASE/termux-x11/termux-x11" "$TERMUX_X11_BIN"
    chmod 755 "$TERMUX_X11_BIN"
    chown "$TERMUX_UID:$TERMUX_UID" "$TERMUX_X11_BIN" 2>/dev/null || true
  fi
  if [ -f "$BASE/termux-x11/termux-x11-chroot" ]; then
    cp "$BASE/termux-x11/termux-x11-chroot" "$TERMUX_X11_WRAPPER"
    chmod 755 "$TERMUX_X11_WRAPPER"
    chown "$TERMUX_UID:$TERMUX_UID" "$TERMUX_X11_WRAPPER" 2>/dev/null || true
  fi
  if [ ! -f "$LOADER_APK" ]; then
    echo "!! falta companion Termux:X11 (loader.apk)"
    echo "   Em Termux: pkg i x11-repo && pkg i termux-x11-nightly"
    echo "   Ou coloca loader.apk em /data/linux/termux-x11/loader.apk"
    echo "   Download: https://github.com/termux/termux-x11/releases (nightly *.pkg.tar.xz)"
    exit 1
  fi
  # critico Android 14+: Writable dex is not allowed
  chmod 400 "$LOADER_APK"
  chown "$TERMUX_UID:$TERMUX_UID" "$LOADER_APK" 2>/dev/null || true
}

ensure_termux_external_apps() {
  # necessario para RunCommandService (arranque no contexto Termux)
  mkdir -p "$TERMUX_HOME/.termux"
  if [ ! -f "$TERMUX_PROPS" ]; then
    printf '%s\n' 'allow-external-apps = true' > "$TERMUX_PROPS"
  elif grep -qE '^[[:space:]]*allow-external-apps[[:space:]]*=' "$TERMUX_PROPS"; then
    # garantir true (comentado ou false)
    if ! grep -qE '^[[:space:]]*allow-external-apps[[:space:]]*=[[:space:]]*true' "$TERMUX_PROPS"; then
      sed -i 's/^[[:space:]]*#*[[:space:]]*allow-external-apps[[:space:]]*=.*/allow-external-apps = true/' "$TERMUX_PROPS"
    fi
  else
    printf '\n%s\n' 'allow-external-apps = true' >> "$TERMUX_PROPS"
  fi
  chown "$TERMUX_UID:$TERMUX_UID" "$TERMUX_PROPS" 2>/dev/null || true
  chmod 600 "$TERMUX_PROPS" 2>/dev/null || true
}

prepare_termux_tmpdir() {
  mkdir -p "$SOCK_DIR"
  # .X11-unix nao pode ficar root:root 755 — o Loader (uid Termux) nao cria X0
  chown -R "$TERMUX_UID:$TERMUX_UID" "$TERMUX_TMP" 2>/dev/null || true
  chmod 1777 "$TERMUX_TMP" "$SOCK_DIR"
}

run_chroot() {
  PID=$(cat "$PIDF" 2>/dev/null)
  [ -n "$PID" ] || return 1
  NSARGS=$(nsenter_ns_args "$PID")
  # shellcheck disable=SC2086
  $BB nsenter $NSARGS -- $BB chroot "$ROOT" /usr/bin/env -i \
    HOME=/root TERM=linux LANG=C.UTF-8 \
    PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
    "$@"
}

run_ns() {
  PID=$(cat "$PIDF" 2>/dev/null)
  [ -n "$PID" ] || return 1
  NSARGS=$(nsenter_ns_args "$PID")
  # shellcheck disable=SC2086
  $BB nsenter $NSARGS -- "$@"
}

start_cmd_entrypoint() {
  # Mesmo TMPDIR do Termux normal; depois bind SOCK_DIR no mount ns do container
  prepare_termux_tmpdir

  # Reutilizar so se o servidor X ainda esta vivo (senao ecran preto)
  if [ -S "$SOCK_X0" ] && pgrep -f 'termux-x11 com.termux.x11' >/dev/null 2>&1; then
    echo ">> socket X11 ja presente em $SOCK_X0 — a reutilizar"
    return 0
  fi

  # limpar estado morto (socket orfao / processo a meio)
  pkill -f 'com.termux.x11.Loader' 2>/dev/null || true
  pkill -f 'com.termux.x11.CmdEntryPoint' 2>/dev/null || true
  pkill -f 'termux-x11 com.termux.x11' 2>/dev/null || true
  pkill -f 'nice-name=termux-x11' 2>/dev/null || true
  sleep 1
  rm -f "$SOCK_X0" 2>/dev/null || true

  setenforce 0 2>/dev/null || true
  ensure_termux_external_apps

  # abrir a app de visualizacao antes do servidor (evita ecran preto sem surface)
  am start --user 0 -n com.termux.x11/com.termux.x11.MainActivity >/dev/null 2>&1 \
    || am start -n com.termux.x11/.MainActivity >/dev/null 2>&1 \
    || true
  # Termux app precisa estar vivo para RunCommandService
  am start --user 0 -n com.termux/.app.TermuxActivity >/dev/null 2>&1 || true
  sleep 1

  WRAP="$TERMUX_X11_WRAPPER"
  [ -x "$WRAP" ] || WRAP="$TERMUX_X11_BIN"
  echo ">> Termux:X11 :0 via RunCommandService (TMPDIR=$TERMUX_TMP)"

  # Arranque no contexto zygote do Termux (mesmo path em que funciona normalmente)
  am startservice --user 0 \
    -n com.termux/.app.RunCommandService \
    -a com.termux.RUN_COMMAND \
    --es com.termux.RUN_COMMAND_PATH "$WRAP" \
    --esa com.termux.RUN_COMMAND_ARGUMENTS ':0' \
    --es com.termux.RUN_COMMAND_WORKDIR "$TERMUX_HOME" \
    --ez com.termux.RUN_COMMAND_BACKGROUND true \
    --es com.termux.RUN_COMMAND_LABEL 'artix-x11' \
    >>"$LOG" 2>&1 || true

  j=0
  while [ "$j" -lt 40 ]; do
    if [ -S "$SOCK_X0" ] && pgrep -f 'termux-x11 com.termux.x11' >/dev/null 2>&1; then
      # trazer a app para a frente apos o binder ACTION_START
      am start --user 0 -n com.termux.x11/com.termux.x11.MainActivity >/dev/null 2>&1 || true
      return 0
    fi
    j=$((j + 1))
    sleep 0.5
  done
  return 1
}

bind_x11_socket() {
  PID=$(cat "$PIDF")
  NSARGS=$(nsenter_ns_args "$PID")
  # shellcheck disable=SC2086
  $BB nsenter $NSARGS -- mkdir -p "$ROOT/tmp/.X11-unix"
  # shellcheck disable=SC2086
  $BB nsenter $NSARGS -- umount "$ROOT/tmp/.X11-unix" 2>/dev/null || true
  # shellcheck disable=SC2086
  $BB nsenter $NSARGS -- mount --bind "$SOCK_DIR" "$ROOT/tmp/.X11-unix" || {
    echo "!! falha bind $SOCK_DIR -> container /tmp/.X11-unix"
    return 1
  }
  # shellcheck disable=SC2086
  $BB nsenter $NSARGS -- ls -la "$ROOT/tmp/.X11-unix"
}

# --- main ---
X11_APK=$(require_termux_x11_apk)
echo ">> Termux:X11 APK: $X11_APK"
ensure_loader

if [ ! -f "$PIDF" ] || ! container_vivo "$(cat "$PIDF")"; then
  echo ">> container parado — a subir…"
  sh "$START_SH" || {
    echo "!! falha em linux-start.sh"
    exit 1
  }
fi

i=0
while [ "$i" -lt 30 ]; do
  if [ -f "$PIDF" ] && container_vivo "$(cat "$PIDF")"; then
    if run_chroot dinitctl list >/dev/null 2>&1; then
      break
    fi
  fi
  i=$((i + 1))
  sleep 1
done

if [ ! -f "$PIDF" ] || ! container_vivo "$(cat "$PIDF")"; then
  echo "!! container nao ficou vivo"
  exit 1
fi

if [ ! -f "$ROOT/etc/artix-x11.conf" ] || [ ! -x "$ROOT/usr/local/bin/xfce-x11-session.sh" ]; then
  echo "!! XFCE/X11 ainda nao instalado no chroot"
  echo "   Corre primeiro:"
  echo "     ARTIX_USER=<user> /data/linux/run-setup-xfce.sh"
  exit 1
fi

X11_USER=""
X11_DISPLAY=:0
# shellcheck disable=SC1090
. "$ROOT/etc/artix-x11.conf"
: "${X11_DISPLAY:=:0}"
if [ -z "${X11_USER:-}" ]; then
  for d in "$ROOT"/home/*; do
    [ -d "$d" ] || continue
    n=$(basename "$d")
    [ "$n" = "lost+found" ] && continue
    X11_USER="$n"
    break
  done
fi
if [ -z "${X11_USER:-}" ]; then
  echo "!! X11_USER vazio — defina em $ROOT/etc/artix-x11.conf"
  echo "   ou: ARTIX_USER=<user> /data/linux/run-setup-xfce.sh"
  exit 1
fi

# parar VNC antigo
run_chroot dinitctl stop vncserver 2>/dev/null || true
run_ns pkill -f "Xvnc :" 2>/dev/null || true
rm -f "$ROOT/etc/dinit.d/boot.d/vncserver" 2>/dev/null || true

if ! start_cmd_entrypoint; then
  echo "!! socket X11 nao apareceu em $SOCK_X0"
  echo
  echo "   Confirma:"
  echo "     1) app Termux:X11 aberta no ecran"
  echo "     2) companion: $LOADER_APK (chmod 400)"
  echo "     3) TMPDIR Termux gravavel: $TERMUX_TMP (1777, uid $TERMUX_UID)"
  echo "     4) allow-external-apps=true em $TERMUX_PROPS"
  echo "   Ou arranca manualmente no Termux: termux-x11 :0  e corre x11-start de novo"
  echo "   log: $LOG"
  exit 1
fi

echo ">> socket X11 OK ($SOCK_X0) — a ligar ao chroot"
bind_x11_socket || exit 1

# dinit xfce-x11
DINIT_SRC="$BASE/dinit.d/xfce-x11"
[ -f "$DINIT_SRC" ] || DINIT_SRC="$(dirname "$0")/dinit.d/xfce-x11"
mkdir -p "$ROOT/etc/dinit.d/boot.d" "$ROOT/var/log/dinit"
if [ -f "$DINIT_SRC" ]; then
  cp "$DINIT_SRC" "$ROOT/etc/dinit.d/xfce-x11"
  strip_crlf "$ROOT/etc/dinit.d/xfce-x11"
  chmod 644 "$ROOT/etc/dinit.d/xfce-x11"
fi
rm -f "$ROOT/etc/dinit.d/boot.d/xfce-x11" 2>/dev/null || true

run_chroot dinitctl start dbus 2>/dev/null || true
run_chroot dinitctl stop xfce-x11 2>/dev/null || true
run_chroot dinitctl start xfce-x11 2>/dev/null \
  || run_chroot dinitctl restart xfce-x11 2>/dev/null \
  || run_chroot /usr/local/bin/xfce-x11-session.sh start &

sleep 3
# se a sessao morreu, pelo menos pintar o ecran (evita preto total)
if ! run_chroot dinitctl is-started xfce-x11 >/dev/null 2>&1; then
  echo "!! xfce-x11 nao ficou activo — a tentar startxfce4 directo"
  run_chroot /usr/local/bin/xfce-x11-session.sh start >/dev/null 2>&1 &
  sleep 2
fi
am start --user 0 -n com.termux.x11/com.termux.x11.MainActivity >/dev/null 2>&1 || true

echo
echo "=== Termux:X11 OK ==="
echo "  user:    $X11_USER"
echo "  display: $X11_DISPLAY"
echo "  ecran:   app Termux:X11"
echo "  status:  /data/linux/linux-status.sh"
echo "  parar:   /data/linux/x11-stop.sh"
echo "  GPU:     DISPLAY=:0 /data/linux/gpu-vulkan-run.sh vkcube"
echo "====================="
