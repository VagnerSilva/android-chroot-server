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
IP="${IP_CIDR%/*}"
[ -n "$IP_CIDR" ] && ok "rede $IP_CIDR" || info "rede (sem IP wlan/eth)"

# timezone (Android persist.sys.timezone vs /etc/timezone no rootfs)
AND_TZ=$(getprop persist.sys.timezone 2>/dev/null)
CHROOT_TZ=
[ -f "$ROOT/etc/timezone" ] && CHROOT_TZ=$(tr -d '\n' < "$ROOT/etc/timezone")
TZ_OFF=
if [ "$VIVO" = 1 ]; then
  PID=$(cat "$PIDF")
  NSARGS=$(nsenter_ns_args "$PID")
  # shellcheck disable=SC2086
  TZ_OFF=$($BB nsenter $NSARGS -- $BB chroot "$ROOT" /usr/bin/env -i \
    PATH=/usr/bin:/bin /bin/date '+%z' 2>/dev/null)
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
  PID=$(cat "$PIDF")
  NSARGS=$(nsenter_ns_args "$PID")
  # shellcheck disable=SC2086
  SVC_OUT=$($BB nsenter $NSARGS -- $BB chroot "$ROOT" /usr/bin/env -i \
    PATH=/usr/bin:/bin:/usr/sbin:/sbin /bin/sh -c '
      for s in sshd dbus elogind; do
        if dinitctl is-started "$s" >/dev/null 2>&1; then
          echo "OK_$s=1"
          echo "  [ok]  $s"
        else
          echo "OK_$s=0"
          if [ -e /etc/dinit.d/"$s" ]; then
            echo "  [!!]  $s"
            if [ "$s" = "sshd" ]; then
              # NOTA: este bloco corre dentro de sh -c '...' — NAO usar aspas
              # simples aninhadas (partem o script no Android/BusyBox).
              echo "  [--]  sshd diag: bin=$(command -v sshd 2>/dev/null || echo AUSENTE)"
              echo "  [--]  sshd diag: unit=$(head -n5 /etc/dinit.d/sshd 2>/dev/null | tr "\n" "|")"
              ST=$(dinitctl status sshd 2>&1 | head -n4 | tr "\n" ";")
              echo "  [--]  sshd diag: status=$ST"
              if [ -f /var/log/dinit/sshd.log ]; then
                echo "  [--]  sshd.log (ultimas):"
                tail -n 8 /var/log/dinit/sshd.log 2>/dev/null | sed "s/^/         /"
              else
                echo "  [--]  sshd.log ausente"
              fi
            fi
          fi
        fi
      done
      if [ -S /run/dbus/system_bus_socket ]; then
        echo "OK_dbus_sock=1"
        echo "  [ok]  dbus socket"
      else
        echo "OK_dbus_sock=0"
        echo "  [!!]  dbus socket"
      fi
      if [ -S /tmp/.X11-unix/X0 ]; then
        echo "OK_x11=1"
        echo "  [ok]  X11 socket :0"
        if dinitctl is-started xfce-x11 >/dev/null 2>&1; then
          echo "  [ok]  xfce-x11"
        elif [ -e /etc/dinit.d/xfce-x11 ]; then
          echo "  [!!]  xfce-x11"
        fi
      else
        echo "OK_x11=0"
        echo "  [--]  X11 socket :0 (Termux:X11 parado)"
      fi
    ')
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

  # GPU: camadas separadas — critério precoce = GLES (artix-gpu-gles.ok)
  # shellcheck disable=SC2086
  GPU_LINE=$($BB nsenter $NSARGS -- $BB chroot "$ROOT" /usr/bin/env -i \
    PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
    HOME=/root TERM=linux LANG=C.UTF-8 DISPLAY="${DISPLAY:-:0}" \
    /bin/sh -c '
      DEV=0
      ls /dev/mali0 >/dev/null 2>&1 && DEV=1
      CARD=0
      ls /dev/dri/card0 >/dev/null 2>&1 && CARD=1
      RENDER=0
      ls /sys/class/drm/renderD* >/dev/null 2>&1 && RENDER=1
      TREE=0
      [ -d /opt/android-mali/vendor/lib64 ] && TREE=1
      MESA25=0
      { [ -f /etc/artix-mesa25.ok ] || [ -f /opt/android-mali/lib/libgallium-25.1.2.so ]; } && MESA25=1
      HYB=0
      { [ -d /opt/libhybris ] || [ -d /usr/lib/libhybris ]; } && HYB=1
      GLES_MARK=0
      [ -f /etc/artix-gpu-gles.ok ] && GLES_MARK=1
      VK_MARK=0
      [ -f /etc/artix-gpu-hybris.ok ] && VK_MARK=1
      BIND=0
      [ -d /mnt/vendor/lib64 ] && BIND=1
      ICD=0
      WRAP=0
      [ -f /etc/artix-gpu.conf ] && . /etc/artix-gpu.conf
      [ -n "${GPU_ICD_FILE:-}" ] && [ -f "$GPU_ICD_FILE" ] && ICD=1
      if [ -x /usr/local/bin/gpu-egl-run ] || [ -x /usr/local/bin/gpu-vulkan-run ]; then
        WRAP=1
      fi

      GLES_NAME=""
      if [ "$GLES_MARK" = 1 ]; then
        GLES_NAME=$(grep "^RENDERER=" /etc/artix-gpu-gles.ok 2>/dev/null | head -n1 | cut -d= -f2-)
        [ -n "$GLES_NAME" ] || GLES_NAME="Mali (gles.ok)"
      fi

      VK_NAME=""
      if [ "$VK_MARK" = 1 ] && [ -x /usr/local/bin/gpu-vulkan-run ] && command -v vulkaninfo >/dev/null 2>&1; then
        export XDG_RUNTIME_DIR=/tmp TMPDIR=/tmp HYBRIS_TLS_PATCH=vulkan.mali.so
        mkdir -p /tmp
        (gpu-vulkan-run vulkaninfo --summary >/tmp/vk-status.txt 2>/tmp/vk-status.err) || true
        VK_FULL=$(cat /tmp/vk-status.txt 2>/dev/null | head -n 40)
        if echo "$VK_FULL" | grep -qiE "Mali-G[0-9]+|physicalDevices: count = [1-9]"; then
          VK_NAME=$(echo "$VK_FULL" | grep -oE "Mali-G[0-9]+[^[:space:]]*" | head -n1)
          [ -n "$VK_NAME" ] || VK_NAME="Mali (hybris)"
        fi
      fi

      DRIVER="nao configurado"
      STATUS=fail
      if [ -n "$VK_NAME" ] && [ "$GLES_MARK" = 1 ]; then
        DRIVER="gles+vulkan: $VK_NAME"
        STATUS=ok
      elif [ "$GLES_MARK" = 1 ]; then
        DRIVER="gles: ${GLES_NAME:-Mali}"
        STATUS=ok
      elif [ "$WRAP" = 0 ]; then
        DRIVER="setup-gpu-hybris pendente"
        STATUS=info
      elif [ "$DEV" = 1 ] && [ "$TREE" = 0 ]; then
        DRIVER="mali0 ok; /opt/android-mali pendente"
        STATUS=fail
      else
        DRIVER="sem GLES Mali (corra run-setup-gpu-hybris)"
        STATUS=fail
      fi

      echo "GPU_STATUS=$STATUS"
      echo "GPU_DRIVER=$DRIVER"
      echo "GPU_DEV=$DEV"
      echo "GPU_CARD=$CARD"
      echo "GPU_RENDER=$RENDER"
      echo "GPU_TREE=$TREE"
      echo "GPU_MESA25=$MESA25"
      echo "GPU_HYB=$HYB"
      echo "GPU_GLES=$GLES_MARK"
      echo "GPU_VK=$VK_MARK"
      echo "GPU_BIND=$BIND"
      echo "GPU_ICD=$ICD"
      echo "GPU_WRAP=$WRAP"
    ' 2>/dev/null)

  GPU_STATUS=$(echo "$GPU_LINE" | grep '^GPU_STATUS=' | cut -d= -f2-)
  GPU_DRIVER=$(echo "$GPU_LINE" | grep '^GPU_DRIVER=' | cut -d= -f2-)
  GPU_DEV=$(echo "$GPU_LINE" | grep '^GPU_DEV=' | cut -d= -f2-)
  GPU_CARD=$(echo "$GPU_LINE" | grep '^GPU_CARD=' | cut -d= -f2-)
  GPU_RENDER=$(echo "$GPU_LINE" | grep '^GPU_RENDER=' | cut -d= -f2-)
  GPU_TREE=$(echo "$GPU_LINE" | grep '^GPU_TREE=' | cut -d= -f2-)
  GPU_MESA25=$(echo "$GPU_LINE" | grep '^GPU_MESA25=' | cut -d= -f2-)
  GPU_HYB=$(echo "$GPU_LINE" | grep '^GPU_HYB=' | cut -d= -f2-)
  GPU_GLES=$(echo "$GPU_LINE" | grep '^GPU_GLES=' | cut -d= -f2-)
  GPU_VK=$(echo "$GPU_LINE" | grep '^GPU_VK=' | cut -d= -f2-)
  GPU_BIND=$(echo "$GPU_LINE" | grep '^GPU_BIND=' | cut -d= -f2-)
  GPU_ICD=$(echo "$GPU_LINE" | grep '^GPU_ICD=' | cut -d= -f2-)
  GPU_WRAP=$(echo "$GPU_LINE" | grep '^GPU_WRAP=' | cut -d= -f2-)

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
