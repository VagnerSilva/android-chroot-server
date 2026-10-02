#!/system/bin/sh
# ============================================================
# linux-start.sh - sobe Artix com dinit
# su -c "/data/linux/linux-start.sh"
#
# Preferencia: unshare -m -p (dinit = PID 1 no namespace).
# Se o kernel rejeitar PID ns (Invalid argument 0x20020000),
# cai para so mount ns — dinit corre sem ser PID 1 global.
# ============================================================

. /data/linux/common.sh 2>/dev/null || . "$(dirname "$0")/common.sh"

INIT="${1:-$INIT_DEFAULT}"

ensure_dirs

LOCK="$RUN/start.lock"
if ! mkdir "$LOCK" 2>/dev/null; then
  echo "outro start ja esta em andamento (lock: $LOCK)"
  echo "se for lock preso: rmdir $LOCK"
  exit 0
fi
trap 'rmdir "$LOCK" 2>/dev/null' EXIT INT TERM

rm -f "$RUN/stopped"

if [ -f "$PIDF" ] && container_vivo "$(cat "$PIDF")"; then
  echo "ja esta rodando (pid $(cat "$PIDF"))"
  exit 0
fi
rm -f "$PIDF"

echo "=== start $(date) ===" >> "$LOG"

echo linux_server > /sys/power/wake_lock 2>/dev/null

mount_rootfs_rw >> "$LOG" 2>&1 || {
  echo "!! falha ao montar $IMG RW — veja $LOG e dmesg" | tee -a "$LOG"
  exit 1
}

# dinit (C++) precisa de libstdc++.so.6 — rootfs inconsistente = wipe + bootstrap
if [ ! -e "$ROOT/usr/lib/libstdc++.so.6" ] || [ ! -e "$ROOT/usr/lib/libgcc_s.so.1" ]; then
  echo "!! runtime GCC incompleto (libstdc++/libgcc) — rootfs inconsistente" | tee -a "$LOG"
  echo "   YES=1 /data/linux/wipe-chroot.sh && /data/linux/bootstrap.sh" | tee -a "$LOG"
  exit 1
fi

DNS1=$(getprop net.dns1 2>/dev/null)
[ -z "$DNS1" ] && DNS1=1.1.1.1
printf 'nameserver %s\nnameserver 8.8.8.8\n' "$DNS1" > "$ROOT/etc/resolv.conf"

sync_timezone_from_android >> "$LOG" 2>&1 || true

mkdir -p "$ROOT/mnt/android" "$ROOT/mnt/vendor" "$ROOT/mnt/system" "$ROOT/mnt/system_ext" "$ROOT/mnt/apex" \
  "$ROOT/dev/shm" "$ROOT/sys/fs/cgroup"

# script interno: binds + chroot + init
# /mnt/{vendor,system,apex} = EXTRAÇÃO para /opt/android-mali (nao requisito runtime GPU)
# Binds na raiz /system /vendor: so se /opt/android-mali ainda nao existir (compat)
INNER="$RUN/inner-start.sh"
cat > "$INNER" <<EOF
#!/system/bin/sh
BB='$BB'
ROOT='$ROOT'
INIT='$INIT'
\$BB mount --bind /dev "\$ROOT/dev"
# binderfs e mount nested — bind simples de /dev NAO o inclui
mkdir -p "\$ROOT/dev/binderfs"
if [ -d /dev/binderfs ]; then
  \$BB mount --rbind /dev/binderfs "\$ROOT/dev/binderfs" 2>/dev/null \
    || \$BB mount --bind /dev/binderfs "\$ROOT/dev/binderfs" 2>/dev/null
fi
mkdir -p "\$ROOT/dev/shm" "\$ROOT/dev/pts"
\$BB mount -t devpts -o gid=5,mode=620 devpts "\$ROOT/dev/pts"
\$BB mount -t tmpfs -o mode=1777,size=512M tmpfs "\$ROOT/dev/shm"
\$BB mount -t proc proc "\$ROOT/proc"
\$BB mount -t sysfs sysfs "\$ROOT/sys"
\$BB mount --bind /sys/fs/cgroup "\$ROOT/sys/fs/cgroup" 2>/dev/null
\$BB mount -t tmpfs -o mode=755 tmpfs "\$ROOT/run"
\$BB mount -t tmpfs -o mode=1777 tmpfs "\$ROOT/tmp"
\$BB mount --bind /data/media/0 "\$ROOT/mnt/android" 2>/dev/null
mkdir -p "\$ROOT/mnt/vendor" "\$ROOT/mnt/system" "\$ROOT/mnt/system_ext" "\$ROOT/mnt/apex"
# Extract-only mounts (runtime GPU = /opt/android-mali)
if [ -d /vendor ]; then
  \$BB mount --bind /vendor "\$ROOT/mnt/vendor" 2>/dev/null
  \$BB mount -o remount,ro,bind "\$ROOT/mnt/vendor" 2>/dev/null
fi
if [ -d /system ]; then
  \$BB mount --bind /system "\$ROOT/mnt/system" 2>/dev/null
  \$BB mount -o remount,ro,bind "\$ROOT/mnt/system" 2>/dev/null
fi
if [ -d /system_ext ]; then
  \$BB mount --bind /system_ext "\$ROOT/mnt/system_ext" 2>/dev/null
  \$BB mount -o remount,ro,bind "\$ROOT/mnt/system_ext" 2>/dev/null
fi
if [ -d /apex ]; then
  \$BB mount --rbind /apex "\$ROOT/mnt/apex" 2>/dev/null \
    || \$BB mount --bind /apex "\$ROOT/mnt/apex" 2>/dev/null
fi
# Compat legado: binds na raiz so sem arvore isolada
if [ ! -d "\$ROOT/opt/android-mali/vendor/lib64" ]; then
  mkdir -p "\$ROOT/system" "\$ROOT/vendor"
  if [ -d /vendor ]; then
    \$BB mount --bind /vendor "\$ROOT/vendor" 2>/dev/null
    \$BB mount -o remount,ro,bind "\$ROOT/vendor" 2>/dev/null
  fi
  if [ -d /system ]; then
    \$BB mount --bind /system "\$ROOT/system" 2>/dev/null
    \$BB mount -o remount,ro,bind "\$ROOT/system" 2>/dev/null
  fi
fi
exec \$BB chroot "\$ROOT" /usr/bin/env -i \\
  HOME=/root TERM=linux container=lxc LANG=C.UTF-8 \\
  PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \\
  \$INIT
EOF
chmod 755 "$INNER"
strip_crlf "$INNER" 2>/dev/null || true

# Testar / escolher modo unshare (PID ns falha em muitos kernels Android)
MODE_FILE="$RUN/unshare.mode"
NS_MODE=""

try_unshare() {
  # $1 = descricao; resto = args do unshare antes de --
  desc="$1"
  shift
  if $BB unshare "$@" -- /system/bin/true >/dev/null 2>>"$LOG"; then
    NS_MODE="$desc"
    echo "$desc" > "$MODE_FILE"
    echo ">> unshare ok: $desc" | tee -a "$LOG"
    return 0
  fi
  echo ">> unshare falhou ($desc)" >> "$LOG"
  return 1
}

# 0x20020000 = CLONE_NEWPID|CLONE_NEWNS — EINVAL = kernel sem PID_NS ou bloqueado
try_unshare "mount+pid+prop" -m -p -f --propagation private \
  || try_unshare "mount+pid" -m -p -f \
  || try_unshare "mount+prop" -m -f --propagation private \
  || try_unshare "mount" -m -f \
  || {
    echo "!! nenhum modo unshare funcionou. Kernel sem namespaces?" | tee -a "$LOG"
    echo "!! teste: zcat /proc/config.gz 2>/dev/null | grep CONFIG_PID_NS" | tee -a "$LOG"
    exit 1
  }

case "$NS_MODE" in
  mount+pid+prop)
    $BB unshare -m -p -f --propagation private -- /system/bin/sh "$INNER" >> "$LOG" 2>&1 &
    ;;
  mount+pid)
    $BB unshare -m -p -f -- /system/bin/sh "$INNER" >> "$LOG" 2>&1 &
    ;;
  mount+prop)
    $BB unshare -m -f --propagation private -- /system/bin/sh "$INNER" >> "$LOG" 2>&1 &
    ;;
  mount)
    $BB unshare -m -f -- /system/bin/sh "$INNER" >> "$LOG" 2>&1 &
    ;;
esac

UPID=$!
echo "$UPID" > "$PIDF"

sleep 5
if ! kill -0 "$UPID" 2>/dev/null; then
  echo "!! processo unshare morreu — veja $LOG" | tee -a "$LOG"
  echo "!! se [FAILED] boot / udev / modules / fsck:" | tee -a "$LOG"
  echo "!!   /data/linux/fix-dinit-chroot.sh && /data/linux/linux-start.sh" | tee -a "$LOG"
  tail -n 40 "$LOG"
  rm -f "$PIDF"
  exit 1
fi

IPID=$($BB pgrep -P "$UPID" 2>/dev/null | head -n1)
[ -z "$IPID" ] && IPID=$UPID
echo "$IPID" > "$PIDF"

echo -1000 > /proc/$IPID/oom_score_adj 2>/dev/null

echo "linux iniciado (pid $IPID, init=$INIT, ns=$NS_MODE) - log: $LOG"
if echo "$NS_MODE" | grep -qv pid; then
  echo "aviso: sem PID namespace — dinit nao e PID 1 isolado; kernel provavelmente sem CONFIG_PID_NS"
fi
