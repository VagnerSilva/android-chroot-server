#!/bin/sh
# Coloca DisableSandbox + IgnorePkg na secao [options]; remove DownloadUser;
# comenta CheckSpace (falha em /data no Android).
CONF=/etc/pacman.conf
SED=/usr/bin/sed
GREP=/usr/bin/grep
AWK=/usr/bin/awk

# remover entradas antigas / mal colocadas
$SED -i '/^# Android chroot: kernel sem Landlock$/d' "$CONF"
$SED -i '/^# Android chroot: kernel sem Landlock \/ sandbox alpm$/d' "$CONF"
$SED -i '/^DisableSandbox$/d' "$CONF"
$SED -i '/^DownloadUser /d' "$CONF"
$SED -i '/^# DownloadUser /d' "$CONF"
$SED -i '/^IgnorePkg /d' "$CONF"
$SED -i '/^DisableHooks /d' "$CONF"
$SED -i 's/^CheckSpace$/# CheckSpace/' "$CONF"

# inserir apos a linha [options]
if $GREP -q '^\[options\]' "$CONF"; then
  $AWK '
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
  printf '%s\n' '[options]' '# Android chroot' 'DisableSandbox' \
    'IgnorePkg = linux-aarch64 linux-aarch64-lts linux-aarch64-headers linux-firmware mkinitcpio mkinitcpio-busybox' \
    | cat - "$CONF" > "$CONF.tmp" && mv "$CONF.tmp" "$CONF"
fi

echo ">> [options] sandbox / IgnorePkg:"
$AWK '/^\[options\]/{p=1} /^\[/{if($0!="[options]")p=0} p' "$CONF" \
  | $GREP -E 'DisableSandbox|IgnorePkg|CheckSpace|DownloadUser' || true
