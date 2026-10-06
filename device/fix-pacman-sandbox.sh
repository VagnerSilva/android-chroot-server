#!/system/bin/sh
# ============================================================
# fix-pacman-sandbox.sh
# Host Android (su): aplica DisableSandbox no pacman.conf do chroot.
# ============================================================
set -e

. /data/linux/common.sh 2>/dev/null || . "$(dirname "$0")/common.sh"

SRC=/data/linux/android-pacman-sandbox.sh
[ -f "$SRC" ] || SRC="$(dirname "$0")/android-pacman-sandbox.sh"
[ -f "$SRC" ] || SRC=/data/local/tmp/android-pacman-sandbox.sh

if [ ! -f "$SRC" ]; then
  echo "!! android-pacman-sandbox.sh nao encontrado — corre prepare.sh"
  exit 1
fi

if [ ! -f "$PIDF" ] || ! container_vivo "$(cat "$PIDF")"; then
  echo "!! container parado — /data/linux/linux-start.sh"
  exit 1
fi

PID=$(cat "$PIDF")
NSARGS=$(nsenter_ns_args "$PID")

mkdir -p "$ROOT/usr/local/sbin" "$ROOT/etc/pacman.d/hooks"
cp "$SRC" "$ROOT/usr/local/sbin/android-pacman-sandbox.sh"
strip_crlf "$ROOT/usr/local/sbin/android-pacman-sandbox.sh"
chmod 755 "$ROOT/usr/local/sbin/android-pacman-sandbox.sh"

# shellcheck disable=SC2086
$BB nsenter $NSARGS -- \
  $BB chroot "$ROOT" /usr/bin/env -i \
    PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
    HOME=/root LANG=C.UTF-8 \
    /bin/sh /usr/local/sbin/android-pacman-sandbox.sh

echo ">> sandbox pacman aplicado no chroot"
