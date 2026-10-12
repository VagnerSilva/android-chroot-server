#!/system/bin/sh
# Sourced by other scripts. Paths and busybox for KernelSU.

BASE=/data/linux
IMG="$BASE/rootfs.img"
ROOT="$BASE/mnt"
RUN="$BASE/run"
PIDF="$RUN/init.pid"
LOG="$BASE/boot.log"
# shellcheck disable=SC2034
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
  P="${1:-}"
  [ -n "$P" ] && [ -d "/proc/$P" ] || return 1
  [ -d "/proc/$P/root" ] || return 1
  [ "$(readlink "/proc/$P/root" 2>/dev/null)" = "$ROOT" ] && return 0
  $BB tr '\0' ' ' < "/proc/$P/cmdline" 2>/dev/null | grep -q "chroot '$ROOT'" && return 0
  return 1
}

# Helpers de erro reutilizaveis para scripts POSIX.
die() {
  printf '%s\n' "!! $*" >&2
  exit 1
}

must() {
  "$@"
  status=$?
  if [ "$status" -eq 0 ]; then
    return 0
  fi
  printf '%s\n' "!! falha ao executar: $*" >&2
  return "$status"
}

# Args de nsenter: so -m se nao houver PID namespace (kernel sem CONFIG_PID_NS).
nsenter_ns_args() {
  P="${1:-}"
  case "$P" in
    ""|*[!0-9]*)
      printf '%s\n' "PID invalido: ${P:-<vazio>}" >&2
      return 1
      ;;
  esac

  if [ ! -d "/proc/$P" ]; then
    printf '%s\n' "PID inexistente: $P" >&2
    return 1
  fi

  if [ -e "/proc/$P/ns/pid" ]; then
    printf '%s\n' "-t $P -m -p"
  else
    printf '%s\n' "-t $P -m"
  fi
}

run_in_chroot() {
  [ -n "${PIDF:-}" ] || {
    printf '%s\n' "PIDF nao definido" >&2
    return 1
  }
  [ -n "${ROOT:-}" ] || {
    printf '%s\n' "ROOT nao definido" >&2
    return 1
  }
  [ -d "$ROOT" ] || {
    printf '%s\n' "ROOT invalido: $ROOT" >&2
    return 1
  }
  [ -n "${BB:-}" ] || {
    printf '%s\n' "busybox nao definido" >&2
    return 1
  }
  [ -x "$BB" ] || {
    printf '%s\n' "busybox ausente: $BB" >&2
    return 1
  }
  [ -f "$PIDF" ] || {
    printf '%s\n' "PIDF ausente: $PIDF" >&2
    return 1
  }

  PID=$(cat "$PIDF" 2>/dev/null || printf '')
  [ -n "$PID" ] || {
    printf '%s\n' "PID invalido em $PIDF" >&2
    return 1
  }

  NSARGS=$(nsenter_ns_args "$PID") || return 1

  "$BB" nsenter $NSARGS -- "$BB" chroot "$ROOT" /usr/bin/env -i \
    HOME="${HOME:-/root}" TERM="${TERM:-linux}" LANG="${LANG:-C.UTF-8}" \
    PATH="${PATH:-/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin}" \
    "$@"
  return $?
}

wait_for_container() {
  timeout="${1:-10}"
  case "$timeout" in
    ""|*[!0-9]*)
      printf '%s\n' "timeout invalido: ${timeout:-<vazio>}" >&2
      return 1
      ;;
  esac

  pid="${2:-}"
  if [ -z "$pid" ] && [ -n "${PIDF:-}" ] && [ -f "$PIDF" ]; then
    pid=$(cat "$PIDF" 2>/dev/null || printf '')
  fi

  case "$pid" in
    ""|*[!0-9]*)
      printf '%s\n' "PID do container invalido: ${pid:-<vazio>}" >&2
      return 1
      ;;
  esac

  i=0
  while [ "$i" -lt "$timeout" ]; do
    if container_vivo "$pid"; then
      return 0
    fi
    kill -0 "$pid" 2>/dev/null || return 1
    child=$($BB pgrep -P "$pid" 2>/dev/null | head -n1)
    if [ -n "$child" ] && container_vivo "$child"; then
      return 0
    fi
    i=$((i + 1))
    sleep 1
  done

  return 1
}

rotate_boot_log() {
  log_file="${1:-$LOG}"
  limit="${2:-262144}"

  [ -n "$log_file" ] || return 0
  [ -f "$log_file" ] || return 0
  case "$limit" in
    ""|*[!0-9]*)
      return 0
      ;;
  esac

  size=$(wc -c < "$log_file" 2>/dev/null || printf '0')
  case "$size" in
    ""|*[!0-9]*)
      size=0
      ;;
  esac

  if [ "$size" -lt "$limit" ]; then
    return 0
  fi

  if [ -f "$log_file.3" ]; then rm -f "$log_file.3" 2>/dev/null || true; fi
  if [ -f "$log_file.2" ]; then mv "$log_file.2" "$log_file.3" 2>/dev/null || true; fi
  if [ -f "$log_file.1" ]; then mv "$log_file.1" "$log_file.2" 2>/dev/null || true; fi
  mv "$log_file" "$log_file.1" 2>/dev/null || true
  : > "$log_file" 2>/dev/null || true
  return 0
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
