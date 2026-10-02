#!/system/bin/sh
# Sourced by other scripts. Paths and busybox for KernelSU.

BASE=/data/linux
IMG="$BASE/rootfs.img"
ROOT="$BASE/mnt"
RUN="$BASE/run"
PIDF="$RUN/init.pid"
LOG="$BASE/boot.log"
INIT_DEFAULT=/sbin/dinit

BB=/data/adb/ksu/bin/busybox
[ -x "$BB" ] || BB=/data/adb/magisk/busybox
[ -x "$BB" ] || BB=busybox

export PATH=/system/bin:/system/xbin:$PATH

# Remove bytes CR (0x0D). NUNCA use sed 's/\r//' nem tr -d '\r' no BusyBox
# Android: \r no padrao e tratado como a LETRA r (Never->Neve, run->un).
strip_crlf() {
  f="$1"
  [ -f "$f" ] || return 0
  # preservar modo: redirect cria ficheiro 0644 e apaga +x
  mode=$(stat -c '%a' "$f" 2>/dev/null || stat -f '%OLp' "$f" 2>/dev/null || echo "")
  CR=$(printf '\r')
  tr -d "$CR" < "$f" > "$f.__nocr" && mv -f "$f.__nocr" "$f"
  [ -n "$mode" ] && chmod "$mode" "$f" 2>/dev/null || true
}

ensure_dirs() {
  mkdir -p "$BASE" "$ROOT" "$RUN"
}

# True if PID is our container (by chroot root or cmdline).
container_vivo() {
  P="$1"
  [ -n "$P" ] && [ -d "/proc/$P" ] || return 1
  [ "$(readlink "/proc/$P/root" 2>/dev/null)" = "$ROOT" ] && return 0
  $BB tr '\0' ' ' < "/proc/$P/cmdline" 2>/dev/null | grep -q "chroot '$ROOT'" && return 0
  return 1
}

# Args de nsenter: so -m se nao houver PID namespace (kernel sem CONFIG_PID_NS).
nsenter_ns_args() {
  P="$1"
  if [ -e "/proc/$P/ns/pid" ]; then
    echo "-t $P -m -p"
  else
    echo "-t $P -m"
  fi
}

# Sync /etc/timezone + /etc/localtime from Android persist.sys.timezone.
# Relogio UTC ja vem do kernel; so falta o fuso. Nao aborta o start se falhar.
sync_timezone_from_android() {
  TZ_NAME=$(getprop persist.sys.timezone 2>/dev/null)
  if [ -z "$TZ_NAME" ]; then
    echo ">> timezone: persist.sys.timezone vazio — mantem actual"
    return 0
  fi
  ZFILE="$ROOT/usr/share/zoneinfo/$TZ_NAME"
  if [ ! -f "$ZFILE" ] && [ ! -L "$ZFILE" ]; then
    echo "!! timezone: zoneinfo ausente: $ZFILE"
    return 1
  fi
  printf '%s\n' "$TZ_NAME" > "$ROOT/etc/timezone"
  ln -sfn "/usr/share/zoneinfo/$TZ_NAME" "$ROOT/etc/localtime"
  echo ">> timezone=$TZ_NAME"
  return 0
}

# Mount image RW + suid,dev; abort if not really RW.
mount_rootfs_rw() {
  if [ ! -f "$IMG" ]; then
    echo "!! imagem nao encontrada: $IMG"
    return 1
  fi

  if ! $BB mountpoint -q "$ROOT"; then
    LOOP=$($BB losetup -f --show "$IMG" 2>/dev/null)
    if [ -z "$LOOP" ]; then
      LOOP=$($BB losetup -f 2>/dev/null)
      if [ -n "$LOOP" ] && $BB losetup "$LOOP" "$IMG" 2>/dev/null; then
        :
      else
        $BB mount -t ext4 -o loop,rw,noatime,suid,dev "$IMG" "$ROOT" || return 1
        LOOP=
      fi
    fi
    if [ -n "$LOOP" ]; then
      $BB mount -t ext4 -o rw,noatime,suid,dev "$LOOP" "$ROOT" || return 1
    fi
  fi

  $BB mount -o remount,rw,suid,dev "$ROOT" 2>/dev/null || true

  LINE=$(grep " $ROOT " /proc/mounts) || {
    echo "!! $ROOT nao esta em /proc/mounts"
    return 1
  }
  echo "$LINE" | grep -q ' rw,' || {
    echo "!! mount sem RW: $LINE"
    echo "!! confira modulo sepolicy artix_chroot_loop e dmesg | grep -iE 'avc|ext4|loop'"
    return 1
  }
  echo "$LINE" | grep -q nosuid && {
    echo "!! mount com nosuid: $LINE"
    return 1
  }
  echo "$LINE" | grep -q nodev && {
    echo "!! mount com nodev: $LINE"
    return 1
  }
  # flag ro como opcao (nao substring de errors=remount-ro sozinha)
  echo "$LINE" | tr ',' ' ' | tr ' ' '\n' | grep -qx ro && {
    echo "!! mount ainda ro: $LINE"
    return 1
  }

  touch "$ROOT/.rwtest" 2>/dev/null && rm -f "$ROOT/.rwtest" || {
    echo "!! touch falhou em $ROOT (nao RW de verdade)"
    return 1
  }
  return 0
}
