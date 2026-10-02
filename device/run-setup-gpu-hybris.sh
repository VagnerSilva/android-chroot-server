#!/system/bin/sh
# ============================================================
# run-setup-gpu-hybris.sh — host: binds extract + setup
# GLES-first via libhybris-opt + /opt/android-mali (runtime-only).
#
# Ordem:
#   1) linux-start (binds /mnt/system /mnt/vendor /mnt/apex para copia)
#   2) check pacman -V (sem recovery automatico)
#   3) copiar deps offline (mesa25, libhybris-opt, libc; sysvk-opt opcional)
#   4) setup-gpu-hybris no chroot
# Rootfs com pacman partido (libgcc): /data/linux/repair-libgcc.sh (sem wipe)
# ============================================================

. /data/linux/common.sh 2>/dev/null || . "$(dirname "$0")/common.sh"

SETUP_SRC=/data/linux/setup-gpu-hybris.sh
[ -f "$SETUP_SRC" ] || SETUP_SRC="$(dirname "$0")/setup-gpu-hybris.sh"

if [ ! -f "$SETUP_SRC" ]; then
  echo "!! setup-gpu-hybris.sh nao encontrado — corre prepare.sh"
  exit 1
fi

if [ ! -f "$PIDF" ] || ! container_vivo "$(cat "$PIDF")"; then
  echo "!! container parado — /data/linux/linux-start.sh primeiro"
  exit 1
fi

mount_rootfs_rw || exit 1
cp "$SETUP_SRC" "$ROOT/root/setup-gpu-hybris.sh"
chmod 755 "$ROOT/root/setup-gpu-hybris.sh"
strip_crlf "$ROOT/root/setup-gpu-hybris.sh"

# pacman vivo — mostrar causa real; repair sem wipe
if ! $BB chroot "$ROOT" /usr/bin/env -i PATH=/usr/bin:/bin HOME=/root \
  /usr/bin/pacman -V >/dev/null 2>&1; then
  echo "!! pacman nao funciona no chroot"
  $BB chroot "$ROOT" /usr/bin/env -i PATH=/usr/bin:/bin HOME=/root \
    /usr/bin/pacman -V 2>&1 | head -n 5 || true
  if [ ! -e "$ROOT/usr/lib/libgcc_s.so.1" ] && [ ! -e "$ROOT/usr/lib64/libgcc_s.so.1" ]; then
    echo "!! causa: falta $ROOT/usr/lib/libgcc_s.so.1"
  fi
  echo ">> a tentar repair-libgcc (sem wipe)"
  REPAIR=/data/linux/repair-libgcc.sh
  [ -f "$REPAIR" ] || REPAIR="$(dirname "$0")/repair-libgcc.sh"
  if [ -f "$REPAIR" ]; then
    sh "$REPAIR" || {
      echo "!! repair-libgcc falhou"
      exit 1
    }
  else
    echo "!! repair-libgcc.sh ausente — prepare.sh incompleto"
    exit 1
  fi
  if ! $BB chroot "$ROOT" /usr/bin/env -i PATH=/usr/bin:/bin HOME=/root \
    /usr/bin/pacman -V >/dev/null 2>&1; then
    echo "!! pacman ainda falha apos repair"
    exit 1
  fi
  echo ">> pacman OK apos repair-libgcc"
fi

PID=$(cat "$PIDF")
NSARGS=$(nsenter_ns_args "$PID")

# Mounts temporarios para EXTRAÇÃO (/opt/android-mali) — nao requisito runtime
ensure_bind() {
  SRC="$1"
  DST="$2"
  [ -d "$SRC" ] || return 0
  mkdir -p "$DST"
  # shellcheck disable=SC2086
  if $BB nsenter $NSARGS -- $BB mountpoint -q "$DST" 2>/dev/null; then
    return 0
  fi
  echo ">> bind (extract) $SRC -> $DST"
  # shellcheck disable=SC2086
  $BB nsenter $NSARGS -- $BB mount --bind "$SRC" "$DST" 2>/dev/null || true
}

# Preferir /mnt/* (isolamento runtime usa /opt/android-mali)
ensure_bind /vendor "$ROOT/mnt/vendor"
ensure_bind /system "$ROOT/mnt/system"
# /system_ext: extract (GLES/HAL deps que vivem la); runtime usa /opt/android-mali
ensure_bind /system_ext "$ROOT/mnt/system_ext"
mkdir -p "$ROOT/mnt/apex"
# shellcheck disable=SC2086
if [ -d /apex ] && ! $BB nsenter $NSARGS -- $BB mountpoint -q "$ROOT/mnt/apex" 2>/dev/null; then
  echo ">> rbind /apex -> mnt/apex (extract)"
  # shellcheck disable=SC2086
  $BB nsenter $NSARGS -- $BB mount --rbind /apex "$ROOT/mnt/apex" 2>/dev/null \
    || $BB nsenter $NSARGS -- $BB mount --bind /apex "$ROOT/mnt/apex" 2>/dev/null \
    || true
fi
# Compat: binds na raiz so se ainda nao houver /opt/android-mali (setup antigo)
if [ ! -d "$ROOT/opt/android-mali/vendor/lib64" ]; then
  ensure_bind /vendor "$ROOT/vendor"
  ensure_bind /system "$ROOT/system"
fi

# deps offline: /data/linux/deps/ → $ROOT/root/ (chroot pode ser wipeado)
DEPS_DIR=/data/linux/deps
[ -d "$DEPS_DIR" ] || DEPS_DIR="$(dirname "$0")/deps"
mkdir -p "$ROOT/root"

copy_dep() {
  _src=$1
  _dstname=$2
  if [ -f "$_src" ]; then
    echo ">> deps: $_dstname → $ROOT/root/"
    cp "$_src" "$ROOT/root/$_dstname"
    return 0
  fi
  return 1
}

# instaladores
for _inst in install-mesa25-android-mali.sh install-libhybris-opt.sh install-sysvk-opt.sh; do
  if [ -f "/data/linux/$_inst" ]; then
    echo ">> deps: $_inst → $ROOT/root/"
    cp "/data/linux/$_inst" "$ROOT/root/$_inst"
    chmod 755 "$ROOT/root/$_inst"
    strip_crlf "$ROOT/root/$_inst"
  fi
done

copy_dep "$DEPS_DIR/libc-hybris.so" "libc-hybris.so" || \
  echo " -- deps/libc-hybris.so ausente (setup tenta curl fallback)"

# mesa25 obrigatorio
if [ -f "$DEPS_DIR/mesa25-android-mali-25.1.2-arm64.tar.zst" ]; then
  copy_dep "$DEPS_DIR/mesa25-android-mali-25.1.2-arm64.tar.zst" \
    "mesa25-android-mali-25.1.2-arm64.tar.zst" || true
elif ls "$DEPS_DIR"/mesa25-android-mali-*.tar.zst >/dev/null 2>&1; then
  _mt=$(ls -1 "$DEPS_DIR"/mesa25-android-mali-*.tar.zst | head -n1)
  copy_dep "$_mt" "$(basename "$_mt")" || true
else
  echo "!! deps/mesa25-android-mali-*.tar.zst ausente"
  exit 1
fi

# libhybris-opt obrigatorio (runtime-only — sem compile)
if [ -f "$DEPS_DIR/libhybris-opt-arm64.tar.zst" ]; then
  copy_dep "$DEPS_DIR/libhybris-opt-arm64.tar.zst" "libhybris-opt-arm64.tar.zst" || true
elif ls "$DEPS_DIR"/libhybris-opt-*.tar.zst >/dev/null 2>&1; then
  _ht=$(ls -1 "$DEPS_DIR"/libhybris-opt-*.tar.zst | head -n1)
  copy_dep "$_ht" "$(basename "$_ht")" || true
else
  echo "!! deps/libhybris-opt-arm64.tar.zst ausente — obrigatorio (sem makepkg no device)"
  echo "   coloque o tarball com /opt/libhybris/... em /data/linux/deps/"
  exit 1
fi

if [ ! -f "$ROOT/root/install-libhybris-opt.sh" ]; then
  echo "!! install-libhybris-opt.sh ausente — prepare.sh incompleto"
  exit 1
fi

# sysvk-opt opcional (Vulkan Fase F)
if [ -f "$DEPS_DIR/sysvk-opt-arm64.tar.zst" ]; then
  copy_dep "$DEPS_DIR/sysvk-opt-arm64.tar.zst" "sysvk-opt-arm64.tar.zst" || true
elif ls "$DEPS_DIR"/sysvk-opt-*.tar.zst >/dev/null 2>&1; then
  _st=$(ls -1 "$DEPS_DIR"/sysvk-opt-*.tar.zst | head -n1)
  copy_dep "$_st" "$(basename "$_st")" || true
else
  echo " -- deps/sysvk-opt-*.tar.zst ausente (Vulkan adiado apos GLES)"
fi

# bash obrigatorio (set -Eeuo, [[ ]], trap ERR)
# DISPLAY para Fase G (Zink glxinfo) — linux-shell propaga se definido
export DISPLAY="${DISPLAY:-:0}"
export SHELL_CMD="/bin/bash /root/setup-gpu-hybris.sh"
exec /data/linux/linux-shell.sh
