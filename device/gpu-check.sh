#!/system/bin/sh
# ============================================================
# gpu-check.sh — GPU Mali GLES-first (+ Vulkan opcional)
#
# PASS precoce: /etc/artix-gpu-gles.ok + renderer Mali via gpu-egl-run
# PASS completo: + /etc/artix-gpu-hybris.ok + Vulkan Mali
# FAIL: llvmpipe / sem mali0 / sem arvore /opt/android-mali
# ============================================================

. /data/linux/common.sh 2>/dev/null || . "$(dirname "$0")/common.sh" 2>/dev/null || true

run_in() {
  if [ -n "${PIDF:-}" ] && [ -f "$PIDF" ] && container_vivo "$(cat "$PIDF")" 2>/dev/null; then
    PID=$(cat "$PIDF")
    NSARGS=$(nsenter_ns_args "$PID")
    # shellcheck disable=SC2086
    $BB nsenter $NSARGS -- $BB chroot "$ROOT" /usr/bin/env -i \
      PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
      HOME=/root TERM=linux LANG=C.UTF-8 DISPLAY="${DISPLAY:-:0}" \
      XDG_RUNTIME_DIR=/tmp TMPDIR=/tmp \
      /bin/sh -c "$1"
  else
    /bin/sh -c "$1"
  fi
}

echo "=== gpu-check Mali (GLES-first) ==="

echo
echo "-- kernel / devices --"
run_in '
  echo "arch: $(uname -m)"
  ls -la /dev/mali0 /dev/dri/card0 2>/dev/null || true
  [ -d /sys/bus/platform/drivers/mali ] && echo "mali driver: ok" || echo "mali driver: ausente"
  if ls /sys/class/drm/renderD* >/dev/null 2>&1; then
    echo "render nodes: $(ls /sys/class/drm/renderD* 2>/dev/null | tr "\n" " ")"
  else
    echo "render nodes: ausentes (esperado — sem Panfrost/renderD128)"
  fi
  true
'

echo
echo "-- isolation / markers --"
run_in '
  [ -f /etc/artix-gpu-gles.ok ] && echo "GLES marker: OK" && cat /etc/artix-gpu-gles.ok || echo "GLES marker: ausente"
  [ -f /etc/artix-gpu-hybris.ok ] && echo "Vulkan marker: OK" || echo "Vulkan marker: ausente"
  [ -d /opt/android-mali/vendor/lib64 ] && echo "android-mali: OK" || echo "android-mali: ausente"
  [ -d /opt/libhybris ] && echo "libhybris prefix: OK" || echo "libhybris prefix: ausente/alt"
  [ -x /usr/local/bin/gpu-egl-run ] && echo "gpu-egl-run: OK" || echo "gpu-egl-run: ausente"
  cat /etc/artix-gpu.conf 2>/dev/null || true
  true
'

MALI_DEV=0
run_in 'test -e /dev/mali0' && MALI_DEV=1 || true

GLES_MARK=0
run_in 'test -f /etc/artix-gpu-gles.ok' && GLES_MARK=1 || true

VK_MARK=0
run_in 'test -f /etc/artix-gpu-hybris.ok' && VK_MARK=1 || true

TREE=0
run_in 'test -d /opt/android-mali/vendor/lib64' && TREE=1 || true

echo
echo "-- GLES (gpu-egl-run) --"
GLES_OUT=$(run_in '
  if [ -x /tmp/mali-egl-test ]; then
    gpu-egl-run /tmp/mali-egl-test 2>&1
  elif command -v eglinfo >/dev/null 2>&1; then
    gpu-egl-run eglinfo 2>&1 | head -n 40
  else
    echo "NO_TEST_BIN"
  fi
' || true)
echo "$GLES_OUT"

GLES_OK=0
GLES_NAME=""
if echo "$GLES_OUT" | grep -qiE 'MALI_OK|Mali-G[0-9]+|RENDERER=.*Mali'; then
  GLES_OK=1
  GLES_NAME=$(echo "$GLES_OUT" | grep -oE 'Mali-G[0-9]+[^[:space:]]*' | head -n1)
  [ -n "$GLES_NAME" ] || GLES_NAME=$(echo "$GLES_OUT" | grep '^RENDERER=' | head -n1 | cut -d= -f2-)
  [ -n "$GLES_NAME" ] || GLES_NAME="Mali (gles)"
fi
echo "$GLES_OUT" | grep -qiE 'llvmpipe|softpipe|swrast' && GLES_OK=0

echo
echo "-- Vulkan (opcional; apos GLES) --"
VK_OUT=""
VK_OK=0
VK_NAME=""
if [ "$VK_MARK" = 1 ] || [ "$GLES_MARK" = 1 ]; then
  VK_OUT=$(run_in '
    export HYBRIS_TLS_PATCH=vulkan.mali.so
    if command -v gpu-vulkan-run >/dev/null && command -v vulkaninfo >/dev/null; then
      gpu-vulkan-run vulkaninfo --summary 2>&1 | head -n 50
    else
      echo "NO_VULKAN_WRAP"
    fi
  ' || true)
  echo "$VK_OUT"
  if echo "$VK_OUT" | grep -qiE 'Mali-G[0-9]+|deviceName.*Mali|physicalDevices: count = [1-9]'; then
    VK_OK=1
    VK_NAME=$(echo "$VK_OUT" | grep -oE 'Mali-G[0-9]+[^[:space:]]*' | head -n1)
    [ -n "$VK_NAME" ] || VK_NAME="Mali (hybris)"
  fi
fi

echo
echo "mali0:     $MALI_DEV"
echo "tree:      $TREE"
echo "gles.ok:   $GLES_MARK  renderer=${GLES_NAME:-n/a}"
echo "hybris.ok: $VK_MARK  vulkan=${VK_NAME:-n/a}"

if [ "$MALI_DEV" != 1 ]; then
  echo "FAIL — /dev/mali0 ausente"
  exit 1
fi

if [ "$GLES_MARK" = 1 ] && [ "$GLES_OK" = 1 ]; then
  if [ "$VK_OK" = 1 ]; then
    echo "PASS — GLES Mali ($GLES_NAME) + Vulkan ($VK_NAME)"
    exit 0
  fi
  echo "PASS — GLES Mali ($GLES_NAME)  [Vulkan ainda nao / opcional]"
  echo "  seguinte: deps/sysvk-opt-arm64.tar.zst + /data/linux/run-setup-gpu-hybris.sh"
  echo "           depois: DISPLAY=:0 gpu-vulkan-run vkcube"
  exit 0
fi

if [ "$GLES_MARK" = 1 ] && [ "$GLES_OK" != 1 ]; then
  echo "FAIL — artix-gpu-gles.ok existe mas teste GLES nao confirma Mali"
  exit 1
fi

if [ "$TREE" != 1 ]; then
  echo "FAIL — /opt/android-mali ausente"
  echo "  correcao: /data/linux/run-setup-gpu-hybris.sh"
  exit 1
fi

echo "FAIL — GLES Mali nao activo"
echo "  1) /data/linux/linux-start.sh"
echo "  2) /data/linux/run-setup-gpu-hybris.sh"
echo "  se pacman partido: YES=1 /data/linux/wipe-chroot.sh && /data/linux/bootstrap.sh"
echo "  NAO use run-setup-gpu-mediatek.sh (LEGACY)"
exit 1
