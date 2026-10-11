#!/system/bin/sh
# check-gpu.sh — diagnóstico de GPU Mali/GLES/Vulkan no chroot

. /data/linux/common.sh 2>/dev/null || . "$(dirname "$0")/common.sh"

if [ ! -f "$PIDF" ] || ! container_vivo "$(cat "$PIDF" 2>/dev/null || printf '')"; then
  echo "GPU_STATUS=unknown"
  echo "GPU_DRIVER=container parado"
  exit 0
fi

run_in_chroot /bin/sh -c '
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
'
