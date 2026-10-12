#!/system/bin/sh

. /data/linux/common.sh 2>/dev/null || . "$(dirname "$0")/common.sh"

if [ "$(id -u)" != "0" ]; then
  echo "!! precisa ser root (su / KernelSU)" >&2
  exit 1
fi

if [ ! -f "$IMG" ]; then
  echo "!! imagem nao encontrada: $IMG" >&2
  exit 1
fi

mkdir -p "$RUN"
LOCK="$RUN/start.lock"
if ! mkdir "$LOCK" 2>/dev/null; then
  echo "!! outro start/backup esta em andamento (lock: $LOCK)" >&2
  exit 1
fi
LOCKED=1
TMP=
cleanup() {
  [ -n "$TMP" ] && rm -f "$TMP"
  [ "$LOCKED" = 1 ] && rmdir "$LOCK" 2>/dev/null || true
}
trap cleanup 0 HUP INT TERM

if [ -f "$PIDF" ] && container_vivo "$(cat "$PIDF" 2>/dev/null)"; then
  echo "!! pare o container antes do backup: /data/linux/linux-stop.sh" >&2
  exit 1
fi

if "$BB" mountpoint -q "$ROOT"; then
  echo "!! rootfs ainda montado em $ROOT; desmonte antes do backup" >&2
  exit 1
fi

DEST=${1:-$IMG.bak}
DEST_DIR=$(dirname "$DEST")
if [ "$DEST" = "$IMG" ]; then
  echo "!! destino nao pode ser a imagem original" >&2
  exit 1
fi
if [ ! -d "$DEST_DIR" ] || [ ! -w "$DEST_DIR" ]; then
  echo "!! diretorio de destino ausente ou sem permissao: $DEST_DIR" >&2
  exit 1
fi
if [ -e "$DEST" ]; then
  echo "!! backup ja existe; nao sera sobrescrito: $DEST" >&2
  exit 1
fi

TMP="$DEST.tmp.$$"
if [ -e "$TMP" ]; then
  echo "!! temporario ja existe; remova-o manualmente: $TMP" >&2
  exit 1
fi

SIZE=$(wc -c < "$IMG" | tr -d ' ')
AVAILABLE_KB=$(df -Pk "$DEST_DIR" | awk 'END {print $4}')
case "$SIZE:$AVAILABLE_KB" in
  *[!0-9:]*|:*)
    echo "!! nao foi possivel verificar o espaco livre em $DEST_DIR" >&2
    exit 1
    ;;
esac
NEEDED_KB=$(( (SIZE + 1023) / 1024 ))
if [ "$AVAILABLE_KB" -lt "$NEEDED_KB" ]; then
  echo "!! espaco insuficiente: precisa de ${NEEDED_KB} KiB, disponivel ${AVAILABLE_KB} KiB" >&2
  exit 1
fi

echo ">> copiando $IMG para $DEST"
if ! cp -p "$IMG" "$TMP" || ! cmp -s "$IMG" "$TMP"; then
  echo "!! copia incompleta ou divergente; original preservado" >&2
  exit 1
fi
if ! ln "$TMP" "$DEST"; then
  echo "!! nao foi possivel publicar o backup: $DEST" >&2
  exit 1
fi
rm -f "$TMP"
TMP=
cleanup
LOCKED=0
trap - 0 HUP INT TERM
echo ">> backup verificado: $DEST"