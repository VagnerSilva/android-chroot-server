#!/system/bin/sh
# ============================================================
# install-dinit-services.sh
# Instala servicos dinit SO por ficheiros de configuracao:
#   /etc/dinit.d/<nome>           → definicao
#   /etc/dinit.d/boot.d/<nome>    → symlink (arranca no boot)
#
# Uso:
#   sh install-dinit-services.sh              # so dinit-test
#   sh install-dinit-services.sh dinit-test hermes omniroute
# ============================================================
set -e

. /data/linux/common.sh 2>/dev/null || . "$(dirname "$0")/common.sh"

BB="${BB:-/data/adb/ksu/bin/busybox}"
[ -x "$BB" ] || BB=/data/adb/magisk/busybox
[ -x "$BB" ] || BB=busybox
ROOT=/data/linux/mnt
PIDF=/data/linux/run/init.pid
BASE_SRC="${SRC:-/data/local/tmp}"
DINIT_SRC="$BASE_SRC/dinit.d"

# origem no repo apos prepare: /data/linux/dinit.d
[ -d "$DINIT_SRC" ] || DINIT_SRC=/data/linux/dinit.d
[ -d "$DINIT_SRC" ] || DINIT_SRC="$(dirname "$0")/dinit.d"

if [ ! -d "$DINIT_SRC" ]; then
  echo "!! pasta de configs nao encontrada (dinit.d)"
  exit 1
fi

SERVICES="${*:-dinit-test}"

run() {
  PID=$(cat "$PIDF" 2>/dev/null)
  [ -n "$PID" ] || { echo "!! container parado"; return 1; }
  $BB nsenter -t "$PID" -m -- $BB chroot "$ROOT" /usr/bin/env -i \
    HOME=/root TERM=linux LANG=C.UTF-8 \
    PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
    "$@"
}

mkdir -p "$ROOT/etc/dinit.d/boot.d" "$ROOT/usr/local/bin" "$ROOT/var/log/dinit"

# script do servico de teste (chmod DEPOIS de strip_crlf — redirect remove +x)
if [ -f "$BASE_SRC/dinit-test-svc.sh" ]; then
  cp "$BASE_SRC/dinit-test-svc.sh" "$ROOT/usr/local/bin/dinit-test-svc.sh"
  strip_crlf "$ROOT/usr/local/bin/dinit-test-svc.sh"
  chmod 755 "$ROOT/usr/local/bin/dinit-test-svc.sh"
elif [ -f /data/linux/dinit-test-svc.sh ]; then
  cp /data/linux/dinit-test-svc.sh "$ROOT/usr/local/bin/dinit-test-svc.sh"
  strip_crlf "$ROOT/usr/local/bin/dinit-test-svc.sh"
  chmod 755 "$ROOT/usr/local/bin/dinit-test-svc.sh"
fi

for name in $SERVICES; do
  SRC="$DINIT_SRC/$name"
  if [ ! -f "$SRC" ]; then
    echo "!! falta config: $SRC"
    exit 1
  fi
  echo ">> instalando /etc/dinit.d/$name"
  cp "$SRC" "$ROOT/etc/dinit.d/$name"
  chmod 644 "$ROOT/etc/dinit.d/$name"
  strip_crlf "$ROOT/etc/dinit.d/$name"

  # ativacao no boot = symlink em boot.d (ficheiro de config, nao dinitctl)
  echo ">> boot.d/$name -> ../$name"
  ln -sfn "../$name" "$ROOT/etc/dinit.d/boot.d/$name"

  # se o dinit ja esta a correr, carrega o servico agora
  if [ -f "$PIDF" ] && kill -0 "$(cat "$PIDF")" 2>/dev/null; then
    run dinitctl start "$name" 2>/dev/null \
      || run dinitctl reload "$name" 2>/dev/null \
      || run dinitctl restart "$name" 2>/dev/null \
      || echo "   (arrancara no proximo boot do container)"
  fi
done

echo
echo ">> boot.d atual:"
ls -la "$ROOT/etc/dinit.d/boot.d"

if [ -f "$PIDF" ] && kill -0 "$(cat "$PIDF")" 2>/dev/null; then
  echo
  for name in $SERVICES; do
    echo ">> status $name"
    run dinitctl status "$name" 2>/dev/null || true
  done
fi

echo
echo "OK — servicos definidos so por ficheiros em /etc/dinit.d/ + boot.d/"
