#!/system/bin/sh
# ============================================================
# run-setup.sh — setup pos-install (sshd + dinit + dbus + elogind)
#
# Encadeia:
#   1) setup-artix.sh      (grupos, pacman, prep sshd/dbus — sem start)
#   2) fix-dinit-chroot.sh (stubs early-boot + unit sshd wrapper)
#   3) linux-stop + linux-start (stubs activos)
#   4) fix-sshd-chroot.sh  (start sshd :2222 — falha aqui se SSH nao subir)
#   5) fix-dbus-chroot.sh  (arranca dbus + socket)
#   6) fix-elogind-chroot.sh
#   7) (opcional) criar utilizador
#   8) SETUP_FULL=1 → GPU hybris + XFCE
#
# Uso (container ja a correr apos linux-start):
#   /data/linux/run-setup.sh
#   SETUP_FULL=1 /data/linux/run-setup.sh
#   CREATE_USER=1 ARTIX_USER=alice ARTIX_PASS='senha' /data/linux/run-setup.sh
#   CREATE_USER=0 /data/linux/run-setup.sh   # forca sem prompt (so nucleo)
#
# Env:
#   CREATE_USER=0|1   se omitido e TTY/tty → pergunta; sem TTY:
#                     SETUP_FULL=1 → exige ARTIX_* ou falha;
#                     SETUP_FULL=0 → CREATE_USER=0
#   ARTIX_USER        obrigatorio se CREATE_USER=1 (ou prompt)
#   ARTIX_PASS        senha (ou prompt com echo off)
#   ARTIX_SUDO        default 1 na criacao automatica
#   SETUP_FULL=0|1    default 0; 1 = GPU hybris + XFCE apos nucleo
#   SKIP_GPU=1        com SETUP_FULL=1: salta GPU hybris (so user + XFCE)
#   USER_PROMPT_DEFAULT=s|n  default do s/N (bootstrap usa s)
# ============================================================

. /data/linux/common.sh 2>/dev/null || . "$(dirname "$0")/common.sh"

SETUP_SRC=/data/linux/setup-artix.sh
[ -f "$SETUP_SRC" ] || SETUP_SRC="$(dirname "$0")/setup-artix.sh"
SETUP_FULL="${SETUP_FULL:-0}"
SKIP_GPU="${SKIP_GPU:-0}"
USER_PROMPT_DEFAULT="${USER_PROMPT_DEFAULT:-n}"

if [ ! -f "$SETUP_SRC" ]; then
  echo "!! setup-artix.sh nao encontrado — corre prepare.sh"
  exit 1
fi

# stdin TTY ou /dev/tty disponivel (adb su / terminal local)
have_tty() {
  [ -t 0 ] && return 0
  [ -c /dev/tty ] && return 0
  return 1
}

# ler linha: preferir /dev/tty se stdin nao for TTY
read_tty() {
  _prompt="$1"
  _var="$2"
  if [ -t 0 ]; then
    printf '%s' "$_prompt"
    IFS= read -r "$_var" || eval "$_var="
  elif [ -c /dev/tty ]; then
    printf '%s' "$_prompt" > /dev/tty
    IFS= read -r "$_var" < /dev/tty || eval "$_var="
  else
    eval "$_var="
    return 1
  fi
}

ensure_dirs
mount_rootfs_rw || exit 1

if [ ! -e "$ROOT/usr/lib/libstdc++.so.6" ] || [ ! -e "$ROOT/usr/lib/libgcc_s.so.1" ]; then
  echo "!! runtime GCC incompleto — rootfs inconsistente"
  echo "   YES=1 /data/linux/wipe-chroot.sh && /data/linux/bootstrap.sh"
  exit 1
fi

# --- 1) setup-artix dentro do chroot (prep; nao arranca sshd) ---
echo "============================================================"
echo " [1/7] setup-artix (pacman / grupos / prep sshd)"
echo "============================================================"
cp "$SETUP_SRC" "$ROOT/root/setup-artix.sh"
chmod 755 "$ROOT/root/setup-artix.sh"
strip_crlf "$ROOT/root/setup-artix.sh"

if [ ! -f "$PIDF" ] || ! container_vivo "$(cat "$PIDF")"; then
  echo ">> container parado — a subir..."
  sh /data/linux/linux-start.sh || exit 1
fi

export SHELL_CMD="/bin/sh /root/setup-artix.sh"
if ! sh /data/linux/linux-shell.sh; then
  echo "!! setup-artix falhou"
  exit 1
fi

# --- 2) stubs dinit (udev/fsck/…) + boot.d dbus/sshd/elogind ---
echo
echo "============================================================"
echo " [2/7] fix-dinit-chroot (stubs Android)"
echo "============================================================"
if [ -x /data/linux/fix-dinit-chroot.sh ]; then
  FIX_DINIT_QUIET=1 sh /data/linux/fix-dinit-chroot.sh || {
    echo "!! fix-dinit-chroot falhou"
    exit 1
  }
else
  echo "!! fix-dinit-chroot.sh ausente — prepare.sh incompleto"
  exit 1
fi

# --- 3) restart (stubs early-boot activos) ---
echo
echo "============================================================"
echo " [3/7] reiniciar container (stubs dinit)"
echo "============================================================"
if [ -f "$PIDF" ] && container_vivo "$(cat "$PIDF")"; then
  sh /data/linux/linux-stop.sh || true
fi
rmdir /data/linux/run/start.lock 2>/dev/null || true
sh /data/linux/linux-start.sh || {
  echo "!! linux-start falhou apos stubs dinit"
  echo "   YES=1 /data/linux/wipe-chroot.sh && /data/linux/bootstrap.sh"
  exit 1
}

# --- 4) sshd (ja com stubs; falhar aqui, nao mais tarde) ---
echo
echo "============================================================"
echo " [4/7] fix-sshd-chroot (start :2222)"
echo "============================================================"
if [ -x /data/linux/fix-sshd-chroot.sh ]; then
  sh /data/linux/fix-sshd-chroot.sh || {
    echo "!! fix-sshd-chroot falhou — SSH tem de subir neste passo"
    exit 1
  }
else
  echo "!! fix-sshd-chroot.sh ausente — prepare.sh incompleto"
  exit 1
fi

# --- 5) dbus ---
echo
echo "============================================================"
echo " [5/7] fix-dbus-chroot"
echo "============================================================"
if [ -x /data/linux/fix-dbus-chroot.sh ]; then
  sh /data/linux/fix-dbus-chroot.sh || {
    echo "!! fix-dbus-chroot falhou"
    exit 1
  }
else
  echo "!! fix-dbus-chroot.sh ausente"
  exit 1
fi

# --- 6) elogind ---
echo
echo "============================================================"
echo " [6/7] fix-elogind-chroot"
echo "============================================================"
if [ -x /data/linux/fix-elogind-chroot.sh ]; then
  sh /data/linux/fix-elogind-chroot.sh || {
    echo "!! fix-elogind-chroot falhou"
    exit 1
  }
else
  echo "!! fix-elogind-chroot.sh ausente"
  exit 1
fi

# --- 7) utilizador ---
CREATED_USER=""

prompt_user_creds() {
  if [ -z "${ARTIX_USER:-}" ]; then
    read_tty 'Nome do utilizador: ' ARTIX_USER || true
  fi
  if [ -z "${ARTIX_PASS:-}" ]; then
    if [ -t 0 ]; then
      printf 'Senha: '
      stty -echo 2>/dev/null || true
      IFS= read -r ARTIX_PASS || ARTIX_PASS=
      stty echo 2>/dev/null || true
      printf '\n'
      printf 'Confirmar senha: '
      stty -echo 2>/dev/null || true
      IFS= read -r _pass2 || _pass2=
      stty echo 2>/dev/null || true
      printf '\n'
    elif [ -c /dev/tty ]; then
      printf 'Senha: ' > /dev/tty
      stty -echo < /dev/tty 2>/dev/null || true
      IFS= read -r ARTIX_PASS < /dev/tty || ARTIX_PASS=
      stty echo < /dev/tty 2>/dev/null || true
      printf '\n' > /dev/tty
      printf 'Confirmar senha: ' > /dev/tty
      stty -echo < /dev/tty 2>/dev/null || true
      IFS= read -r _pass2 < /dev/tty || _pass2=
      stty echo < /dev/tty 2>/dev/null || true
      printf '\n' > /dev/tty
    else
      ARTIX_PASS=
      _pass2=
    fi
    if [ -z "$ARTIX_PASS" ]; then
      echo "!! senha vazia"
      exit 1
    fi
    if [ "$ARTIX_PASS" != "$_pass2" ]; then
      echo "!! senhas nao coincidem"
      exit 1
    fi
  fi
}

case "${CREATE_USER:-}" in
  0|1) ;; # explicito — sem prompt s/N
  *)
    if have_tty; then
      echo
      echo "============================================================"
      echo " [7/7] utilizador Artix"
      echo "============================================================"
      if [ "$USER_PROMPT_DEFAULT" = "s" ] || [ "$USER_PROMPT_DEFAULT" = "S" ]; then
        _hint='[S/n]'
      else
        _hint='[s/N]'
      fi
      read_tty "Criar utilizador agora? $_hint: " _ans || _ans=
      case "$_ans" in
        s|S|y|Y|sim|Sim|SIM|yes|Yes|YES) CREATE_USER=1 ;;
        n|N|nao|Nao|NAO|no|No|NO) CREATE_USER=0 ;;
        "")
          if [ "$USER_PROMPT_DEFAULT" = "s" ] || [ "$USER_PROMPT_DEFAULT" = "S" ]; then
            CREATE_USER=1
          else
            CREATE_USER=0
          fi
          ;;
        *) CREATE_USER=0 ;;
      esac
    else
      if [ "$SETUP_FULL" = "1" ]; then
        echo "!! SETUP_FULL=1 sem TTY: defina CREATE_USER=1 ARTIX_USER=<nome> ARTIX_PASS='senha'"
        echo "   Ex.: CREATE_USER=1 ARTIX_USER=alice ARTIX_PASS='senha' SETUP_FULL=1 $0"
        exit 1
      fi
      CREATE_USER=0
    fi
    ;;
esac

if [ "$CREATE_USER" = "1" ]; then
  echo
  echo "============================================================"
  echo " [7/7] criar utilizador"
  echo "============================================================"
  if [ -z "${ARTIX_USER:-}" ] && have_tty; then
    read_tty 'Nome do utilizador: ' ARTIX_USER || true
  fi
  if [ -z "${ARTIX_USER:-}" ]; then
    echo "!! CREATE_USER=1 exige ARTIX_USER=<nome>"
    echo "   Ex.: CREATE_USER=1 ARTIX_USER=alice ARTIX_PASS='senha' $0"
    exit 1
  fi
  if [ ! -x /data/linux/artix-user.sh ]; then
    echo "!! artix-user.sh ausente — prepare.sh incompleto"
    exit 1
  fi
  # ja existe? (re-run bootstrap / setup)
  if [ -d "$ROOT/home/$ARTIX_USER" ] || grep -q "^${ARTIX_USER}:" "$ROOT/etc/passwd" 2>/dev/null; then
    echo ">> utilizador ja existe: $ARTIX_USER — a saltar create"
    CREATED_USER="$ARTIX_USER"
  else
    if have_tty; then
      prompt_user_creds
    fi
    if [ -z "${ARTIX_PASS:-}" ]; then
      echo "!! CREATE_USER=1 exige ARTIX_PASS=<senha>"
      echo "   Ex.: CREATE_USER=1 ARTIX_USER=$ARTIX_USER ARTIX_PASS='senha' $0"
      exit 1
    fi
    ARTIX_SUDO="${ARTIX_SUDO:-1}" ARTIX_PASS="$ARTIX_PASS" \
      /data/linux/artix-user.sh create "$ARTIX_USER" - || {
      echo "!! falha ao criar utilizador: $ARTIX_USER"
      exit 1
    }
    CREATED_USER="$ARTIX_USER"
  fi
fi

# SETUP_FULL exige utilizador para XFCE
if [ "$SETUP_FULL" = "1" ]; then
  if [ -z "${ARTIX_USER:-}" ] && [ -z "$CREATED_USER" ]; then
    # tentar primeiro user em /home
    if [ -d "$ROOT/home" ]; then
      ARTIX_USER=$(ls -1 "$ROOT/home" 2>/dev/null | head -n1)
    fi
  fi
  [ -n "$CREATED_USER" ] && ARTIX_USER="$CREATED_USER"
  if [ -z "${ARTIX_USER:-}" ]; then
    echo "!! SETUP_FULL=1 exige utilizador (CREATE_USER=1 ARTIX_USER=… ou ja existente em /home)"
    exit 1
  fi

  echo
  echo "============================================================"
  if [ "$SKIP_GPU" = "1" ]; then
    echo " [+] GPU hybris — SKIP_GPU=1 (manual depois)"
    echo "============================================================"
    echo ">> a saltar run-setup-gpu-hybris"
    echo "   quando quiseres: /data/linux/run-setup-gpu-hybris.sh"
  else
    echo " [+] GPU hybris"
    echo "============================================================"
    if [ ! -x /data/linux/run-setup-gpu-hybris.sh ]; then
      echo "!! run-setup-gpu-hybris.sh ausente"
      exit 1
    fi
    sh /data/linux/run-setup-gpu-hybris.sh || {
      echo "!! setup GPU hybris falhou"
      exit 1
    }
  fi

  echo
  echo "============================================================"
  echo " [+] XFCE + Termux:X11"
  echo "============================================================"
  if [ ! -x /data/linux/run-setup-xfce.sh ]; then
    echo "!! run-setup-xfce.sh ausente"
    exit 1
  fi
  ARTIX_USER="$ARTIX_USER" sh /data/linux/run-setup-xfce.sh || {
    echo "!! setup XFCE falhou"
    exit 1
  }
fi

echo
echo "============================================================"
echo " setup completo — estado:"
echo "============================================================"
sh /data/linux/linux-status.sh 2>/dev/null || true

if [ -n "$CREATED_USER" ]; then
  NEXT_USER="$CREATED_USER"
  USER_HINT="utilizador criado: $CREATED_USER"
else
  NEXT_USER="${ARTIX_USER:-<user>}"
  USER_HINT="criar user (se ainda nao existir):
  CREATE_USER=1 ARTIX_USER=<user> ARTIX_PASS='senha' $0
  # ou: ARTIX_SUDO=1 /data/linux/artix-user.sh create <user> 'senha'"
fi

if [ "$SETUP_FULL" = "1" ]; then
  if [ "$SKIP_GPU" = "1" ]; then
    cat <<EOF

Proximos:
  /data/linux/x11-start.sh
  /data/linux/run-setup-gpu-hybris.sh   # GPU (manual — fora do bootstrap actual)
============================================================
EOF
  else
    cat <<EOF

Proximos:
  /data/linux/x11-start.sh
  # ou bootstrap completo: /data/linux/bootstrap.sh
============================================================
EOF
  fi
else
  cat <<EOF

Proximos (opcional):
  $USER_HINT
  ARTIX_USER=$NEXT_USER /data/linux/run-setup-xfce.sh
  /data/linux/x11-start.sh
  /data/linux/run-setup-gpu-hybris.sh
  # completo do zero: /data/linux/bootstrap.sh
============================================================
EOF
fi
