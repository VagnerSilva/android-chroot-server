#!/bin/sh
# ============================================================
# xfce-x11-session.sh — sessao XFCE no DISPLAY do Termux:X11
# Instalado em /usr/local/bin pelo setup-xfce.sh
# Conf: /etc/artix-x11.conf
#
# Desktop default: softGL (LIBGL_ALWAYS_SOFTWARE=1 + Mesa 25.1.2).
# Opcional: XFCE_USE_ZINK=1 + /etc/artix-gpu-zink.ok → Zink→Vulkan Mali.
# Fallback automatico para softGL se marker/zink-run ausentes.
# ============================================================
set -e
CONF=/etc/artix-x11.conf
[ -f "$CONF" ] || { echo "!! falta $CONF"; exit 1; }
# shellcheck disable=SC1090
. "$CONF"
: "${X11_DISPLAY:=:0}"
: "${XFCE_USE_ZINK:=0}"
if [ -z "${X11_USER:-}" ]; then
  echo "!! X11_USER vazio em $CONF — corre run-setup-xfce.sh com ARTIX_USER=<nome>"
  exit 1
fi

HOME_DIR=$(getent passwd "$X11_USER" | cut -d: -f6)
[ -n "$HOME_DIR" ] || HOME_DIR="/home/$X11_USER"
DISP_N="${X11_DISPLAY#:}"
SOCK="/tmp/.X11-unix/X${DISP_N}"

# Decide GL: Zink (GPU) ou softGL (CPU)
USE_ZINK=0
if [ "$XFCE_USE_ZINK" = 1 ]; then
  if [ -f /etc/artix-gpu-zink.ok ] && [ -x /usr/local/bin/zink-run ]; then
    USE_ZINK=1
  else
    echo "!! XFCE_USE_ZINK=1 mas falta artix-gpu-zink.ok ou zink-run — softGL"
  fi
fi

apply_wm_prefs() {
  # box_move/resize ON; compositor OFF (Termux:X11 — softGL=tela preta;
  # com Zink manter OFF ate validar estabilidade)
  XFWM_XML="$HOME_DIR/.config/xfce4/xfconf/xfce-perchannel-xml/xfwm4.xml"
  mkdir -p "$(dirname "$XFWM_XML")"
  if [ -f "$XFWM_XML" ] && grep -q 'name="use_compositing"' "$XFWM_XML"; then
    sed -i 's/name="use_compositing" type="bool" value="[^"]*"/name="use_compositing" type="bool" value="false"/' "$XFWM_XML"
  elif [ -f "$XFWM_XML" ]; then
    sed -i '/name="general" type="empty"/a\    <property name="use_compositing" type="bool" value="false"/>' "$XFWM_XML"
  fi
  chown "$X11_USER:$X11_USER" "$XFWM_XML" 2>/dev/null || true
  RUNTIMEDIR="/tmp/runtime-${X11_USER}"
  mkdir -p "$RUNTIMEDIR"
  chown "$X11_USER:$X11_USER" "$RUNTIMEDIR" 2>/dev/null || true
  chmod 700 "$RUNTIMEDIR" 2>/dev/null || true
  su -l "$X11_USER" -s /bin/sh -c "
    export DISPLAY='$X11_DISPLAY' XDG_RUNTIME_DIR='$RUNTIMEDIR'
    if command -v xfconf-query >/dev/null 2>&1; then
      xfconf-query -c xfwm4 -p /general/box_move -n -t bool -s true 2>/dev/null \
        || xfconf-query -c xfwm4 -p /general/box_move -s true 2>/dev/null || true
      xfconf-query -c xfwm4 -p /general/box_resize -n -t bool -s true 2>/dev/null \
        || xfconf-query -c xfwm4 -p /general/box_resize -s true 2>/dev/null || true
      xfconf-query -c xfwm4 -p /general/use_compositing -n -t bool -s false 2>/dev/null \
        || xfconf-query -c xfwm4 -p /general/use_compositing -s false 2>/dev/null || true
    fi
  " || true
}

kill_session() {
  pkill -u "$X11_USER" -f 'xfce4-session' 2>/dev/null || true
  pkill -u "$X11_USER" -f 'startxfce4' 2>/dev/null || true
  # nao matar o servidor X (Termux:X11)
  sleep 1
}

case "${1:-start}" in
  stop)
    kill_session
    exit 0
    ;;
  start|*)
    if [ ! -S "$SOCK" ]; then
      echo "!! sem socket X11 $SOCK — corre /data/linux/x11-start.sh (Termux:X11)"
      exit 1
    fi
    kill_session
    apply_wm_prefs
    RUNTIMEDIR="/tmp/runtime-${X11_USER}"
    mkdir -p "$RUNTIMEDIR"
    chown "$X11_USER:$X11_USER" "$RUNTIMEDIR" 2>/dev/null || true
    chmod 700 "$RUNTIMEDIR" 2>/dev/null || true

    if [ "$USE_ZINK" = 1 ]; then
      echo ">> XFCE GL: Zink → Vulkan Mali (XFCE_USE_ZINK=1)"
      if command -v dbus-launch >/dev/null 2>&1; then
        exec su -l "$X11_USER" -s /bin/sh -c \
          "export DISPLAY='$X11_DISPLAY' XDG_RUNTIME_DIR='$RUNTIMEDIR' TMPDIR=/tmp XDG_SESSION_TYPE=x11; \
           unset SESSION_MANAGER DBUS_SESSION_BUS_ADDRESS; \
           unset HYBRIS_TLS_PATCH; \
           exec /usr/local/bin/zink-run dbus-launch --exit-with-session startxfce4"
      fi
      exec su -l "$X11_USER" -s /bin/sh -c \
        "export DISPLAY='$X11_DISPLAY' XDG_RUNTIME_DIR='$RUNTIMEDIR' TMPDIR=/tmp XDG_SESSION_TYPE=x11; \
         unset SESSION_MANAGER DBUS_SESSION_BUS_ADDRESS; \
         unset HYBRIS_TLS_PATCH; \
         exec /usr/local/bin/zink-run startxfce4"
    fi

    echo ">> XFCE GL: softpipe (CPU)"
    exec su -l "$X11_USER" -s /bin/sh -c \
      "export DISPLAY='$X11_DISPLAY' XDG_RUNTIME_DIR='$RUNTIMEDIR' TMPDIR=/tmp XDG_SESSION_TYPE=x11; \
       unset SESSION_MANAGER DBUS_SESSION_BUS_ADDRESS; \
       unset HYBRIS_TLS_PATCH; \
       unset GALLIUM_DRIVER MESA_LOADER_DRIVER_OVERRIDE; \
       export LD_LIBRARY_PATH=/opt/android-mali/lib; \
       export LIBGL_DRIVERS_PATH=/opt/android-mali/lib/dri; \
       export GBM_BACKENDS_PATH=/opt/android-mali/lib/gbm; \
       export __EGL_VENDOR_LIBRARY_DIRS=/opt/android-mali/share/glvnd/egl_vendor.d; \
       export LIBGL_ALWAYS_SOFTWARE=1; \
       # Manter HYBRIS_LD_LIBRARY_PATH do profile (libgpud_sys.so p/ Vulkan ICD);
       # softGL usa LD_LIBRARY_PATH Mesa — hybris LD nao mistura libs Linux.
       if command -v dbus-launch >/dev/null 2>&1; then \
         exec dbus-launch --exit-with-session startxfce4; \
       else \
         exec startxfce4; \
       fi"
    ;;
esac
