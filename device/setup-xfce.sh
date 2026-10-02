#!/bin/sh
# ============================================================
# setup-xfce.sh — corre DENTRO do chroot Artix
# Instala XFCE4 para Termux:X11 (GPU). Sem TigerVNC/llvmpipe.
#
# Env:
#   ARTIX_USER     user alvo (default: primeiro em /home)
#   X11_DISPLAY    default :0
# ============================================================
set -e

echo ">> setup XFCE + Termux:X11"

DISPLAY_NUM="${X11_DISPLAY:-:0}"

USER_NAME="${ARTIX_USER:-}"
if [ -z "$USER_NAME" ]; then
  for d in /home/*; do
    [ -d "$d" ] || continue
    n=$(basename "$d")
    [ "$n" = "lost+found" ] && continue
    USER_NAME="$n"
    break
  done
fi
if [ -z "$USER_NAME" ]; then
  echo "!! nenhum utilizador — defina ARTIX_USER=<nome>"
  echo "   crie com: CREATE_USER=1 ARTIX_USER=<nome> ARTIX_PASS='senha' /data/linux/run-setup.sh"
  echo "   ou: /data/linux/artix-user.sh create <nome> '<senha>'"
  exit 1
fi

if ! id "$USER_NAME" >/dev/null 2>&1; then
  echo "!! utilizador nao existe: $USER_NAME"
  echo "   crie com: /data/linux/artix-user.sh create $USER_NAME '<senha>'"
  exit 1
fi

HOME_DIR=$(getent passwd "$USER_NAME" | cut -d: -f6)
[ -n "$HOME_DIR" ] || HOME_DIR="/home/$USER_NAME"
[ -d "$HOME_DIR" ] || {
  echo "!! home inexistente: $HOME_DIR"
  exit 1
}

echo ">> user=$USER_NAME home=$HOME_DIR display=$DISPLAY_NUM"

# glibc primeiro — lcms2/xfce4-session precisam de simbolos recentes
echo ">> pacman: glibc"
pacman -Sy --noconfirm --needed glibc || pacman -S --noconfirm glibc || {
  echo "!! falha a actualizar glibc — mirrors/rede?"
  exit 1
}

# Mesa 25.1.2 overlay (/opt/android-mali) — NAO instalar mesa>=26 do pacman
# (free(): invalid pointer / size com softGL e hybris)
if [ -f /root/install-mesa25-android-mali.sh ]; then
  echo ">> mesa25 overlay (em vez de pacman mesa 26)"
  /bin/bash /root/install-mesa25-android-mali.sh || {
    echo "!! install-mesa25-android-mali falhou"
    exit 1
  }
else
  echo "!! /root/install-mesa25-android-mali.sh ausente — corre prepare + run-setup-xfce"
  exit 1
fi

echo ">> pacman: xfce4 + mesa-utils (sem mesa pacman / sem tigervnc)"
pacman -Sy --noconfirm --needed --overwrite='*' \
  xfce4 xfce4-goodies mesa-utils dbus \
  || pacman -S --noconfirm --needed --overwrite='*' \
  xfce4 xfce4-goodies mesa-utils dbus

mkdir -p "$HOME_DIR/.config/xfce4/xfconf/xfce-perchannel-xml" \
  /var/log/dinit /usr/local/bin /etc/dinit.d/boot.d
chown -R "$USER_NAME:$USER_NAME" "$HOME_DIR/.config"

# xstartup auxiliar (sessao real e gerida por xfce-x11-session.sh)
cat > "$HOME_DIR/.x11-xstartup" <<'EOF'
#!/bin/sh
unset SESSION_MANAGER
unset DBUS_SESSION_BUS_ADDRESS
export XDG_SESSION_TYPE=x11
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/tmp}"
[ -r "$HOME/.Xresources" ] && xrdb "$HOME/.Xresources"
if command -v dbus-launch >/dev/null 2>&1; then
  exec dbus-launch --exit-with-session startxfce4
else
  exec startxfce4
fi
EOF
chmod 755 "$HOME_DIR/.x11-xstartup"
chown "$USER_NAME:$USER_NAME" "$HOME_DIR/.x11-xstartup"

# conf persistente
# XFCE_USE_ZINK=1 → desktop via Zink→Vulkan Mali (requer artix-gpu-zink.ok).
# Default 0 = softGL (CPU). Env XFCE_USE_ZINK tem prioridade; senao preserva conf.
_ENV_ZINK="${XFCE_USE_ZINK-}"
_PREV_ZINK=0
if [ -f /etc/artix-x11.conf ]; then
  # shellcheck disable=SC1091
  . /etc/artix-x11.conf 2>/dev/null || true
  _PREV_ZINK="${XFCE_USE_ZINK:-0}"
fi
if [ -n "$_ENV_ZINK" ]; then
  XFCE_USE_ZINK="$_ENV_ZINK"
else
  XFCE_USE_ZINK="$_PREV_ZINK"
fi
cat > /etc/artix-x11.conf <<EOF
X11_USER=$USER_NAME
X11_DISPLAY=$DISPLAY_NUM
XFCE_USE_ZINK=$XFCE_USE_ZINK
EOF
chmod 644 /etc/artix-x11.conf
unset _ENV_ZINK _PREV_ZINK

# seed xfconf: box_move/resize ON; compositor OFF (Termux:X11+softGL = tela preta)
XFWM_XML="$HOME_DIR/.config/xfce4/xfconf/xfce-perchannel-xml/xfwm4.xml"
if [ ! -f "$XFWM_XML" ]; then
  cat > "$XFWM_XML" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xfwm4" version="1.0">
  <property name="general" type="empty">
    <property name="box_move" type="bool" value="true"/>
    <property name="box_resize" type="bool" value="true"/>
    <property name="use_compositing" type="bool" value="false"/>
  </property>
</channel>
EOF
else
  # actualizar keys sem destruir o resto (sed simples)
  if grep -q 'name="box_move"' "$XFWM_XML"; then
    sed -i 's/name="box_move" type="bool" value="[^"]*"/name="box_move" type="bool" value="true"/' "$XFWM_XML"
  fi
  if grep -q 'name="box_resize"' "$XFWM_XML"; then
    sed -i 's/name="box_resize" type="bool" value="[^"]*"/name="box_resize" type="bool" value="true"/' "$XFWM_XML"
  fi
  if grep -q 'name="use_compositing"' "$XFWM_XML"; then
    sed -i 's/name="use_compositing" type="bool" value="[^"]*"/name="use_compositing" type="bool" value="false"/' "$XFWM_XML"
  else
    sed -i '/name="general" type="empty"/a\    <property name="use_compositing" type="bool" value="false"/>' "$XFWM_XML"
  fi
fi
chown "$USER_NAME:$USER_NAME" "$XFWM_XML"

# wrapper sessao (fonte: xfce-x11-session.sh no host apos prepare)
if [ -f /data/linux/xfce-x11-session.sh ]; then
  cp /data/linux/xfce-x11-session.sh /usr/local/bin/xfce-x11-session.sh
else
  cat > /usr/local/bin/xfce-x11-session.sh <<'EOF'
#!/bin/sh
# Arranca / para XFCE no DISPLAY do Termux:X11
set -e
CONF=/etc/artix-x11.conf
[ -f "$CONF" ] || { echo "!! falta $CONF"; exit 1; }
# shellcheck disable=SC1090
. "$CONF"
: "${X11_DISPLAY:=:0}"
if [ -z "${X11_USER:-}" ]; then
  echo "!! X11_USER vazio em $CONF — corre run-setup-xfce.sh com ARTIX_USER=<nome>"
  exit 1
fi

HOME_DIR=$(getent passwd "$X11_USER" | cut -d: -f6)
[ -n "$HOME_DIR" ] || HOME_DIR="/home/$X11_USER"
DISP_N="${X11_DISPLAY#:}"
SOCK="/tmp/.X11-unix/X${DISP_N}"

apply_wm_prefs() {
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
  sleep 1
}

case "${1:-start}" in
  stop)
    kill_session
    exit 0
    ;;
  start|*)
    if [ ! -S "$SOCK" ]; then
      echo "!! sem socket X11 $SOCK — corre /data/linux/x11-start.sh"
      exit 1
    fi
    kill_session
    apply_wm_prefs
    RUNTIMEDIR="/tmp/runtime-${X11_USER}"
    mkdir -p "$RUNTIMEDIR"
    chown "$X11_USER:$X11_USER" "$RUNTIMEDIR" 2>/dev/null || true
    chmod 700 "$RUNTIMEDIR" 2>/dev/null || true
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
       # Manter HYBRIS_LD_LIBRARY_PATH do profile (libgpud_sys.so p/ Vulkan ICD)
       if command -v dbus-launch >/dev/null 2>&1; then \
         exec dbus-launch --exit-with-session startxfce4; \
       else \
         exec startxfce4; \
       fi"
    ;;
esac
EOF
fi
chmod 755 /usr/local/bin/xfce-x11-session.sh

# dinit: sessao XFCE (servidor X vem do x11-start.sh)
cat > /etc/dinit.d/xfce-x11 <<'EOF'
# XFCE sobre Termux:X11 — DISPLAY :0
type            = process
command         = /usr/local/bin/xfce-x11-session.sh start
stop-command    = /usr/local/bin/xfce-x11-session.sh stop
restart         = true
smooth-recovery = true
logfile         = /var/log/dinit/xfce-x11.log
waits-for       = dbus
EOF
chmod 644 /etc/dinit.d/xfce-x11

# nao activar no boot automatico (depende da app Android)
rm -f /etc/dinit.d/boot.d/xfce-x11 2>/dev/null || true
rm -f /etc/dinit.d/boot.d/vncserver 2>/dev/null || true

echo
echo ">> XFCE/Termux:X11 OK"
echo "   user=$USER_NAME display=$DISPLAY_NUM"
echo "   Pre-requisito Android: app Termux:X11 (com.termux.x11)"
echo "   Dia a dia:"
echo "     /data/linux/x11-start.sh"
echo "     /data/linux/x11-stop.sh"
echo "   GPU: DISPLAY=:0 gpu-vulkan-run vkcube"
