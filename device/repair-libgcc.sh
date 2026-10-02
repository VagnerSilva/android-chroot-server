#!/system/bin/sh
# ============================================================
# repair-libgcc.sh — HOST Android (su), SEM wipe, SEM Termux
#
# Causa tipica: pacman -Sy gcc-libs (meta) removeu libgcc_s.so.1
# sem instalar o pacote libgcc.
#
# Fontes (ordem):
#   1) cache pacman do rootfs: libgcc-*.pkg.tar.xz|.zst
#   2) tarball Artix (armtix-dinit-*.tar.xz) — paths ./usr/lib/...
#   3) download mirror ARMtix (.pkg.tar.xz)
#
# Ferramentas: busybox KSU/Magisk (tar + xz).
# ============================================================

. /data/linux/common.sh 2>/dev/null || . "$(dirname "$0")/common.sh"

CACHE_HOST="$BASE/cache/repair-libgcc"
TERMUX_HOME=/data/data/com.termux/files/home
TMP_DIR=/data/local/tmp
TAR_NAME=armtix-dinit-20260921.tar.xz
DEFAULT_TAR="$TERMUX_HOME/$TAR_NAME"
VER_FALLBACK="16.2.1+r23+gd564253eb6c8-1"

MIRRORS="
https://armtix.artixlinux.org/repos/system/os/aarch64
https://repo.armtixlinux.org/system/os/aarch64
"

fail() { echo "!! $*" >&2; exit 1; }
log() { echo ">> $*"; }

have_libgcc() {
  [ -e "$ROOT/usr/lib/libgcc_s.so.1" ] || [ -e "$ROOT/usr/lib64/libgcc_s.so.1" ]
}

have_libstdcxx() {
  [ -e "$ROOT/usr/lib/libstdc++.so.6" ] || [ -e "$ROOT/usr/lib64/libstdc++.so.6" ]
}

pacman_ok() {
  $BB chroot "$ROOT" /usr/bin/env -i PATH=/usr/bin:/bin HOME=/root \
    /usr/bin/pacman -V >/dev/null 2>&1
}

# Extrai .pkg.tar.xz|.zst para $ROOT (so ficheiros usr/...)
extract_pkg() {
  pkg=$1
  [ -f "$pkg" ] || return 1
  log "extrair $(basename "$pkg") → $ROOT"
  case "$pkg" in
    *.pkg.tar.xz|*.tar.xz)
      $BB tar -xJf "$pkg" -C "$ROOT" \
        --exclude='.PKGINFO' --exclude='.MTREE' --exclude='.BUILDINFO' \
        --exclude='.INSTALL' --exclude='.CHANGELOG' \
        || return 1
      ;;
    *.pkg.tar.zst|*.tar.zst)
      if [ -x "$ROOT/usr/bin/zstd" ]; then
        "$ROOT/usr/bin/zstd" -dc "$pkg" 2>/dev/null | $BB tar -xf - -C "$ROOT" \
          --exclude='.PKGINFO' --exclude='.MTREE' --exclude='.BUILDINFO' \
          --exclude='.INSTALL' --exclude='.CHANGELOG' \
          || return 1
      else
        return 1
      fi
      ;;
    *)
      return 1
      ;;
  esac
  return 0
}

# 1) cache pacman no rootfs
restore_from_pacman_cache() {
  pkgdir="$ROOT/var/cache/pacman/pkg"
  [ -d "$pkgdir" ] || return 1
  hit=""
  for pat in \
    "$pkgdir"/libgcc-*.pkg.tar.xz \
    "$pkgdir"/libgcc-*.pkg.tar.zst
  do
    [ -f "$pat" ] || continue
    hit=$pat
    break
  done
  [ -n "$hit" ] || return 1
  log "cache: $hit"
  extract_pkg "$hit" || return 1
  have_libgcc
}

# 2) tarball Artix — entradas sao ./usr/lib/...
restore_from_armtix_tar() {
  tarfile=$1
  [ -f "$tarfile" ] || return 1
  log "tarball Artix: $tarfile"

  # Paths com ./ (formato do armtix-dinit) e sem ./
  if $BB tar -xJf "$tarfile" -C "$ROOT" \
      ./usr/lib/libgcc_s.so.1 ./usr/lib/libgcc_s.so \
      2>/dev/null; then
    :
  elif $BB tar -xJf "$tarfile" -C "$ROOT" \
      usr/lib/libgcc_s.so.1 usr/lib/libgcc_s.so \
      2>/dev/null; then
    :
  elif $BB unxz -c "$tarfile" 2>/dev/null | $BB tar -xf - -C "$ROOT" \
      ./usr/lib/libgcc_s.so.1 ./usr/lib/libgcc_s.so \
      2>/dev/null; then
    :
  else
    return 1
  fi
  have_libgcc
}

find_armtix_tar() {
  if [ -n "${ARMTIX_TAR:-}" ] && [ -f "$ARMTIX_TAR" ]; then
    echo "$ARMTIX_TAR"; return 0
  fi
  for cand in \
    "$TERMUX_HOME/$TAR_NAME" \
    "$TMP_DIR/$TAR_NAME" \
    "$DEFAULT_TAR"
  do
    [ -f "$cand" ] && { echo "$cand"; return 0; }
  done
  hit=$(ls -1 "$TERMUX_HOME"/armtix-dinit-*.tar.xz 2>/dev/null | sort | tail -n1) || true
  [ -n "$hit" ] && [ -f "$hit" ] && { echo "$hit"; return 0; }
  hit=$(ls -1 "$TMP_DIR"/armtix-dinit-*.tar.xz 2>/dev/null | sort | tail -n1) || true
  [ -n "$hit" ] && [ -f "$hit" ] && { echo "$hit"; return 0; }
  return 1
}

find_downloader() {
  for c in /system/bin/curl /system/bin/wget; do
    [ -x "$c" ] && { echo "$c"; return 0; }
  done
  command -v curl 2>/dev/null && return 0
  command -v wget 2>/dev/null && return 0
  return 1
}

download_to() {
  url=$1; out=$2
  dl=$(find_downloader) || return 1
  case "$dl" in
    *curl) "$dl" -fL --retry 3 --connect-timeout 20 -o "$out" "$url" ;;
    *wget) "$dl" -O "$out" "$url" ;;
    *) return 1 ;;
  esac
}

url_encode_plus() {
  printf '%s' "$1" | sed 's/+/%2B/g'
}

# 3) download .pkg.tar.xz do mirror
restore_from_mirror() {
  fn="libgcc-${VER_FALLBACK}-aarch64.pkg.tar.xz"
  enc=$(url_encode_plus "$fn")
  out="$CACHE_HOST/$fn"
  mkdir -p "$CACHE_HOST"
  for base in $MIRRORS; do
    [ -n "$base" ] || continue
    url="$base/$enc"
    log "download $url"
    if download_to "$url" "$out" && extract_pkg "$out"; then
      have_libgcc && return 0
    fi
    rm -f "$out"
  done
  return 1
}

# --- main ---
[ "$(id -u)" = 0 ] || fail "precisa root (su)"
ensure_dirs
mkdir -p "$CACHE_HOST"
mount_rootfs_rw || fail "nao montou $ROOT"

if have_libgcc && pacman_ok; then
  log "libgcc_s + pacman OK — nada a fazer"
  exit 0
fi

echo "!! causa: falta $ROOT/usr/lib/libgcc_s.so.1 (pacman nao carrega)"
log "reparar (sem wipe)"

# Ordem comprovada no device: cache xz primeiro (ja descarregado)
if ! have_libgcc; then
  restore_from_pacman_cache || true
fi
if ! have_libgcc; then
  TAR=$(find_armtix_tar) || TAR=""
  [ -n "$TAR" ] && restore_from_armtix_tar "$TAR" || true
fi
if ! have_libgcc; then
  restore_from_mirror || true
fi

$BB chroot "$ROOT" /usr/bin/env -i PATH=/usr/bin:/bin /usr/bin/ldconfig 2>/dev/null || true

have_libgcc || fail "ainda sem libgcc_s.so.1 apos repair"

if pacman_ok; then
  log "pacman -V OK"
  # alinhar pacotes oficiais se rede ok
  $BB chroot "$ROOT" /usr/bin/env -i PATH=/usr/bin:/bin HOME=/root \
    /usr/bin/pacman -Sy --noconfirm --needed libgcc libstdc++ gcc-libs 2>/dev/null || \
    log "aviso: pacman -Sy libgcc opcional falhou (lib ja no disco)"
else
  fail "libgcc_s OK mas pacman ainda falha"
fi

log "repair-libgcc OK"
ls -l "$ROOT/usr/lib/libgcc_s.so.1" 2>/dev/null || true
exit 0
