#!/bin/sh
# android-pacman-sandbox.sh — corre DENTRO do chroot Artix
# DisableSandbox + IgnorePkg em [options]; remove DownloadUser;
# comenta CheckSpace; instala hook ALPM para repor apos upgrade do pacman.
set -e
CONF=/etc/pacman.conf
HOOKDIR=/etc/pacman.d/hooks
HOOK="$HOOKDIR/zz-android-disable-sandbox.hook"
SELF=/usr/local/sbin/android-pacman-sandbox.sh

mkdir -p /usr/local/sbin "$HOOKDIR"

# Copiar-se para o path permanente (quando invocado de /root)
if [ -n "$0" ] && [ -f "$0" ] && [ "$0" != "$SELF" ]; then
  case "$0" in
    /dev/*) ;;
    /*)
      cp "$0" "$SELF"
      chmod 755 "$SELF"
      ;;
  esac
fi

if [ ! -f "$CONF" ]; then
  echo "!! $CONF ausente"
  exit 1
fi

sed -i '/^# Android chroot: kernel sem Landlock$/d' "$CONF"
sed -i '/^# Android chroot: kernel sem Landlock \/ sandbox alpm$/d' "$CONF"
sed -i '/^DisableSandbox/d' "$CONF"
sed -i '/^DownloadUser /d' "$CONF"
sed -i '/^# DownloadUser /d' "$CONF"
sed -i '/^IgnorePkg /d' "$CONF"
sed -i '/^DisableHooks /d' "$CONF"
sed -i 's/^CheckSpace$/# CheckSpace/' "$CONF"

if grep -q '^\[options\]' "$CONF"; then
  awk '
    BEGIN { done=0 }
    /^\[options\]/ && !done {
      print
      print "# Android chroot: kernel sem Landlock / sandbox alpm"
      print "DisableSandbox"
      print "IgnorePkg = linux-aarch64 linux-aarch64-lts linux-aarch64-headers linux-firmware mkinitcpio mkinitcpio-busybox"
      done=1
      next
    }
    { print }
  ' "$CONF" > "$CONF.tmp" && mv "$CONF.tmp" "$CONF"
else
  printf '%s\n' '[options]' '# Android chroot: kernel sem Landlock / sandbox alpm' 'DisableSandbox' \
    'IgnorePkg = linux-aarch64 linux-aarch64-lts linux-aarch64-headers linux-firmware mkinitcpio mkinitcpio-busybox' \
    | cat - "$CONF" > "$CONF.tmp" && mv "$CONF.tmp" "$CONF"
fi

cat > "$HOOK" <<'HOOK'
[Trigger]
Type = Package
Operation = Upgrade
Target = pacman

[Action]
Description = Reapply DisableSandbox for Android chroot
When = PostTransaction
Exec = /usr/local/sbin/android-pacman-sandbox.sh
HOOK
chmod 644 "$HOOK"

echo ">> [options] sandbox / IgnorePkg:"
awk '/^\[options\]/{p=1} /^\[/{if($0!="[options]")p=0} p' "$CONF" \
  | grep -E 'DisableSandbox|IgnorePkg|CheckSpace|DownloadUser' || true
echo ">> hook: $HOOK"
