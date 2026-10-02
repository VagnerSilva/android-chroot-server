#!/system/bin/sh
# ============================================================
# install-direnv.sh
# Prefere pacote Arch Linux ARM [extra] (aarch64).
# Fallback: binario GitHub linux-arm64.
#
# su -c /data/linux/install-direnv.sh
# ============================================================
set -e

. /data/linux/common.sh 2>/dev/null || . "$(dirname "$0")/common.sh"

if [ ! -f "$PIDF" ] || ! container_vivo "$(cat "$PIDF")"; then
  echo "!! container parado"
  exit 1
fi

PID=$(cat "$PIDF")
NSARGS=$(nsenter_ns_args "$PID")

# garantir ALARM se ainda nao estiver
if ! grep -q '^# BEGIN Arch Linux ARM' "$ROOT/etc/pacman.conf" 2>/dev/null; then
  echo ">> a ativar Arch Linux ARM..."
  if [ -x /data/linux/enable-archlinuxarm.sh ]; then
    /data/linux/enable-archlinuxarm.sh
  elif [ -x "$(dirname "$0")/enable-archlinuxarm.sh" ]; then
    "$(dirname "$0")/enable-archlinuxarm.sh"
  else
    echo "!! falta enable-archlinuxarm.sh"
    exit 1
  fi
fi

echo ">> pacman -S direnv (ALARM extra)"
# shellcheck disable=SC2086
if $BB nsenter $NSARGS -- \
  $BB chroot "$ROOT" /usr/bin/env -i \
    PATH=/usr/bin:/bin:/usr/sbin:/sbin HOME=/root \
    pacman -S --noconfirm --needed direnv; then
  # shellcheck disable=SC2086
  $BB nsenter $NSARGS -- $BB chroot "$ROOT" /usr/bin/env -i \
    PATH=/usr/local/bin:/usr/bin:/bin \
    /bin/sh -c 'command -v direnv; direnv version'
  echo ">> direnv via pacman OK"
  echo "Ativar (user): echo 'eval \"\$(direnv hook bash)\"' >> ~/.bashrc"
  exit 0
fi

echo "!! pacman falhou — fallback GitHub arm64"
VER="${DIRENV_VERSION:-v2.37.1}"
URL="https://github.com/direnv/direnv/releases/download/${VER}/direnv.linux-arm64"
# shellcheck disable=SC2086
$BB nsenter $NSARGS -- $BB chroot "$ROOT" /usr/bin/curl -fsSL --max-time 120 \
  -o /tmp/direnv.linux-arm64 "$URL"
# shellcheck disable=SC2086
$BB nsenter $NSARGS -- $BB chroot "$ROOT" /usr/bin/env -i \
  PATH=/usr/bin:/bin HOME=/root /bin/sh -c '
    /bin/mkdir -p /usr/local/bin
    /bin/cp -f /tmp/direnv.linux-arm64 /usr/local/bin/direnv
    /bin/chmod 755 /usr/local/bin/direnv
    /bin/rm -f /tmp/direnv.linux-arm64
    /usr/local/bin/direnv version
  '
echo ">> direnv via GitHub OK"
