#!/bin/bash
# ============================================================
# install-sysvk-opt.sh — DENTRO do chroot Artix
#
# Instala sysvk + WSI pré-compilados a partir de tarball offline
# (sem makepkg). Opcional — so corre se o tarball existir.
#
# Fontes:
#   /root/sysvk-opt-arm64.tar.zst
#   /root/sysvk-opt-*.tar.zst
#
# Env:
#   SYSVK_TAR=caminho
# ============================================================
set -euo pipefail

MARKER=/etc/artix-sysvk.ok

fail() {
  echo "!! $*" >&2
  exit 1
}

[ "$(id -u)" -eq 0 ] || fail "execute como root"

find_tar() {
  if [ -n "${SYSVK_TAR:-}" ] && [ -f "$SYSVK_TAR" ]; then
    echo "$SYSVK_TAR"
    return 0
  fi
  if [ -f /root/sysvk-opt-arm64.tar.zst ]; then
    echo /root/sysvk-opt-arm64.tar.zst
    return 0
  fi
  # shellcheck disable=SC2012
  ls -1 /root/sysvk-opt-*.tar.zst 2>/dev/null | head -n1
}

TAR=$(find_tar || true)
[ -n "$TAR" ] && [ -f "$TAR" ] || fail "tarball sysvk-opt ausente em /root/"

command -v tar >/dev/null 2>&1 || fail "tar ausente"
command -v zstd >/dev/null 2>&1 || fail "zstd ausente"

echo ">> sysvk-opt: extrair $TAR → /"
tar --use-compress-program=zstd -xf "$TAR" -C /
ldconfig 2>/dev/null || true

ICD_FILE=""
for j in \
  /usr/share/vulkan/icd.d/*.json \
  /usr/local/share/vulkan/icd.d/*.json \
  /opt/libhybris/share/vulkan/icd.d/*.json
do
  [ -f "$j" ] || continue
  if grep -qiE 'sysvk|android|wrapper|mali' "$j"; then
    ICD_FILE=$j
    break
  fi
done
[ -n "$ICD_FILE" ] || fail "apos extract: ICD sysvk/android nao encontrado"

WSI_OK=0
for j in \
  /usr/share/vulkan/explicit_layer.d/VkLayer_window_system_integration.json \
  /usr/share/vulkan/implicit_layer.d/VkLayer_window_system_integration.json
do
  [ -f "$j" ] && WSI_OK=1 && break
done
[ "$WSI_OK" = 1 ] || echo "!! aviso: JSON WSI layer ausente apos extract (verifique tarball)"

printf 'SYSVK_TAR=%s\nICD_FILE=%s\n' "$(basename "$TAR")" "$ICD_FILE" > "$MARKER"
chmod 644 "$MARKER"

echo ">> sysvk-opt OK: ICD=$ICD_FILE (marker $MARKER)"
