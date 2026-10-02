#!/bin/bash
# ============================================================
# install-libhybris-opt.sh — DENTRO do chroot Artix
#
# Instala libhybris pré-compilado a partir de tarball offline
# (sem makepkg/compile). Overlay em /opt/libhybris.
#
# Fontes (primeira que existir):
#   /root/libhybris-opt-arm64.tar.zst
#   /root/libhybris-opt-*.tar.zst
#
# Env:
#   HYBRIS_TAR=caminho     forçar tarball
#   HYBRIS_PREFIX=/opt/libhybris
# ============================================================
set -euo pipefail

HYBRIS_PREFIX=${HYBRIS_PREFIX:-/opt/libhybris}
MARKER=/etc/artix-libhybris.ok

fail() {
  echo "!! $*" >&2
  exit 1
}

[ "$(id -u)" -eq 0 ] || fail "execute como root"

find_tar() {
  if [ -n "${HYBRIS_TAR:-}" ] && [ -f "$HYBRIS_TAR" ]; then
    echo "$HYBRIS_TAR"
    return 0
  fi
  if [ -f /root/libhybris-opt-arm64.tar.zst ]; then
    echo /root/libhybris-opt-arm64.tar.zst
    return 0
  fi
  # shellcheck disable=SC2012
  ls -1 /root/libhybris-opt-*.tar.zst 2>/dev/null | head -n1
}

TAR=$(find_tar || true)
[ -n "$TAR" ] && [ -f "$TAR" ] || fail "tarball libhybris-opt ausente em /root/ (deps/ + run-setup-gpu-hybris)"

command -v tar >/dev/null 2>&1 || fail "tar ausente"
command -v zstd >/dev/null 2>&1 || fail "zstd ausente"

echo ">> libhybris-opt: extrair $TAR → / (overlay $HYBRIS_PREFIX)"
tar --use-compress-program=zstd -xf "$TAR" -C /

COMMON=""
for c in \
  "$HYBRIS_PREFIX/lib/libhybris-common.so" \
  "$HYBRIS_PREFIX/lib/libhybris-common.so.1" \
  "$HYBRIS_PREFIX/lib/libhybris-common.so.1.0.0" \
  "$HYBRIS_PREFIX/lib64/libhybris-common.so" \
  "$HYBRIS_PREFIX/lib64/libhybris-common.so.1"
do
  if [ -e "$c" ]; then
    COMMON=$c
    break
  fi
done
[ -n "$COMMON" ] || fail "apos extract falta libhybris-common sob $HYBRIS_PREFIX"

# Resolver symlink para o ELF real (se aplicável)
REAL=$COMMON
if [ -L "$COMMON" ]; then
  REAL=$(readlink -f "$COMMON" 2>/dev/null || true)
  [ -n "$REAL" ] && [ -f "$REAL" ] || REAL=$COMMON
fi

if command -v readelf >/dev/null 2>&1 && [ -f "$REAL" ]; then
  readelf -h "$REAL" | grep -q AArch64 || fail "libhybris-common nao e AArch64 ($REAL)"
fi

# linker path permanente
mkdir -p /etc/ld.so.conf.d
{
  printf '%s\n' "$HYBRIS_PREFIX/lib"
  [ -d "$HYBRIS_PREFIX/lib64" ] && printf '%s\n' "$HYBRIS_PREFIX/lib64"
  [ -d "$HYBRIS_PREFIX/lib/libhybris" ] && printf '%s\n' "$HYBRIS_PREFIX/lib/libhybris"
} > /etc/ld.so.conf.d/libhybris-opt.conf
ldconfig 2>/dev/null || true

printf 'HYBRIS_PREFIX=%s\nHYBRIS_TAR=%s\nHYBRIS_COMMON=%s\n' \
  "$HYBRIS_PREFIX" "$(basename "$TAR")" "$COMMON" > "$MARKER"
chmod 644 "$MARKER"

echo ">> libhybris-opt OK: $COMMON (marker $MARKER)"
