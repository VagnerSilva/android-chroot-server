#!/system/bin/sh
# ============================================================
# artix-user.sh — criar / remover utilizador no chroot Artix
#
# Criar:
#   /data/linux/artix-user.sh create <user> <senha>
#   /data/linux/artix-user.sh --create <user> <senha>
#
# Remover:
#   /data/linux/artix-user.sh remove <user>
#   /data/linux/artix-user.sh --remove <user>
#
# Opcional: ARTIX_SUDO=1 para adicionar ao grupo wheel/sudo
# ============================================================
set -e

. /data/linux/common.sh 2>/dev/null || . "$(dirname "$0")/common.sh"

usage() {
  cat <<'EOF'
uso:
  artix-user.sh create <user> <senha>
  artix-user.sh passwd <user> <senha>
  artix-user.sh sudo <user>          # dar sudo (wheel + sudoers.d)
  artix-user.sh nosudo <user>        # retirar sudo
  artix-user.sh remove <user>

senha com caracteres especiais — usa aspas simples:
  artix-user.sh passwd alice 'p@ss$w0rd!#%'

ou stdin (mais seguro, qualquer caractere):
  artix-user.sh create alice -
  artix-user.sh passwd alice -

ou variavel:
  ARTIX_PASS='p@ss$#' artix-user.sh passwd alice

criar ja com sudo:
  ARTIX_SUDO=1 artix-user.sh create alice 'senha'

opcoes: --create / --passwd / --sudo / --nosudo / --remove
EOF
  exit 1
}

# Le senha de: arg, ARTIX_PASS, ou stdin se arg for "-" / ausente com ARTIX_PASS
read_password() {
  # $1 = senha passada na CLI (pode ser "-" )
  RAW="$1"
  if [ -n "$ARTIX_PASS" ]; then
    USER_PASS="$ARTIX_PASS"
    return 0
  fi
  if [ "$RAW" = "-" ] || [ "$RAW" = "--stdin" ]; then
    if [ -t 0 ]; then
      printf 'senha: ' >&2
      stty -echo 2>/dev/null || true
      IFS= read -r USER_PASS
      stty echo 2>/dev/null || true
      printf '\n' >&2
    else
      IFS= read -r USER_PASS
    fi
    [ -n "$USER_PASS" ] || { echo "!! senha vazia"; exit 1; }
    return 0
  fi
  if [ -z "$RAW" ]; then
    echo "!! falta senha (usa aspas, '-' para stdin, ou ARTIX_PASS=...)"
    exit 1
  fi
  USER_PASS="$RAW"
}

ACTION=""
USER_NAME=""
USER_PASS=""

case "$1" in
  create|--create|-c)
    ACTION=create
    USER_NAME="$2"
    [ -n "$USER_NAME" ] || usage
    read_password "$3"
    ;;
  passwd|--passwd|password|--password|setpass)
    ACTION=passwd
    USER_NAME="$2"
    [ -n "$USER_NAME" ] || usage
    read_password "$3"
    ;;
  remove|--remove|-r|delete|--delete|-d)
    ACTION=remove
    USER_NAME="$2"
    [ -n "$USER_NAME" ] || usage
    ;;
  sudo|--sudo|grant-sudo)
    ACTION=sudo
    USER_NAME="$2"
    [ -n "$USER_NAME" ] || usage
    ;;
  nosudo|--nosudo|revoke-sudo)
    ACTION=nosudo
    USER_NAME="$2"
    [ -n "$USER_NAME" ] || usage
    ;;
  -h|--help|"")
    usage
    ;;
  *)
    echo "!! acao desconhecida: $1"
    usage
    ;;
esac

# utilizadores de sistema — nao mexer
case "$USER_NAME" in
  root|bin|daemon|nobody|alpm|dbus|sshd|systemd-*)
    echo "!! utilizador reservado: $USER_NAME"
    exit 1
    ;;
esac

if [ ! -f "$PIDF" ] || ! container_vivo "$(cat "$PIDF")"; then
  echo "!! container parado. rode: /data/linux/linux-start.sh"
  exit 1
fi

PID=$(cat "$PIDF")
NSARGS=$(nsenter_ns_args "$PID")

run_chroot() {
  # shellcheck disable=SC2086
  $BB nsenter $NSARGS -- \
    $BB chroot "$ROOT" /usr/bin/env -i \
      HOME=/root TERM=linux LANG=C.UTF-8 \
      PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
      "$@"
}

ensure_aid_groups() {
  run_chroot /bin/sh -c '
    if ! grep -q "^aid_inet:" /etc/group 2>/dev/null; then
      cat >> /etc/group <<EOF
aid_bt_admin:x:3001:
aid_bt:x:3002:
aid_inet:x:3003:
aid_net_raw:x:3004:
aid_net_admin:x:3005:
aid_sdcard_rw:x:1015:
aid_media_rw:x:1023:
aid_everybody:x:9997:
EOF
    fi
  '
}

if [ "$ACTION" = create ]; then
  echo ">> criando utilizador: $USER_NAME"
  ensure_aid_groups

  # shellcheck disable=SC2086
  $BB nsenter $NSARGS -- \
    $BB chroot "$ROOT" /usr/bin/env -i \
      HOME=/root TERM=linux LANG=C.UTF-8 \
      ARTIX_NEW_PASS="$USER_PASS" \
      ARTIX_SUDO="${ARTIX_SUDO:-0}" \
      PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
      /bin/sh -c '
        U="'"$USER_NAME"'"
        if id "$U" >/dev/null 2>&1; then
          echo "!! utilizador ja existe: $U"
          echo "   para mudar senha: artix-user.sh passwd $U <senha>"
          exit 1
        fi
        useradd -m -s /bin/bash "$U" 2>/dev/null \
          || useradd -m -s /bin/sh "$U"
        # Artix/Arch: passwd NAO le stdin — usar chpasswd
        printf "%s:%s\n" "$U" "$ARTIX_NEW_PASS" | chpasswd
        usermod -aG aid_inet,aid_net_raw,aid_sdcard_rw "$U" 2>/dev/null || true
        if [ "$ARTIX_SUDO" = 1 ]; then
          getent group wheel >/dev/null && usermod -aG wheel "$U"
          getent group sudo >/dev/null && usermod -aG sudo "$U"
          if [ -d /etc/sudoers.d ]; then
            echo "$U ALL=(ALL:ALL) ALL" > "/etc/sudoers.d/$U"
            chmod 440 "/etc/sudoers.d/$U"
          fi
        fi
        # confirma que ha hash (nao !! nem *)
        HASH=$(getent shadow "$U" | cut -d: -f2)
        case "$HASH" in
          ""|"!"|"!!"|"*"|"!*"|"x")
            echo "!! senha NAO foi gravada (hash=$HASH)"
            exit 1
            ;;
        esac
        echo ">> criado: $U (uid=$(id -u $U)) senha OK"
        id "$U"
        echo ">> home: /home/$U   (cd ~  ou  cd /home/$U)"
        echo ">> /root e so do utilizador root — usuarios normais nao entram la"
        ls -ld "/home/$U"
      '
  echo ">> SSH: ssh -p 2222 ${USER_NAME}@<ip>"
  echo ">> shell: /data/linux/linux-shell.sh ${USER_NAME}"
  exit 0
fi

if [ "$ACTION" = passwd ] || [ "$ACTION" = password ] || [ "$ACTION" = setpass ]; then
  echo ">> a definir senha de: $USER_NAME"
  # shellcheck disable=SC2086
  $BB nsenter $NSARGS -- \
    $BB chroot "$ROOT" /usr/bin/env -i \
      HOME=/root TERM=linux LANG=C.UTF-8 \
      ARTIX_NEW_PASS="$USER_PASS" \
      PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
      /bin/sh -c '
        U="'"$USER_NAME"'"
        if ! id "$U" >/dev/null 2>&1; then
          echo "!! utilizador nao existe: $U"
          exit 1
        fi
        printf "%s:%s\n" "$U" "$ARTIX_NEW_PASS" | chpasswd
        HASH=$(getent shadow "$U" | cut -d: -f2)
        case "$HASH" in
          ""|"!"|"!!"|"*"|"!*"|"x")
            echo "!! senha NAO foi gravada"
            exit 1
            ;;
        esac
        echo ">> senha atualizada: $U"
      '
  exit 0
fi

if [ "$ACTION" = remove ]; then
  echo ">> removendo utilizador: $USER_NAME"
  run_chroot /bin/sh -c "
    U='$USER_NAME'
    if ! id \"\$U\" >/dev/null 2>&1; then
      echo \"!! utilizador nao existe: \$U\"
      exit 1
    fi
    pkill -u \"\$U\" 2>/dev/null || true
    sleep 1
    userdel -r \"\$U\" 2>/dev/null || userdel \"\$U\"
    rm -f \"/etc/sudoers.d/\$U\"
    echo \">> removido: \$U\"
  "
  exit 0
fi

if [ "$ACTION" = sudo ]; then
  echo ">> a dar sudo a: $USER_NAME"
  run_chroot /bin/sh -c '
    U="'"$USER_NAME"'"
    if ! id "$U" >/dev/null 2>&1; then
      echo "!! utilizador nao existe: $U"
      exit 1
    fi
    command -v sudo >/dev/null 2>&1 || {
      echo "!! pacote sudo em falta — instale como root: pacman -S sudo"
      exit 1
    }
    getent group wheel >/dev/null && usermod -aG wheel "$U"
    getent group sudo >/dev/null && usermod -aG sudo "$U"
    mkdir -p /etc/sudoers.d
    echo "$U ALL=(ALL:ALL) ALL" > "/etc/sudoers.d/$U"
    chmod 440 "/etc/sudoers.d/$U"
    # validar sintaxe
    if command -v visudo >/dev/null 2>&1; then
      visudo -cf "/etc/sudoers.d/$U" || {
        rm -f "/etc/sudoers.d/$U"
        echo "!! sudoers invalido"
        exit 1
      }
    fi
    echo ">> sudo OK: $U"
    id "$U"
    ls -l "/etc/sudoers.d/$U"
  '
  exit 0
fi

if [ "$ACTION" = nosudo ]; then
  echo ">> a retirar sudo de: $USER_NAME"
  run_chroot /bin/sh -c '
    U="'"$USER_NAME"'"
    if ! id "$U" >/dev/null 2>&1; then
      echo "!! utilizador nao existe: $U"
      exit 1
    fi
    gpasswd -d "$U" wheel 2>/dev/null || true
    gpasswd -d "$U" sudo 2>/dev/null || true
    rm -f "/etc/sudoers.d/$U"
    echo ">> sudo removido: $U"
  '
  exit 0
fi
