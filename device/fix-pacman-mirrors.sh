#!/system/bin/sh
# ============================================================
# fix-pacman-mirrors.sh
# Mirrorlist ARMtix (aarch64) + SigLevel=Never + sync.
# ============================================================
set -e

. /data/linux/common.sh 2>/dev/null || . "$(dirname "$0")/common.sh"

SRC_ML=/data/linux/pacman.d/mirrorlist
[ -f "$SRC_ML" ] || SRC_ML="$(dirname "$0")/pacman.d/mirrorlist"
[ -f "$SRC_ML" ] || SRC_ML=/data/local/tmp/pacman.d/mirrorlist

if [ ! -f "$SRC_ML" ]; then
  echo "!! mirrorlist fonte nao encontrado"
  exit 1
fi

if [ ! -f "$PIDF" ] || ! container_vivo "$(cat "$PIDF")"; then
  echo "!! container parado — /data/linux/linux-start.sh"
  exit 1
fi

PID=$(cat "$PIDF")
NSARGS=$(nsenter_ns_args "$PID")

mkdir -p "$ROOT/etc/pacman.d"
cp "$SRC_ML" "$ROOT/etc/pacman.d/mirrorlist"
strip_crlf "$ROOT/etc/pacman.d/mirrorlist"
chmod 644 "$ROOT/etc/pacman.d/mirrorlist"

# script interno (evita quoting infernal)
INNER="$ROOT/root/.fix-mirrors-inner.sh"
cat > "$INNER" <<'INNER'
#!/bin/sh
set -e
CONF=/etc/pacman.conf

# Garante SigLevel=Never imediatamente apos cada [repo] ARMtix
tmp=$(mktemp)
awk '
  BEGIN { repos["system"]=1; repos["world"]=1; repos["galaxy"]=1; repos["armtix"]=1 }
  /^\[/ {
    name=$0
    gsub(/[\[\]]/,"",name)
    print
    if (name in repos) {
      print "SigLevel = Never"
      inrepo=1
      next
    } else {
      inrepo=0
    }
    next
  }
  inrepo && /^SigLevel/ { next }
  { print }
' "$CONF" > "$tmp"
mv "$tmp" "$CONF"

# sandbox (kernel Android sem Landlock); sem DownloadUser; IgnorePkg kernel
sed -i '/^DisableSandbox$/d' "$CONF"
sed -i '/^DownloadUser /d' "$CONF"
sed -i '/^IgnorePkg /d' "$CONF"
sed -i 's/^CheckSpace$/# CheckSpace/' "$CONF"
sed -i "/^\[options\]/a DisableSandbox\nIgnorePkg = linux-aarch64 linux-aarch64-lts linux-aarch64-headers linux-firmware mkinitcpio mkinitcpio-busybox" "$CONF"

echo ">> Servers:"
grep "^Server" /etc/pacman.d/mirrorlist
echo ">> Secoes:"
grep -E "^\[|^SigLevel|^Include|^DisableSandbox|^IgnorePkg|^# CheckSpace" "$CONF"
echo ">> pacman -Syy ..."
pacman -Syy --noconfirm
echo ">> sync OK"
INNER
strip_crlf "$INNER"
chmod 755 "$INNER"

# shellcheck disable=SC2086
$BB nsenter $NSARGS -- \
  $BB chroot "$ROOT" /usr/bin/env -i \
    PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
    HOME=/root LANG=C.UTF-8 \
    /bin/sh /root/.fix-mirrors-inner.sh

rm -f "$INNER"
echo ">> mirrors ARMtix aplicados"
