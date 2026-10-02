#!/system/bin/sh
# ============================================================
# wipe-chroot.sh — remove COMPLETAMENTE o chroot + ficheiros do projeto
#
# Apaga:
#   - /data/linux/rootfs.img (sistema Artix)
#   - TODO o conteudo de /data/linux/ (scripts, dinit.d, mesa pkgs, logs…)
#   - /data/adb/service.d/99-linux.sh (autostart do projecto)
#
# NAO toca:
#   - /system /vendor /product /apex /sdcard
#   - Termux (/data/data/com.termux/…)
#   - KernelSU/Magisk (excepto o 99-linux.sh em service.d)
#   - apps Android
#
# Uso:
#   su -c "YES=1 /data/linux/wipe-chroot.sh"
#
# Sem YES=1: so lista o que seria apagado e sai com erro.
# Depois: voltar a fazer prepare.sh / deploy.ps1 no PC.
# ============================================================

. /data/linux/common.sh 2>/dev/null || . "$(dirname "$0")/common.sh"

AUTOSTART=/data/adb/service.d/99-linux.sh

# --- so permitir remocoes sob $BASE (excepto autostart conhecido) ---
assert_under_base() {
  p="$1"
  case "$p" in
    "$BASE"|"$BASE"/*) return 0 ;;
    *)
      echo "!! recusa path fora de $BASE: $p"
      exit 99
      ;;
  esac
}

assert_under_base "$IMG"
assert_under_base "$ROOT"
assert_under_base "$RUN"
assert_under_base "$LOG"

print_plan() {
  echo "============================================================"
  echo " wipe-chroot — plano"
  echo "============================================================"
  echo " APAGA (projecto + chroot):"
  [ -f "$IMG" ] && echo "   $IMG  ($(ls -lh "$IMG" 2>/dev/null | awk '{print $5}'))" \
    || echo "   $IMG  (ausente)"
  echo "   TODO o conteudo de $BASE/  (scripts, configs, mesa, run, mnt…)"
  [ -f "$AUTOSTART" ] && echo "   $AUTOSTART" || echo "   $AUTOSTART  (ausente)"
  echo
  echo " MANTÉM (Android / device):"
  echo "   /system /vendor /product /apex /sdcard"
  echo "   /data/adb (KernelSU/Magisk) excepto $AUTOSTART"
  echo "   Termux e restantes apps em /data/data"
  echo "============================================================"
}

umount_all_under_root() {
  if [ -d "$ROOT" ]; then
    grep " $ROOT/" /proc/mounts 2>/dev/null | awk '{print $2}' | sort -r | while read -r mp; do
      [ -n "$mp" ] || continue
      case "$mp" in
        "$ROOT"/*)
          echo ">> umount $mp"
          $BB umount "$mp" 2>/dev/null || $BB umount -l "$mp" 2>/dev/null || true
          ;;
      esac
    done
  fi
  $BB umount "$ROOT" 2>/dev/null || $BB umount -l "$ROOT" 2>/dev/null || true
  for L in $($BB losetup -a 2>/dev/null | grep rootfs.img | cut -d: -f1); do
    echo ">> losetup -d $L"
    $BB losetup -d "$L" 2>/dev/null || true
  done
}

still_mounted() {
  grep -q " $ROOT " /proc/mounts 2>/dev/null && return 0
  grep -q " $ROOT/" /proc/mounts 2>/dev/null && return 0
  return 1
}

# Apaga cada entrada directa de $BASE (nao o proprio $BASE nem paths fora).
wipe_base_contents() {
  assert_under_base "$BASE"
  if [ ! -d "$BASE" ]; then
    echo ">> $BASE ja ausente"
    return 0
  fi
  echo ">> apagar todo o conteudo de $BASE"
  for e in "$BASE"/* "$BASE"/.[!.]* "$BASE"/..?*; do
    [ -e "$e" ] || [ -L "$e" ] || continue
    case "$e" in
      "$BASE"/*|"$BASE"/.[!.]*|"$BASE"/..?*)
        echo "   rm -rf $e"
        $BB rm -rf "$e" 2>/dev/null || rm -rf "$e"
        ;;
      *)
        echo "!! skip path inesperado: $e"
        ;;
    esac
  done
}

print_plan

if [ "${YES:-0}" != 1 ]; then
  echo
  echo "!! confirma com: YES=1 $0"
  exit 1
fi

echo
echo ">> YES=1 — wipe chroot + ficheiros do projecto (Android/apps intactos)"

# 1) parar container (precisa dos scripts ainda presentes)
if [ -f "$BASE/linux-stop.sh" ]; then
  echo ">> linux-stop.sh"
  sh "$BASE/linux-stop.sh" || true
else
  echo "!! linux-stop.sh ausente — stop best-effort"
  if [ -f "$PIDF" ]; then
    PID=$(cat "$PIDF" 2>/dev/null)
    [ -n "$PID" ] && kill -TERM "$PID" 2>/dev/null
    [ -n "$PID" ] && kill -KILL "$PID" 2>/dev/null
    rm -f "$PIDF"
  fi
fi

# 2) umount agressivo
umount_all_under_root
sync

if still_mounted; then
  echo "!! ainda ha mounts sob $ROOT — abortar antes de apagar"
  grep " $ROOT" /proc/mounts 2>/dev/null | awk '{print "  " $2}'
  exit 2
fi

# 3) apagar imagem (antes do wipe total; idempotente se ja for)
if [ -f "$IMG" ]; then
  assert_under_base "$IMG"
  echo ">> apagar $IMG"
  rm -f "$IMG" || {
    echo "!! falha a apagar $IMG"
    exit 3
  }
fi

# 4) limpar TODO /data/linux (scripts + artefactos do projecto)
wipe_base_contents
sync

# 5) autostart do projecto em service.d (unico ficheiro fora de BASE)
if [ -f "$AUTOSTART" ] || [ -L "$AUTOSTART" ]; then
  echo ">> apagar $AUTOSTART"
  rm -f "$AUTOSTART" || {
    echo "!! falha a apagar $AUTOSTART"
    exit 4
  }
fi

echo
echo ">> wipe concluido"
echo "   $BASE: $(ls -A "$BASE" 2>/dev/null | wc -l | tr -d ' ') entradas restantes (esperado 0)"
[ -f "$IMG" ] && echo "!! $IMG AINDA EXISTE" || echo "   rootfs.img: ausente"
[ -f "$AUTOSTART" ] && echo "!! $AUTOSTART AINDA EXISTE" || echo "   autostart: ausente"

cat <<EOF

============================================================
 Proximos passos (no PC):
   # repor scripts no device
   rootfs/host/prepare.sh   ou   rootfs/host/deploy.ps1
 Depois no device:
   /data/linux/install-rootfs.sh
   /data/linux/linux-start.sh
============================================================
EOF
