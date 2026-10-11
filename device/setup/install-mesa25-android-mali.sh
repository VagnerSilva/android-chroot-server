#!/bin/bash
# ============================================================
# install-mesa25-android-mali.sh — DENTRO do chroot Artix
#
# Instala Mesa 25.1.2 (overlay) em /opt/android-mali a partir do
# tarball offline — evita Mesa >=26 (free(): invalid size / pointer
# com softGL e Zink+hybris).
#
# Fontes (primeira que existir):
#   /root/mesa25-android-mali-25.1.2-arm64.tar.zst
#   /root/mesa25-android-mali-*.tar.zst
#
# Env:
#   MESA25_TAR=caminho   forçar tarball
#   MESA25_KEEP_SYSTEM=1 nao remover pacote pacman mesa>=26
# ============================================================
set -euo pipefail

ANDROID_MALI=${ANDROID_MALI:-/opt/android-mali}
MARKER=/etc/artix-mesa25.ok
MESA25_VER=25.1.2

fail() {
  echo "!! $*" >&2
  exit 1
}

[ "$(id -u)" -eq 0 ] || fail "execute como root"

find_tar() {
  if [ -n "${MESA25_TAR:-}" ] && [ -f "$MESA25_TAR" ]; then
    echo "$MESA25_TAR"
    return 0
  fi
  if [ -f /root/mesa25-android-mali-25.1.2-arm64.tar.zst ]; then
    echo /root/mesa25-android-mali-25.1.2-arm64.tar.zst
    return 0
  fi
  # shellcheck disable=SC2012
  ls -1 /root/mesa25-android-mali-*.tar.zst 2>/dev/null | head -n1
}

TAR=$(find_tar || true)
[ -n "$TAR" ] && [ -f "$TAR" ] || fail "tarball mesa25 ausente em /root/ (prepare deps/ + run-setup)"

command -v tar >/dev/null 2>&1 || fail "tar ausente"
command -v zstd >/dev/null 2>&1 || fail "zstd ausente"

echo ">> mesa25: extrair $TAR → / (overlay $ANDROID_MALI)"
tar --use-compress-program=zstd -xf "$TAR" -C /

GALLIUM="$ANDROID_MALI/lib/libgallium-${MESA25_VER}.so"
[ -f "$GALLIUM" ] || fail "apos extract falta $GALLIUM"
command -v readelf >/dev/null 2>&1 && \
  readelf -h "$GALLIUM" | grep -q AArch64 || \
  fail "libgallium nao e AArch64"

# Mesa megadriver: zink_dri.so → libdril_dri.so (igual swrast)
DRI_DIR="$ANDROID_MALI/lib/dri"
if [ -f "$DRI_DIR/libdril_dri.so" ]; then
  ln -sfn libdril_dri.so "$DRI_DIR/zink_dri.so"
  echo ">> dri: zink_dri.so → libdril_dri.so"
else
  echo "!! aviso: $DRI_DIR/libdril_dri.so ausente — Zink pode falhar"
fi

# Termux:X11 precisa de kopper real (nao kopper_stubs). Overlay actual
# tipicamente tem stubs (~8B) — Zink fica adiado ate rebuild.
if command -v readelf >/dev/null 2>&1; then
  set +o pipefail
  KOPPER_SZ=$(readelf -Ws "$GALLIUM" 2>/dev/null \
    | awk '/[[:space:]]kopper_init_screen([[:space:]]|$)/ { print $3; exit }')
  set -o pipefail
  if [ -n "$KOPPER_SZ" ] && [ "$KOPPER_SZ" -lt 32 ] 2>/dev/null; then
    echo "!! aviso: $GALLIUM tem kopper_stubs (kopper_init_screen=${KOPPER_SZ}B)"
    echo "   Zink em Termux:X11 requer rebuild mesa25 com kopper/WSI GLX"
  else
    echo ">> kopper_init_screen size=${KOPPER_SZ:-?} (ok se >=32)"
  fi
fi

# linker path permanente (softGL / glvnd mesa opt)
mkdir -p /etc/ld.so.conf.d
printf '%s\n' "$ANDROID_MALI/lib" > /etc/ld.so.conf.d/android-mali-mesa25.conf
ldconfig 2>/dev/null || true

# env tipico para softGL (XFCE) — hybris/gpu-egl-run NAO devem depender disto
cat > /etc/profile.d/mesa25-android-mali.sh <<EOF
# Mesa ${MESA25_VER} sob /opt/android-mali (evita Mesa >=26)
export MESA25_PREFIX="${ANDROID_MALI}"
# SoftGL: preferir gallium/EGL/GLX do overlay
case ":\${LD_LIBRARY_PATH:-}:" in
  *:${ANDROID_MALI}/lib:*) ;;
  *) export LD_LIBRARY_PATH="${ANDROID_MALI}/lib\${LD_LIBRARY_PATH:+:\$LD_LIBRARY_PATH}" ;;
esac
export LIBGL_DRIVERS_PATH="${ANDROID_MALI}/lib/dri"
export GBM_BACKENDS_PATH="${ANDROID_MALI}/lib/gbm"
export __EGL_VENDOR_LIBRARY_DIRS="${ANDROID_MALI}/share/glvnd/egl_vendor.d"
EOF
chmod 644 /etc/profile.d/mesa25-android-mali.sh

# Remover Mesa >=26 do pacman (free(): invalid pointer conhecido)
if [ "${MESA25_KEEP_SYSTEM:-0}" != 1 ] && command -v pacman >/dev/null 2>&1; then
  if pacman -Qi mesa >/dev/null 2>&1; then
    VER=$(pacman -Qi mesa 2>/dev/null | awk -F': ' '/^Version/{print $2; exit}')
    echo ">> mesa pacman instalado: $VER"
    case "$VER" in
      *26.*|*27.*|*28.*)
        echo ">> a remover mesa>=26 (Rdd) — runtime = overlay ${MESA25_VER}"
        pacman -Rdd --noconfirm mesa 2>/dev/null || \
          echo "!! aviso: nao foi possivel remover mesa ($VER) — overlay prevalece via LD path"
        ;;
      *)
        echo ">> mesa pacman $VER <26 — manter (overlay continua prioritario via LD path)"
        ;;
    esac
  else
    echo ">> mesa pacman ausente — so overlay ${MESA25_VER}"
  fi
fi

printf 'MESA25_VERSION=%s\nMESA25_PREFIX=%s\nMESA25_TAR=%s\n' \
  "$MESA25_VER" "$ANDROID_MALI" "$(basename "$TAR")" > "$MARKER"
chmod 644 "$MARKER"

echo ">> mesa25 OK: $GALLIUM (marker $MARKER)"
