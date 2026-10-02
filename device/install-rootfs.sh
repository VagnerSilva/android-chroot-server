#!/system/bin/sh
# ============================================================
# install-rootfs.sh — cria ext4 e extrai o tarball Artix/dinit
#
# Procura (nesta ordem):
#   1) argumento / ARMTIX_TAR
#   2) home Termux: ~/armtix-dinit-20260921.tar.xz (ou armtix-dinit-*.tar.xz)
#   3) /data/local/tmp/armtix-dinit-20260921.tar.xz (ou armtix-dinit-*.tar.xz)
#   4) download → /data/local/tmp/armtix-dinit-20260921.tar.xz
#
# su -c "/data/linux/install-rootfs.sh"
# su -c "/data/linux/install-rootfs.sh /caminho/arquivo.tar.xz"
# Opcional: SIZE_GB=8
# ============================================================
set -e

. /data/linux/common.sh 2>/dev/null || . "$(dirname "$0")/common.sh"

TERMUX_HOME=/data/data/com.termux/files/home
TMP_DIR=/data/local/tmp
TAR_NAME=armtix-dinit-20260921.tar.xz
TAR_URL="https://armtix.artixlinux.org/images/$TAR_NAME"
SIZE_GB="${SIZE_GB:-8}"

find_downloader() {
  for c in /system/bin/curl /system/bin/wget; do
    [ -x "$c" ] && { echo "$c"; return 0; }
  done
  command -v curl 2>/dev/null && return 0
  command -v wget 2>/dev/null && return 0
  # busybox wget (KSU/Magisk)
  if "$BB" wget --help >/dev/null 2>&1; then
    echo "$BB wget"
    return 0
  fi
  return 1
}

download_tarball() {
  out="$1"
  dl=$(find_downloader) || {
    echo "!! sem curl/wget para baixar $TAR_URL"
    return 1
  }
  echo ">> download: $TAR_URL"
  echo "   destino: $out"
  case "$dl" in
    *curl)
      "$dl" -fL --retry 3 --connect-timeout 30 -o "$out.partial" "$TAR_URL" || {
        rm -f "$out.partial"; return 1
      }
      ;;
    *wget)
      # $dl pode ser "busybox wget" (duas palavras)
      # shellcheck disable=SC2086
      $dl -O "$out.partial" "$TAR_URL" || {
        rm -f "$out.partial"; return 1
      }
      ;;
    *)
      return 1
      ;;
  esac
  mv -f "$out.partial" "$out"
}

# Primeiro tarball armtix-dinit-*.tar.xz numa pasta (mais recente por nome)
pick_armtix_in_dir() {
  dir="$1"
  [ -d "$dir" ] || return 1
  hit=$(ls -1 "$dir"/armtix-dinit-*.tar.xz 2>/dev/null | sort | tail -n1) || true
  [ -n "$hit" ] && [ -f "$hit" ] && { echo "$hit"; return 0; }
  return 1
}

resolve_tarball() {
  if [ -n "${1:-}" ]; then
    echo "$1"; return 0
  fi
  if [ -n "${ARMTIX_TAR:-}" ] && [ -f "$ARMTIX_TAR" ]; then
    echo "$ARMTIX_TAR"; return 0
  fi
  for cand in \
    "$TERMUX_HOME/$TAR_NAME" \
    "$TMP_DIR/$TAR_NAME"
  do
    [ -f "$cand" ] && { echo "$cand"; return 0; }
  done
  hit=$(pick_armtix_in_dir "$TERMUX_HOME") && { echo "$hit"; return 0; }
  hit=$(pick_armtix_in_dir "$TMP_DIR") && { echo "$hit"; return 0; }

  dest="$TMP_DIR/$TAR_NAME"
  download_tarball "$dest" || return 1
  echo "$dest"
}

TARBALL=$(resolve_tarball "${1:-}") || true
if [ -z "$TARBALL" ] || [ ! -f "$TARBALL" ]; then
  echo "uso: $0 [rootfs.tar|tar.gz|tar.xz]"
  echo "padrao: $TERMUX_HOME/$TAR_NAME ou $TMP_DIR/$TAR_NAME"
  echo "url:    $TAR_URL"
  echo
  echo "procurando em $TERMUX_HOME:"
  ls -lh "$TERMUX_HOME"/*.tar* 2>/dev/null || echo "  (nenhum)"
  echo "procurando em $TMP_DIR:"
  ls -lh "$TMP_DIR"/armtix-dinit-*.tar* 2>/dev/null || echo "  (nenhum)"
  echo "procurando em /sdcard/Download:"
  ls -lh /sdcard/Download/*.tar* 2>/dev/null || echo "  (nenhum)"
  exit 1
fi

echo ">> tarball: $TARBALL"
ensure_dirs

if [ ! -f "$IMG" ]; then
  echo ">> criando imagem ext4 esparsa de ${SIZE_GB}G"
  $BB truncate -s "${SIZE_GB}G" "$IMG"
  if [ -x /system/bin/mke2fs ]; then
    /system/bin/mke2fs -t ext4 -F -m 0 -L linuxroot "$IMG"
  elif command -v mkfs.ext4 >/dev/null 2>&1; then
    mkfs.ext4 -F -m 0 -L linuxroot "$IMG"
  else
    echo "!! sem mke2fs/mkfs.ext4"
    rm -f "$IMG"
    exit 1
  fi
else
  echo ">> reaproveitando imagem: $IMG"
fi

mount_rootfs_rw || exit 1

if [ ! -e "$ROOT/bin/sh" ] && [ ! -L "$ROOT/bin" ]; then
  echo ">> extraindo (pode demorar)..."
  case "$TARBALL" in
    *.gz|*.tgz)
      $BB tar --numeric-owner -xzf "$TARBALL" -C "$ROOT"
      ;;
    *.xz)
      if $BB tar --numeric-owner -xJf "$TARBALL" -C "$ROOT" 2>/dev/null; then
        :
      elif $BB unxz -c "$TARBALL" 2>/dev/null | $BB tar --numeric-owner -xf - -C "$ROOT"; then
        :
      elif [ -x "$TERMUX_HOME/../usr/bin/xz" ]; then
        "$TERMUX_HOME/../usr/bin/xz" -dc "$TARBALL" | $BB tar --numeric-owner -xf - -C "$ROOT"
      elif command -v xz >/dev/null 2>&1; then
        xz -dc "$TARBALL" | $BB tar --numeric-owner -xf - -C "$ROOT"
      else
        echo "!! nao descomprimi xz. No Termux (sem root):"
        echo "   pkg install xz-utils"
        echo "   xz -dk $TARBALL"
        echo "   # depois: $0 ${TARBALL%.xz}"
        $BB umount "$ROOT" 2>/dev/null
        exit 1
      fi
      ;;
    *)
      $BB tar --numeric-owner -xf "$TARBALL" -C "$ROOT"
      ;;
  esac
else
  echo ">> rootfs ja presente em $ROOT — pulando extracao"
fi

if [ ! -e "$ROOT/bin/sh" ] && [ ! -L "$ROOT/bin" ]; then
  echo "!! extracao falhou: sem $ROOT/bin/sh"
  $BB umount "$ROOT" 2>/dev/null
  exit 1
fi

echo ">> ajustes pos-extracao"
mkdir -p "$ROOT/proc" "$ROOT/sys" "$ROOT/dev/shm" "$ROOT/dev/pts" \
  "$ROOT/run" "$ROOT/tmp" "$ROOT/mnt/android" "$ROOT/sys/fs/cgroup"
chmod 1777 "$ROOT/tmp"

if ! grep -q '^aid_inet:' "$ROOT/etc/group" 2>/dev/null; then
  cat >> "$ROOT/etc/group" <<'EOF'
aid_bt_admin:x:3001:root
aid_bt:x:3002:root
aid_inet:x:3003:root
aid_net_raw:x:3004:root
aid_net_admin:x:3005:root
aid_sdcard_rw:x:1015:root
aid_media_rw:x:1023:root
aid_everybody:x:9997:root
EOF
fi

rm -f "$ROOT/etc/resolv.conf"
DNS1=$(getprop net.dns1 2>/dev/null); [ -z "$DNS1" ] && DNS1=1.1.1.1
printf 'nameserver %s\nnameserver 8.8.8.8\n' "$DNS1" > "$ROOT/etc/resolv.conf"

$BB umount "$ROOT" 2>/dev/null || true
for L in $($BB losetup -a 2>/dev/null | grep rootfs.img | cut -d: -f1); do
  $BB losetup -d "$L" 2>/dev/null
done

LOOP=$($BB losetup -f --show "$IMG" 2>/dev/null) || true
if [ -n "$LOOP" ]; then
  [ -x /system/bin/e2fsck ] && /system/bin/e2fsck -fy "$LOOP" || true
  $BB losetup -d "$LOOP" 2>/dev/null
fi

cat <<EOF

============================================================
 rootfs instalado: $IMG
 fonte: $TARBALL

 Proximos (recomendado — completo):
   /data/linux/bootstrap.sh
   # ou com user sem TTY:
   CREATE_USER=1 ARTIX_USER=<user> ARTIX_PASS='senha' /data/linux/bootstrap.sh

 Alternativa manual:
   /data/linux/linux-start.sh
   /data/linux/run-setup.sh          # sshd + dinit + dbus + elogind
   /data/linux/linux-status.sh
   # autostart: prepare/bootstrap instalam; repor:
   /data/linux/install-autostart.sh
============================================================
EOF
