#!/system/bin/sh
# ============================================================
# run-setup-xfce.sh — copia setup-xfce.sh para o rootfs e executa
#
# Env (passadas ao chroot):
#   ARTIX_USER X11_DISPLAY
#
# Ex.:
#   ARTIX_USER=alice /data/linux/run-setup-xfce.sh
# ============================================================

. /data/linux/common.sh 2>/dev/null || . "$(dirname "$0")/common.sh"

SETUP_SRC=/data/linux/setup-xfce.sh
[ -f "$SETUP_SRC" ] || SETUP_SRC="$(dirname "$0")/setup-xfce.sh"

if [ ! -f "$SETUP_SRC" ]; then
  echo "!! setup-xfce.sh nao encontrado"
  exit 1
fi

mount_rootfs_rw || exit 1
cp "$SETUP_SRC" "$ROOT/root/setup-xfce.sh"
chmod 755 "$ROOT/root/setup-xfce.sh"
strip_crlf "$ROOT/root/setup-xfce.sh"

# mesa25 offline + instalador → /root no chroot
DEPS_DIR=/data/linux/deps
[ -d "$DEPS_DIR" ] || DEPS_DIR="$(dirname "$0")/deps"
mkdir -p "$ROOT/root"
if [ -f /data/linux/install-mesa25-android-mali.sh ]; then
  cp /data/linux/install-mesa25-android-mali.sh "$ROOT/root/install-mesa25-android-mali.sh"
  chmod 755 "$ROOT/root/install-mesa25-android-mali.sh"
  strip_crlf "$ROOT/root/install-mesa25-android-mali.sh"
fi
if [ -f "$DEPS_DIR/mesa25-android-mali-25.1.2-arm64.tar.zst" ]; then
  echo ">> deps: mesa25-android-mali-25.1.2-arm64.tar.zst → $ROOT/root/"
  cp "$DEPS_DIR/mesa25-android-mali-25.1.2-arm64.tar.zst" \
    "$ROOT/root/mesa25-android-mali-25.1.2-arm64.tar.zst"
elif ls "$DEPS_DIR"/mesa25-android-mali-*.tar.zst >/dev/null 2>&1; then
  _mt=$(ls -1 "$DEPS_DIR"/mesa25-android-mali-*.tar.zst | head -n1)
  echo ">> deps: $(basename "$_mt") → $ROOT/root/"
  cp "$_mt" "$ROOT/root/$(basename "$_mt")"
else
  echo "!! deps/mesa25-android-mali-*.tar.zst ausente — prepare.sh / deploy deps/"
  exit 1
fi

# tambem instalar wrapper host→chroot se existir
if [ -f /data/linux/xfce-x11-session.sh ]; then
  cp /data/linux/xfce-x11-session.sh "$ROOT/usr/local/bin/xfce-x11-session.sh"
  chmod 755 "$ROOT/usr/local/bin/xfce-x11-session.sh"
  strip_crlf "$ROOT/usr/local/bin/xfce-x11-session.sh"
  chmod 755 "$ROOT/usr/local/bin/xfce-x11-session.sh"
fi
FIT_SRC=/data/linux/xfce-fit-windows.sh
[ -f "$FIT_SRC" ] || FIT_SRC="$(dirname "$0")/xfce-fit-windows.sh"
if [ -f "$FIT_SRC" ]; then
  mkdir -p "$ROOT/usr/local/bin" "$ROOT/root"
  cp "$FIT_SRC" "$ROOT/usr/local/bin/xfce-fit-windows.sh"
  cp "$FIT_SRC" "$ROOT/root/xfce-fit-windows.sh"
  chmod 755 "$ROOT/usr/local/bin/xfce-fit-windows.sh" "$ROOT/root/xfce-fit-windows.sh"
  strip_crlf "$ROOT/usr/local/bin/xfce-fit-windows.sh"
  strip_crlf "$ROOT/root/xfce-fit-windows.sh"
  chmod 755 "$ROOT/usr/local/bin/xfce-fit-windows.sh" "$ROOT/root/xfce-fit-windows.sh"
fi

ENV_PREFIX=""
[ -n "${ARTIX_USER:-}" ] && ENV_PREFIX="$ENV_PREFIX ARTIX_USER='$ARTIX_USER'"
[ -n "${X11_DISPLAY:-}" ] && ENV_PREFIX="$ENV_PREFIX X11_DISPLAY='$X11_DISPLAY'"

export SHELL_CMD="$ENV_PREFIX /bin/sh /root/setup-xfce.sh"
exec /data/linux/linux-shell.sh
