#!/system/bin/sh
# ============================================================
# enable-archlinuxarm.sh
# Ativa repos Arch Linux ARM (aarch64) DEPOIS dos repos ARMtix.
# ============================================================
set -e

. /data/linux/common.sh 2>/dev/null || . "$(dirname "$0")/common.sh"

SRC_ML=/data/linux/pacman.d/mirrorlist-archarm
[ -f "$SRC_ML" ] || SRC_ML="$(dirname "$0")/pacman.d/mirrorlist-archarm"
[ -f "$SRC_ML" ] || SRC_ML=/data/local/tmp/pacman.d/mirrorlist-archarm

[ -f "$SRC_ML" ] || { echo "!! falta mirrorlist-archarm"; exit 1; }
[ -f "$PIDF" ] && container_vivo "$(cat "$PIDF")" || { echo "!! container parado"; exit 1; }

PID=$(cat "$PIDF")
NSARGS=$(nsenter_ns_args "$PID")

# strip CRLF sem sed/tr '\r' (BusyBox Android apaga a letra r)
strip_cr() {
  CR=$(printf '\r')
  tr -d "$CR" < "$1" > "$1.tmp" && mv "$1.tmp" "$1"
}

mkdir -p "$ROOT/etc/pacman.d"
cp "$SRC_ML" "$ROOT/etc/pacman.d/mirrorlist-archarm"
strip_cr "$ROOT/etc/pacman.d/mirrorlist-archarm"

INNER="$ROOT/root/.enable-alarm-inner.sh"
# heredoc ASCII only — evitar CRLF/UTF8 issues
cat > "$INNER" <<'INNER'
#!/bin/sh
set -e
CONF=/etc/pacman.conf

# limpar bloco anterior e typos Neve
tmp=$(mktemp)
awk '
  /^# BEGIN Arch Linux ARM/ { skip=1; next }
  /^# END Arch Linux ARM/ { skip=0; next }
  skip { next }
  { print }
' "$CONF" > "$tmp"
mv "$tmp" "$CONF"
sed -i 's/SigLevel = Neve$/SigLevel = Never/' "$CONF" 2>/dev/null || true

printf '\n' >> "$CONF"
printf '%s\n' \
  '# BEGIN Arch Linux ARM (aarch64) - pacotes em falta no ARMtix' \
  '# Formato ALARM: $arch/$repo' \
  '[core]' \
  'SigLevel = Never' \
  'Include = /etc/pacman.d/mirrorlist-archarm' \
  '' \
  '[extra]' \
  'SigLevel = Never' \
  'Include = /etc/pacman.d/mirrorlist-archarm' \
  '' \
  '[alarm]' \
  'SigLevel = Never' \
  'Include = /etc/pacman.d/mirrorlist-archarm' \
  '' \
  '[aur]' \
  'SigLevel = Never' \
  'Include = /etc/pacman.d/mirrorlist-archarm' \
  '# END Arch Linux ARM' \
  >> "$CONF"

echo ">> pacman -Sy ..."
pacman -Sy --noconfirm
echo ">> ALARM ativo"
pacman -Ss '^direnv$' | head -5
INNER
strip_cr "$INNER"
chmod 755 "$INNER"

# shellcheck disable=SC2086
$BB nsenter $NSARGS -- \
  $BB chroot "$ROOT" /usr/bin/env -i \
    PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
    HOME=/root LANG=C.UTF-8 \
    /bin/sh /root/.enable-alarm-inner.sh

rm -f "$INNER"
echo ">> Arch Linux ARM habilitado"
