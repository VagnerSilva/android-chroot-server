#!/system/bin/sh
# ============================================================
# run-setup-gpu-mediatek.sh — copia setup-gpu-mediatek.sh e corre
# ============================================================

. /data/linux/common.sh 2>/dev/null || . "$(dirname "$0")/common.sh"

SETUP_SRC=/data/linux/setup-gpu-mediatek.sh
[ -f "$SETUP_SRC" ] || SETUP_SRC="$(dirname "$0")/setup-gpu-mediatek.sh"

if [ ! -f "$SETUP_SRC" ]; then
  echo "!! setup-gpu-mediatek.sh nao encontrado"
  exit 1
fi

mount_rootfs_rw || exit 1
cp "$SETUP_SRC" "$ROOT/root/setup-gpu-mediatek.sh"
chmod 755 "$ROOT/root/setup-gpu-mediatek.sh"
strip_crlf "$ROOT/root/setup-gpu-mediatek.sh"

# garantir binds vendor/system se o container ja estiver vivo
if [ -f "$PIDF" ] && container_vivo "$(cat "$PIDF")"; then
  PID=$(cat "$PIDF")
  NSARGS=$(nsenter_ns_args "$PID")
  for pair in "/vendor:$ROOT/mnt/vendor" "/system:$ROOT/mnt/system"; do
    SRC=${pair%%:*}
    DST=${pair#*:}
    [ -d "$SRC" ] || continue
    mkdir -p "$DST"
    # shellcheck disable=SC2086
    if ! $BB nsenter $NSARGS -- $BB mountpoint -q "$DST" 2>/dev/null; then
      echo ">> bind $SRC -> $DST"
      # shellcheck disable=SC2086
      $BB nsenter $NSARGS -- $BB mount --bind "$SRC" "$DST" 2>/dev/null || \
        $BB mount --bind "$SRC" "$DST" 2>/dev/null || true
      # remount ro se possivel
      # shellcheck disable=SC2086
      $BB nsenter $NSARGS -- $BB mount -o remount,ro,bind "$DST" 2>/dev/null || true
    fi
  done
else
  # chroot temp: bind agora para o setup ver as libs
  mkdir -p "$ROOT/mnt/vendor" "$ROOT/mnt/system"
  [ -d /vendor ] && $BB mount --bind /vendor "$ROOT/mnt/vendor" 2>/dev/null || true
  [ -d /system ] && $BB mount --bind /system "$ROOT/mnt/system" 2>/dev/null || true
fi

export SHELL_CMD="/bin/sh /root/setup-gpu-mediatek.sh"
exec /data/linux/linux-shell.sh
