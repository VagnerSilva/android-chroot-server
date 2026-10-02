#!/system/bin/sh
# ============================================================
# install-autostart.sh — KernelSU late_start (service.d)
#
# Copia 99-linux.sh → /data/adb/service.d/99-linux.sh
# Chamado por prepare.sh e bootstrap.sh (idempotente).
#
# SKIP_AUTOSTART=1 — nao instalar / nao actualizar
# ============================================================

. /data/linux/common.sh 2>/dev/null || . "$(dirname "$0")/common.sh"

AUTOSTART_DST=/data/adb/service.d/99-linux.sh
AUTOSTART_SRC=/data/linux/99-linux.sh
[ -f "$AUTOSTART_SRC" ] || AUTOSTART_SRC="$(dirname "$0")/99-linux.sh"

if [ "${SKIP_AUTOSTART:-0}" = 1 ]; then
  echo ">> SKIP_AUTOSTART=1 — autostart nao instalado"
  exit 0
fi

if [ ! -f "$AUTOSTART_SRC" ]; then
  echo "!! 99-linux.sh ausente ($AUTOSTART_SRC)"
  exit 1
fi

if [ "$(id -u)" != "0" ]; then
  echo "!! precisa ser root (su / KernelSU)"
  exit 1
fi

mkdir -p /data/adb/service.d
cp "$AUTOSTART_SRC" "$AUTOSTART_DST"
# strip CRLF (funcao em common.sh)
if type strip_crlf >/dev/null 2>&1; then
  strip_crlf "$AUTOSTART_DST"
else
  CR=$(printf '\r')
  tr -d "$CR" < "$AUTOSTART_DST" > "$AUTOSTART_DST.__nocr" \
    && mv -f "$AUTOSTART_DST.__nocr" "$AUTOSTART_DST"
fi
chmod 755 "$AUTOSTART_DST"
echo ">> autostart OK: $AUTOSTART_DST"
ls -la "$AUTOSTART_DST"
exit 0
