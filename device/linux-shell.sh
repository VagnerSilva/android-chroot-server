#!/system/bin/sh
# ============================================================
# linux-shell.sh - entra no container (nsenter) ou chroot temp
#
# Root (padrao):
#   /data/linux/linux-shell.sh
#
# Como utilizador (home em /home/<user>):
#   /data/linux/linux-shell.sh <user>
#   /data/linux/linux-shell.sh --user <user>
#   /data/linux/linux-shell.sh -u <user>
#   SHELL_USER=<user> /data/linux/linux-shell.sh
#
# Comando unico:
#   SHELL_CMD='id; pwd' /data/linux/linux-shell.sh --user alice
# ============================================================

. /data/linux/common.sh 2>/dev/null || . "$(dirname "$0")/common.sh"

ensure_dirs

SHELL_USER="${SHELL_USER:-}"
while [ $# -gt 0 ]; do
  case "$1" in
    -u|--user)
      SHELL_USER="$2"
      shift 2
      ;;
    -h|--help)
      cat <<'EOF'
uso:
  linux-shell.sh              # root, HOME=/root
  linux-shell.sh <user>       # login em /home/<user>
  linux-shell.sh -u <user>
  SHELL_USER=<user> linux-shell.sh
  SHELL_CMD='...' linux-shell.sh [-u user]
EOF
      exit 0
      ;;
    -*)
      echo "!! opcao desconhecida: $1"
      exit 1
      ;;
    *)
      # primeiro argumento sem - e o user
      if [ -z "$SHELL_USER" ]; then
        SHELL_USER="$1"
        shift
      else
        echo "!! argumento extra: $1"
        exit 1
      fi
      ;;
  esac
done

# shell de login (bash se existir)
if [ -x "$ROOT/bin/bash" ] || [ -x "$ROOT/usr/bin/bash" ]; then
  LOGIN_SH=/bin/bash
else
  LOGIN_SH=/bin/sh
fi

# comando a executar dentro da sessao
if [ -n "$SHELL_CMD" ]; then
  INNER_CMD="$SHELL_CMD"
else
  INNER_CMD="exec $LOGIN_SH -l"
fi

# monta o comando final: root ou su -l user
if [ -n "$SHELL_USER" ]; then
  if [ "$SHELL_USER" = root ]; then
    HOME_DIR=/root
    RUN_AS="cd /root && export HOME=/root USER=root LOGNAME=root; $INNER_CMD"
  else
    HOME_DIR="/home/$SHELL_USER"
    if [ -n "$SHELL_CMD" ]; then
      RUN_AS="su -l $SHELL_USER -c \"$SHELL_CMD\""
    else
      RUN_AS="exec su -l $SHELL_USER"
    fi
  fi
  echo ">> utilizador: $SHELL_USER (home $HOME_DIR)"
else
  SHELL_USER=root
  HOME_DIR=/root
  RUN_AS="cd /root && export HOME=/root USER=root LOGNAME=root; $INNER_CMD"
  echo ">> utilizador: root (home /root)"
fi

enter_alive() {
  PID=$(cat "$PIDF")
  NSARGS=$(nsenter_ns_args "$PID")
  echo ">> entrando no namespace (pid $PID, nsenter $NSARGS)"
  # shellcheck disable=SC2086
  # Com SHELL_CMD: nao fazer exec — o caller (ex. run-setup.sh) precisa continuar.
  # Propagar DISPLAY se definido (Zink/Vulkan X11 durante setup)
  _ENV_DISPLAY=
  [ -n "${DISPLAY:-}" ] && _ENV_DISPLAY="DISPLAY=$DISPLAY"
  if [ -n "$SHELL_CMD" ]; then
    # shellcheck disable=SC2086
    $BB nsenter $NSARGS -- \
      $BB chroot "$ROOT" /usr/bin/env -i \
        TERM="${TERM:-linux}" LANG=C.UTF-8 \
        PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
        $_ENV_DISPLAY \
        /bin/sh -c "$RUN_AS"
    return $?
  fi
  # shellcheck disable=SC2086
  exec $BB nsenter $NSARGS -- \
    $BB chroot "$ROOT" /usr/bin/env -i \
      TERM="${TERM:-linux}" LANG=C.UTF-8 \
      PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
      $_ENV_DISPLAY \
      /bin/sh -c "$RUN_AS"
}

enter_temp() {
  echo ">> container parado — chroot temporario de setup"
  mount_rootfs_rw || exit 1

  $BB mount --bind /dev "$ROOT/dev" 2>/dev/null
  mkdir -p "$ROOT/dev/pts" "$ROOT/dev/shm"
  $BB mount -t devpts -o gid=5,mode=620 devpts "$ROOT/dev/pts" 2>/dev/null
  $BB mount -t proc proc "$ROOT/proc" 2>/dev/null
  $BB mount -t sysfs sysfs "$ROOT/sys" 2>/dev/null
  $BB mount -t tmpfs -o mode=755 tmpfs "$ROOT/run" 2>/dev/null
  $BB mount -t tmpfs -o mode=1777 tmpfs "$ROOT/tmp" 2>/dev/null

  cleanup() {
    $BB umount "$ROOT/tmp" 2>/dev/null
    $BB umount "$ROOT/run" 2>/dev/null
    $BB umount "$ROOT/sys" 2>/dev/null
    $BB umount "$ROOT/proc" 2>/dev/null
    $BB umount "$ROOT/dev/pts" 2>/dev/null
    $BB umount "$ROOT/dev" 2>/dev/null
    $BB umount "$ROOT" 2>/dev/null
    for L in $($BB losetup -a 2>/dev/null | grep rootfs.img | cut -d: -f1); do
      $BB losetup -d "$L" 2>/dev/null
    done
  }
  trap cleanup EXIT INT TERM

  $BB chroot "$ROOT" /usr/bin/env -i \
    TERM="${TERM:-linux}" LANG=C.UTF-8 \
    PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
    /bin/sh -c "$RUN_AS"
}

# validar user se nao for root (precisa container ou imagem montada)
if [ "$SHELL_USER" != root ]; then
  if [ -f "$PIDF" ] && container_vivo "$(cat "$PIDF")"; then
    PID=$(cat "$PIDF")
    NSARGS=$(nsenter_ns_args "$PID")
    # shellcheck disable=SC2086
    if ! $BB nsenter $NSARGS -- $BB chroot "$ROOT" /usr/bin/id "$SHELL_USER" >/dev/null 2>&1; then
      echo "!! utilizador nao existe: $SHELL_USER"
      echo "   crie com: /data/linux/artix-user.sh create $SHELL_USER <senha>"
      exit 1
    fi
  elif [ -d "$ROOT/home/$SHELL_USER" ] || grep -q "^${SHELL_USER}:" "$ROOT/etc/passwd" 2>/dev/null; then
    :
  else
    # tenta montar so para validar
    if mount_rootfs_rw 2>/dev/null; then
      if ! grep -q "^${SHELL_USER}:" "$ROOT/etc/passwd" 2>/dev/null; then
        echo "!! utilizador nao existe: $SHELL_USER"
        $BB umount "$ROOT" 2>/dev/null
        exit 1
      fi
    fi
  fi
fi

if [ -f "$PIDF" ] && container_vivo "$(cat "$PIDF")"; then
  enter_alive
else
  enter_temp
fi
