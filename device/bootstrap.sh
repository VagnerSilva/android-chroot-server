#!/system/bin/sh
# ============================================================
# bootstrap.sh — ambiente do zero (nucleo + user + XFCE)
#
# Ordem:
#   0) linux-stop (estado limpo — nao reutilizar container vivo)
#   1) install-rootfs se rootfs.img ausente
#   2) linux-start
#   3) run-setup SETUP_FULL=1 SKIP_GPU=1 (nucleo incl. sshd + user + XFCE)
#   4) x11-start (Termux:X11)
#   5) linux-status STRICT=1 REQUIRE_X11=1 REQUIRE_GPU=0
#
# sshd e servico dinit: sobe/valida no run-setup passo 4 (apos stubs).
# Se SSH falhar, run-setup ja saiu com erro — sem ensure tardio aqui.
#
# GPU hybris: passo MANUAL depois — /data/linux/run-setup-gpu-hybris.sh
# Rootfs inconsistente (pacman/libs): wipe-chroot.sh + bootstrap.sh
#
# Uso:
#   /data/linux/bootstrap.sh
#   CREATE_USER=1 ARTIX_USER=alice ARTIX_PASS='senha' /data/linux/bootstrap.sh
#
# Env:
#   CREATE_USER / ARTIX_USER / ARTIX_PASS / ARTIX_SUDO  (passados a run-setup)
#   SKIP_X11=1   so debug — salta x11-start e REQUIRE_X11
#   SKIP_GPU=0   para forcar GPU no bootstrap (nao recomendado nesta fase)
# ============================================================

. /data/linux/common.sh 2>/dev/null || . "$(dirname "$0")/common.sh"

if [ "$(id -u)" != "0" ]; then
  echo "!! precisa ser root (su / KernelSU)"
  exit 1
fi

SKIP_X11="${SKIP_X11:-0}"
SKIP_GPU="${SKIP_GPU:-1}"
ensure_dirs

have_tty() {
  [ -t 0 ] && return 0
  [ -c /dev/tty ] && return 0
  return 1
}

echo "============================================================"
echo " bootstrap — ambiente Artix do zero"
echo "============================================================"

# --- 0) estado limpo (dinit shutdown + kill PID do container) ---
echo
echo ">> estado limpo (linux-stop)..."
if [ -f "$PIDF" ] && container_vivo "$(cat "$PIDF")"; then
  sh /data/linux/linux-stop.sh || true
elif [ -f "$PIDF" ]; then
  rm -f "$PIDF"
fi
rmdir /data/linux/run/start.lock 2>/dev/null || true

# --- 1) rootfs ---
if [ ! -f "$IMG" ]; then
  echo
  echo ">> rootfs.img ausente — a instalar..."
  if [ ! -x /data/linux/install-rootfs.sh ]; then
    echo "!! install-rootfs.sh ausente — corre prepare.sh"
    exit 1
  fi
  sh /data/linux/install-rootfs.sh || {
    echo "!! install-rootfs falhou"
    exit 1
  }
else
  echo ">> rootfs.img OK: $IMG"
fi

# --- 2) start (sempre fresco apos stop) ---
echo
echo ">> a subir container..."
sh /data/linux/linux-start.sh || {
  echo "!! linux-start falhou"
  exit 1
}

# --- 3) setup (nucleo + user + XFCE; GPU off por defeito) ---
# setup-artix (via run-setup) faz pacman -Sy glibc cedo — evita GLIBC_2.43
# em xfce4-session/liblcms2 apos sync parcial do world.
echo
echo ">> run-setup SETUP_FULL=1 SKIP_GPU=$SKIP_GPU (nucleo + user + XFCE)..."
if [ ! -x /data/linux/run-setup.sh ]; then
  echo "!! run-setup.sh ausente — prepare.sh incompleto"
  exit 1
fi

# from-scratch: default do prompt = criar user (XFCE precisa)
export SETUP_FULL=1
export SKIP_GPU
export USER_PROMPT_DEFAULT=s
# propagar credenciais se ja definidas
[ -n "${CREATE_USER:-}" ] && export CREATE_USER
[ -n "${ARTIX_USER:-}" ] && export ARTIX_USER
[ -n "${ARTIX_PASS:-}" ] && export ARTIX_PASS
[ -n "${ARTIX_SUDO:-}" ] && export ARTIX_SUDO

# adb / su -c sem TTY: SETUP_FULL exige user — inferir ou falhar cedo
if [ -z "${CREATE_USER:-}" ] && ! have_tty; then
  _home_user=
  if [ -d "$ROOT/home" ]; then
    _home_user=$(ls -1 "$ROOT/home" 2>/dev/null | head -n1)
  fi
  if [ -n "$_home_user" ]; then
    export CREATE_USER=0
    export ARTIX_USER="${ARTIX_USER:-$_home_user}"
    echo ">> sem TTY: utilizador existente $ARTIX_USER (CREATE_USER=0)"
  elif [ -n "${ARTIX_USER:-}" ] && [ -n "${ARTIX_PASS:-}" ]; then
    export CREATE_USER=1
    echo ">> sem TTY: CREATE_USER=1 ARTIX_USER=$ARTIX_USER"
  else
    echo "!! adb/sem TTY: SETUP_FULL precisa de utilizador"
    echo "   CREATE_USER=1 ARTIX_USER=<nome> ARTIX_PASS='senha' /data/linux/bootstrap.sh"
    exit 1
  fi
fi

sh /data/linux/run-setup.sh || {
  echo "!! run-setup falhou"
  exit 1
}

# recuperar ARTIX_USER se criado / ja conhecido
if [ -z "${ARTIX_USER:-}" ] && [ -d "$ROOT/home" ]; then
  ARTIX_USER=$(ls -1 "$ROOT/home" 2>/dev/null | head -n1)
  export ARTIX_USER
fi

# --- 4) X11 ---
if [ "$SKIP_X11" = "1" ]; then
  echo
  echo ">> SKIP_X11=1 — a saltar x11-start (debug)"
else
  echo
  echo ">> x11-start (Termux:X11 + XFCE)..."
  APK_PATH=$(pm path com.termux.x11 2>/dev/null | head -n1 | cut -d: -f2)
  if [ -z "$APK_PATH" ] || [ ! -f "$APK_PATH" ]; then
    echo "!! falta a app Termux:X11 (pacote com.termux.x11)"
    echo "   Instala via F-Droid ou GitHub (termux-x11-universal-debug.apk nightly)"
    echo "   Depois: /data/linux/x11-start.sh"
    echo "   Ou re-corre: /data/linux/bootstrap.sh"
    exit 1
  fi
  if [ ! -x /data/linux/x11-start.sh ]; then
    echo "!! x11-start.sh ausente"
    exit 1
  fi
  if [ -n "${ARTIX_USER:-}" ]; then
    ARTIX_USER="$ARTIX_USER" sh /data/linux/x11-start.sh || {
      echo "!! x11-start falhou"
      exit 1
    }
  else
    sh /data/linux/x11-start.sh || {
      echo "!! x11-start falhou"
      exit 1
    }
  fi
fi

# --- 5) gate de sucesso (sshd ja validado no run-setup passo 4) ---
echo
echo "============================================================"
echo " gate de sucesso (STRICT)"
echo "============================================================"
REQ_X11=1
[ "$SKIP_X11" = "1" ] && REQ_X11=0
REQ_GPU=1
[ "$SKIP_GPU" = "1" ] && REQ_GPU=0
if ! STRICT=1 REQUIRE_X11="$REQ_X11" REQUIRE_GPU="$REQ_GPU" sh /data/linux/linux-status.sh; then
  echo
  echo "!! bootstrap INCOMPLETO — corrige os [!!] acima e re-corre"
  exit 1
fi

# Autostart KernelSU (idempotente; prepare tambem instala)
if [ -x /data/linux/install-autostart.sh ]; then
  sh /data/linux/install-autostart.sh || {
    echo "!! install-autostart falhou"
    exit 1
  }
elif [ "${SKIP_AUTOSTART:-0}" != 1 ] && [ -f /data/linux/99-linux.sh ]; then
  mkdir -p /data/adb/service.d
  cp /data/linux/99-linux.sh /data/adb/service.d/99-linux.sh
  chmod 755 /data/adb/service.d/99-linux.sh
  echo ">> autostart OK: /data/adb/service.d/99-linux.sh"
fi

echo
echo "============================================================"
echo " bootstrap OK — nucleo + XFCE"
if [ "$SKIP_GPU" = "1" ]; then
  echo " GPU/desktop: /data/linux/gpu-desktop.sh"
  echo "   (1a vez: setup hybris + Zink + Termux:X11; depois so sobe o ecran)"
fi
if [ -n "${ARTIX_USER:-}" ]; then
  echo " user: $ARTIX_USER"
  echo " shell: /data/linux/linux-shell.sh $ARTIX_USER"
fi
echo " status: /data/linux/linux-status.sh"
echo " autostart: /data/adb/service.d/99-linux.sh (container apos boot)"
echo "============================================================"
exit 0
