#!/system/bin/sh
# linux-status.sh — estado actual do container
#
# Env:
#   STRICT=1       exit 1 se faltar nucleo (sshd/dbus/elogind/socket)
#   REQUIRE_X11=1  com STRICT: tambem exige socket X11 :0 / Termux:X11
#   REQUIRE_GPU=1  com STRICT: exige GPU GLES/wrappers (default 1; bootstrap com SKIP_GPU usa 0)
#
. /data/linux/common.sh 2>/dev/null || . "$(dirname "$0")/common.sh"

STRICT="${STRICT:-0}"
REQUIRE_X11="${REQUIRE_X11:-0}"
REQUIRE_GPU="${REQUIRE_GPU:-1}"
STATUS_RC=0
set -eu

ok()   { echo "  [ok]  $*"; }
fail() { echo "  [!!]  $*"; STATUS_RC=1; }
info() { echo "  [--]  $*"; }

echo "=== linux $(date '+%H:%M:%S') ==="

# mount
if LINE=$(grep " $ROOT " /proc/mounts 2>/dev/null); then
  echo "$LINE" | grep -q ' rw,' && ok "mount RW" || fail "mount sem RW"
  echo "$LINE" | grep -q nosuid && fail "nosuid" || ok "suid"
  echo "$LINE" | grep -q nodev && fail "nodev" || ok "dev"
else
  fail "imagem nao montada"
fi

# container
VIVO=0
if [ -f "$PIDF" ] && container_vivo "$(cat "$PIDF")"; then
  VIVO=1
  NS=$([ -f "$RUN/unshare.mode" ] && cat "$RUN/unshare.mode" || echo mount)
  ok "container vivo (pid $(cat "$PIDF"), ns=$NS)"
else
  fail "container parado"
fi

# rede
IP_CIDR=$(ip -4 addr show 2>/dev/null | awk '/inet / && /wlan|eth|rndis|rmnet/ {print $2; exit}')
[ -n "$IP_CIDR" ] && ok "rede $IP_CIDR" || info "rede (sem IP wlan/eth)"

# timezone (Android persist.sys.timezone vs /etc/timezone no rootfs)
AND_TZ=$(getprop persist.sys.timezone 2>/dev/null)
CHROOT_TZ=
[ -f "$ROOT/etc/timezone" ] && CHROOT_TZ=$(tr -d '\n' < "$ROOT/etc/timezone")
TZ_OFF=
if [ "$VIVO" = 1 ]; then
  TZ_OFF=$(run_in_chroot /bin/date '+%z' 2>/dev/null || printf '')
fi
if [ -z "$AND_TZ" ]; then
  info "timezone (Android sem persist.sys.timezone)"
elif [ -z "$CHROOT_TZ" ]; then
  fail "timezone Android=$AND_TZ — /etc/timezone ausente"
elif [ "$AND_TZ" = "$CHROOT_TZ" ]; then
  if [ -n "$TZ_OFF" ]; then
    # %z = -0300 → UTC-3
    sign=$(printf '%s' "$TZ_OFF" | cut -c1)
    hour=$(printf '%s' "$TZ_OFF" | cut -c2-3 | sed 's/^0//')
    [ -z "$hour" ] && hour=0
    ok "timezone $CHROOT_TZ (UTC${sign}${hour})"
  else
    ok "timezone $CHROOT_TZ"
  fi
else
  fail "timezone Android=$AND_TZ chroot=$CHROOT_TZ"
fi

# servicos + GPU (so com container vivo)
X11_UP=0
SVC_SSHD=0
SVC_DBUS=0
SVC_ELOGIND=0
SVC_DBUS_SOCK=0
SVC_X11=0
GPU_WRAP=0

if [ "$VIVO" = 1 ]; then
  SVC_OUT=$("$BASE/check-services.sh" 2>/dev/null || true)
  echo "$SVC_OUT" | grep '  \[' || true
  echo "$SVC_OUT" | grep -q '^OK_sshd=1' && SVC_SSHD=1
  echo "$SVC_OUT" | grep -q '^OK_dbus=1' && SVC_DBUS=1
  echo "$SVC_OUT" | grep -q '^OK_elogind=1' && SVC_ELOGIND=1
  echo "$SVC_OUT" | grep -q '^OK_dbus_sock=1' && SVC_DBUS_SOCK=1
  echo "$SVC_OUT" | grep -q '^OK_x11=1' && SVC_X11=1

  # STRICT: nucleo obrigatorio
  if [ "$STRICT" = "1" ]; then
    [ "$SVC_SSHD" = 1 ] || fail "sshd nao started (STRICT)"
    [ "$SVC_DBUS" = 1 ] || fail "dbus nao started (STRICT)"
    [ "$SVC_ELOGIND" = 1 ] || fail "elogind nao started (STRICT)"
    [ "$SVC_DBUS_SOCK" = 1 ] || fail "dbus socket ausente (STRICT)"
  fi

  TERMUX_X0=/data/data/com.termux/files/usr/tmp/.X11-unix/X0
  if [ -S "$ROOT/tmp/.X11-unix/X0" ] || [ -S "$TERMUX_X0" ] || [ -S "$RUN/x11-tmp/.X11-unix/X0" ]; then
    X11_UP=1
    SVC_X11=1
    ok "Termux:X11 DISPLAY=:0"
  fi

  GPU_LINE=$("$BASE/check-gpu.sh" 2>/dev/null || true)
  GPU_STATUS=$(echo "$GPU_LINE" | grep '^GPU_STATUS=' | cut -d= -f2-) || GPU_STATUS=
  GPU_DRIVER=$(echo "$GPU_LINE" | grep '^GPU_DRIVER=' | cut -d= -f2-) || GPU_DRIVER=
  GPU_DEV=$(echo "$GPU_LINE" | grep '^GPU_DEV=' | cut -d= -f2-) || GPU_DEV=
  GPU_CARD=$(echo "$GPU_LINE" | grep '^GPU_CARD=' | cut -d= -f2-) || GPU_CARD=
  GPU_RENDER=$(echo "$GPU_LINE" | grep '^GPU_RENDER=' | cut -d= -f2-) || GPU_RENDER=
  GPU_TREE=$(echo "$GPU_LINE" | grep '^GPU_TREE=' | cut -d= -f2-) || GPU_TREE=
  GPU_MESA25=$(echo "$GPU_LINE" | grep '^GPU_MESA25=' | cut -d= -f2-) || GPU_MESA25=
  GPU_HYB=$(echo "$GPU_LINE" | grep '^GPU_HYB=' | cut -d= -f2-) || GPU_HYB=
  GPU_GLES=$(echo "$GPU_LINE" | grep '^GPU_GLES=' | cut -d= -f2-) || GPU_GLES=
  GPU_VK=$(echo "$GPU_LINE" | grep '^GPU_VK=' | cut -d= -f2-) || GPU_VK=
  GPU_BIND=$(echo "$GPU_LINE" | grep '^GPU_BIND=' | cut -d= -f2-) || GPU_BIND=
  GPU_ICD=$(echo "$GPU_LINE" | grep '^GPU_ICD=' | cut -d= -f2-) || GPU_ICD=
  GPU_WRAP=$(echo "$GPU_LINE" | grep '^GPU_WRAP=' | cut -d= -f2-) || GPU_WRAP=

  case "$GPU_STATUS" in
    ok)
      ok "GPU OK — ${GPU_DRIVER:-desconhecido}"
      ;;
    info)
      if [ "$STRICT" = "1" ] && [ "$REQUIRE_GPU" = "1" ]; then
        fail "GPU — ${GPU_DRIVER:-desconhecido}"
      else
        info "GPU — ${GPU_DRIVER:-desconhecido}"
      fi
      ;;
    *)
      if [ "$STRICT" = "1" ] && [ "$REQUIRE_GPU" = "1" ]; then
        fail "GPU — ${GPU_DRIVER:-check falhou}"
      else
        info "GPU — ${GPU_DRIVER:-check falhou}"
      fi
      ;;
  esac
  [ "$GPU_DEV" = 1 ] && ok "GPU kernel (/dev/mali0)" || info "GPU /dev/mali0 ausente"
  [ "$GPU_CARD" = 1 ] && ok "DRM card0 (mediatek-drm)" || info "DRM card0 ausente"
  if [ "$GPU_RENDER" = 1 ]; then
    info "DRM renderD* presente"
  else
    info "DRM renderD* ausente (esperado — sem Panfrost)"
  fi
  if [ "$GPU_TREE" = 1 ]; then
    ok "Android Mali userspace (/opt/android-mali/vendor)"
  else
    info "/opt/android-mali/vendor ausente (corra run-setup-gpu-hybris)"
  fi
  if [ "$GPU_MESA25" = 1 ]; then
    ok "Mesa 25.1.2 overlay (/opt/android-mali/lib)"
  else
    info "Mesa 25 overlay ausente"
  fi
  [ "$GPU_HYB" = 1 ] && ok "libhybris" || info "libhybris ausente"
  [ "$GPU_GLES" = 1 ] && ok "GLES marker (artix-gpu-gles.ok)" || info "GLES marker ausente"
  [ "$GPU_VK" = 1 ] && ok "Vulkan marker (artix-gpu-hybris.ok)" || info "Vulkan marker ausente (apos GLES)"
  [ "$GPU_BIND" = 1 ] && info "extract bind /mnt/vendor" || true
  if [ "$GPU_ICD" = 1 ]; then
    ok "GPU ICD Vulkan configurado"
  else
    info "GPU ICD Vulkan ausente (ok se so GLES)"
  fi
  if [ "$STRICT" = "1" ] && [ "$REQUIRE_GPU" = "1" ] && [ "$GPU_WRAP" != "1" ]; then
    fail "GPU wrappers (gpu-egl-run) ausentes"
  elif [ "$GPU_WRAP" = 1 ]; then
    ok "GPU wrappers"
  else
    info "GPU wrappers ausentes"
  fi
  if [ "$STRICT" = "1" ] && [ "$REQUIRE_GPU" != "1" ]; then
    info "REQUIRE_GPU=0 — GPU nao e gate STRICT"
  fi
else
  info "GPU (container parado — sem check)"
  [ "$STRICT" = "1" ] && [ "$REQUIRE_GPU" = "1" ] && STATUS_RC=1
fi

if [ "$STRICT" = "1" ] && [ "$REQUIRE_X11" = "1" ]; then
  if [ "$SVC_X11" != "1" ] && [ "$X11_UP" != "1" ]; then
    fail "X11 socket :0 obrigatorio (Termux:X11)"
  fi
fi

echo "========================="

if [ "$STRICT" = "1" ]; then
  exit "$STATUS_RC"
fi
exit 0
