#!/system/bin/sh
# ============================================================
# fix-sshd-chroot.sh — sshd no chroot Android (apos stubs dinit)
#
# Factos observados no device:
#   - :2222 fica presa num sshd filho do dinit, com o unit em STOPPED
#   - matar esse pid em ciclo nao resolve: o dinit exec outro no lugar
#   - pkill -f "sshd-chroot-start" MATA este script (cmdline do sh -c)
#   - dinitctl stop --force derrubaria o boot e os outros servicos
#
# Fluxo:
#   1) config + wrapper + unit
#   2) se dinit STARTED e a porta escuta → OK
#   3) senao: unload do sshd (deixa de haver respawn), SIGKILL de TODOS
#      os processos com a porta aberta, uma vez, depois start
#
# su -c /data/linux/fix-sshd-chroot.sh
# ============================================================
set -e

. /data/linux/common.sh 2>/dev/null || . "$(dirname "$0")/common.sh"

if [ ! -f "$PIDF" ] || ! container_vivo "$(cat "$PIDF")"; then
  echo "!! container parado — /data/linux/linux-start.sh"
  exit 1
fi

PID=$(cat "$PIDF")
NSARGS=$(nsenter_ns_args "$PID")

# shellcheck disable=SC2086
$BB nsenter $NSARGS -- $BB chroot "$ROOT" /usr/bin/env -i \
  PATH=/usr/bin:/bin:/usr/sbin:/sbin HOME=/root LANG=C.UTF-8 \
  /bin/sh -c '
set -e

SSHD_PORT=${SSHD_PORT:-2222}
SSHD_UNIT=${SSHD_UNIT:-/etc/dinit.d/sshd}
SSHD_BOOT_LINK=${SSHD_BOOT_LINK:-/etc/dinit.d/boot.d/sshd}

port_listeners() {
  echo "=== porta :$SSHD_PORT — quem usa ==="
  if command -v ss >/dev/null 2>&1; then
    ss -lntp 2>/dev/null | grep -E ":${SSHD_PORT}\\b" || echo "(ss: nada em :$SSHD_PORT)"
  fi
  if command -v fuser >/dev/null 2>&1; then
    echo -n "fuser: "
    fuser -v "${SSHD_PORT}/tcp" 2>&1 || echo "(livre)"
  fi
  if command -v pgrep >/dev/null 2>&1; then
    echo "pgrep -x sshd:"
    pgrep -a -x sshd 2>/dev/null || echo "(nenhum)"
  fi
}

port_in_use() {
  if command -v ss >/dev/null 2>&1; then
    ss -lnt 2>/dev/null | grep -qE ":${SSHD_PORT}\\b" && return 0
  fi
  hex=$(printf "%04X" "$SSHD_PORT")
  awk -v h="$hex" "NR>1 && \$4==\"0A\" { n=split(\$2,a,\":\"); if (toupper(a[n])==h) found=1 } END { exit !found }" \
    /proc/net/tcp /proc/net/tcp6 2>/dev/null && return 0
  return 1
}

dinit_sshd_state() {
  dinitctl is-started sshd 2>/dev/null | grep -Eo "STARTED|STARTING|STOPPED|STOPPING" | head -n 1 || true
}

proc_ppid() {
  sed -n "s/^PPid:[[:space:]]*//p" "/proc/$1/status" 2>/dev/null || true
}

proc_comm() {
  cat "/proc/$1/comm" 2>/dev/null || true
}

# Qualquer processo com o socket de escuta, nao so comm=sshd.
pids_on_port_proc() {
  hex=$(printf "%04X" "$SSHD_PORT")
  inodes=$(awk -v h="$hex" "NR>1 && \$4==\"0A\" { n=split(\$2,a,\":\"); if (toupper(a[n])==h && \$10 != 0) print \$10 }" \
    /proc/net/tcp /proc/net/tcp6 2>/dev/null | sort -u)
  [ -n "$inodes" ] || return 0
  for d in /proc/[0-9]*; do
    pid=${d##*/}
    case "$pid" in
      *[!0-9]*) continue ;;
    esac
    matched=0
    for fd in "$d"/fd/*; do
      [ "$matched" = 1 ] && break
      link=$(readlink "$fd" 2>/dev/null || true)
      case "$link" in
        socket:\[*)
          ino=${link#socket:[}
          ino=${ino%]}
          for want in $inodes; do
            if [ "$ino" = "$want" ]; then
              echo "$pid"
              matched=1
              break
            fi
          done
          ;;
      esac
    done
  done
}

skip_pid() {
  case "$1" in
    ""|*[!0-9]*|1|$$|$PPID) return 0 ;;
  esac
  case "$(proc_comm "$1")" in
    dinit|systemd|init) return 0 ;;
  esac
  return 1
}

port_pids() {
  found=""
  if command -v ss >/dev/null 2>&1; then
    found=$(ss -lntp 2>/dev/null | grep -E ":${SSHD_PORT}\\b" | sed -n "s/.*pid=\\([0-9][0-9]*\\).*/\\1/p")
  fi
  if command -v fuser >/dev/null 2>&1; then
    found="$found $(fuser "${SSHD_PORT}/tcp" 2>/dev/null)"
  fi
  found="$found $(pids_on_port_proc)"
  for p in $found; do
    skip_pid "$p" && continue
    echo "$p"
  done | sort -u
}

install_real_wrapper() {
  cat > /usr/local/sbin/sshd-chroot-start <<EOF
#!/bin/sh
mkdir -p /var/empty /run/sshd /var/log/dinit
chmod 755 /var/empty /run/sshd
find /var/empty -mindepth 1 -maxdepth 1 -exec rm -rf {} + 2>/dev/null || true
/usr/bin/ssh-keygen -A >/dev/null 2>&1 || true
exec $SSHD_BIN -D -e
EOF
  chmod 755 /usr/local/sbin/sshd-chroot-start
}

write_sshd_unit() {
  mode=$1
  if [ "$mode" = "false" ]; then
    cat > "$SSHD_UNIT" <<EOF
type            = process
command         = /usr/local/sbin/sshd-chroot-start
restart         = false
smooth-recovery = false
logfile         = /var/log/dinit/sshd.log
EOF
    rm -f "$SSHD_BOOT_LINK"
    return 0
  fi
  cat > "$SSHD_UNIT" <<EOF
type            = process
command         = /usr/local/sbin/sshd-chroot-start
smooth-recovery = true
restart         = true
logfile         = /var/log/dinit/sshd.log
EOF
  mkdir -p "$(dirname "$SSHD_BOOT_LINK")"
  ln -sfn ../sshd "$SSHD_BOOT_LINK"
}

kill_port_pids() {
  pids=$(port_pids)
  [ -n "$pids" ] || return 0
  echo ">> SIGKILL na porta :$SSHD_PORT: $pids"
  for p in $pids; do
    echo ">> kill $p ($(proc_comm "$p")) pai=$(proc_ppid "$p") $(proc_comm "$(proc_ppid "$p")")"
    kill -9 "$p" 2>/dev/null || true
  done
  if command -v fuser >/dev/null 2>&1; then
    fuser -k -KILL "${SSHD_PORT}/tcp" >/dev/null 2>&1 || true
  fi
}

# Unload primeiro: sem o servico carregado, o dinit nao cria outro sshd.
free_port() {
  echo ">> unload sshd para o kill nao ser reposto"
  write_sshd_unit false
  dinitctl disable sshd 2>/dev/null || true
  dinitctl stop sshd 2>/dev/null || true
  dinitctl unload sshd 2>/dev/null || true
  kill_port_pids
  sleep 1
  if port_in_use; then
    kill_port_pids
    sleep 1
  fi
  if port_in_use; then
    echo "!! porta :$SSHD_PORT ainda ocupada"
    port_listeners
    return 1
  fi
  echo ">> porta :$SSHD_PORT livre"
  return 0
}

ensure_openssh() {
  if [ -x /usr/bin/sshd ] || command -v sshd >/dev/null 2>&1; then
    return 0
  fi
  echo ">> openssh ausente — pacman..."
  pacman -Sy --noconfirm --needed openssh openssh-dinit 2>/tmp/sshd-pacman.err || {
    echo "!! pacman openssh falhou:"; cat /tmp/sshd-pacman.err 2>/dev/null || true
    exit 1
  }
  [ -x /usr/bin/sshd ] || { echo "!! sem /usr/bin/sshd"; exit 1; }
}

ensure_openssh
SSHD_BIN=/usr/bin/sshd
[ -x "$SSHD_BIN" ] || SSHD_BIN=$(command -v sshd)

mkdir -p /etc/dinit.d/boot.d /var/log/dinit /run/sshd /etc/ssh /usr/local/sbin /var/empty
chmod 755 /var/empty /run/sshd
find /var/empty -mindepth 1 -maxdepth 1 -exec rm -rf {} + 2>/dev/null || true

if ! id sshd >/dev/null 2>&1; then
  useradd -r -d /var/empty -s /usr/bin/nologin -c "Privilege-separated SSH" sshd 2>/dev/null || true
fi
if ! id sshd >/dev/null 2>&1; then
  grep -q "^sshd:" /etc/passwd 2>/dev/null || \
    echo "sshd:x:74:74:Privilege-separated SSH:/var/empty:/usr/bin/nologin" >> /etc/passwd
  grep -q "^sshd:" /etc/group 2>/dev/null || echo "sshd:x:74:" >> /etc/group
fi
for u in root sshd; do
  id "$u" >/dev/null 2>&1 || continue
  usermod -aG aid_inet,aid_net_raw "$u" 2>/dev/null || true
done

if [ -f /etc/ssh/sshd_config ]; then
  [ -f /etc/ssh/sshd_config.bak-chroot ] || cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak-chroot
else
  touch /etc/ssh/sshd_config
fi
sed -i "s/^#\\?Port .*/Port $SSHD_PORT/" /etc/ssh/sshd_config
grep -q "^Port $SSHD_PORT" /etc/ssh/sshd_config || echo "Port $SSHD_PORT" >> /etc/ssh/sshd_config
sed -i "s/^#\\?PermitRootLogin .*/PermitRootLogin yes/" /etc/ssh/sshd_config
grep -q "^PermitRootLogin " /etc/ssh/sshd_config || echo "PermitRootLogin yes" >> /etc/ssh/sshd_config
sed -i "s/^#\\?PasswordAuthentication .*/PasswordAuthentication yes/" /etc/ssh/sshd_config
grep -q "^PasswordAuthentication" /etc/ssh/sshd_config || echo "PasswordAuthentication yes" >> /etc/ssh/sshd_config
sed -i "s/^#\\?UsePAM .*/UsePAM no/" /etc/ssh/sshd_config
grep -q "^UsePAM " /etc/ssh/sshd_config || echo "UsePAM no" >> /etc/ssh/sshd_config
sed -i "s/^#\\?PidFile .*/PidFile \\/run\\/sshd.pid/" /etc/ssh/sshd_config
grep -q "^PidFile " /etc/ssh/sshd_config || echo "PidFile /run/sshd.pid" >> /etc/ssh/sshd_config

ssh-keygen -A >/dev/null 2>&1 || true

install_real_wrapper

if [ -f "$SSHD_UNIT" ] && [ ! -f "${SSHD_UNIT}.bak-chroot" ]; then
  cp "$SSHD_UNIT" "${SSHD_UNIT}.bak-chroot"
fi
write_sshd_unit true

if ! $SSHD_BIN -t 2>/tmp/sshd-t.err; then
  echo "!! sshd -t falhou:"; cat /tmp/sshd-t.err; exit 1
fi

echo ">> diagnostico inicial"
port_listeners
dinitctl status sshd 2>&1 || true

# STARTING ainda nao e orfao — esperar antes de matar o listener.
i=0
st=""
while [ "$i" -lt 5 ]; do
  st=$(dinit_sshd_state)
  echo "dinit estado: ${st:-?}"
  if [ "$st" = "STARTED" ] && port_in_use; then
    echo ">> OK — dinit STARTED + porta :$SSHD_PORT"
    dinitctl status sshd || true
    exit 0
  fi
  if [ "$st" != "STARTING" ] && [ "$st" != "STOPPING" ]; then
    break
  fi
  i=$((i + 1))
  sleep 1
done

if [ "$st" = "STARTED" ]; then
  echo ">> dinit STARTED mas porta livre — restart"
  dinitctl restart sshd 2>/dev/null || dinitctl stop sshd 2>/dev/null || true
  sleep 1
  st=$(dinit_sshd_state)
  if [ "$st" = "STARTED" ] && port_in_use; then
    echo ">> OK — dinit STARTED + porta :$SSHD_PORT"
    dinitctl status sshd || true
    exit 0
  fi
fi

# Porta presa e dinit nao esta STARTED: unload + matar quem tem a porta.
if port_in_use; then
  echo ">> porta ocupada sem dinit STARTED — a terminar quem usa :$SSHD_PORT"
  if ! free_port; then
    exit 1
  fi
else
  echo ">> porta :$SSHD_PORT livre"
  dinitctl stop sshd 2>/dev/null || true
fi

install_real_wrapper
write_sshd_unit true
dinitctl enable sshd 2>/dev/null || true

echo ">> dinitctl start sshd"
dinitctl start sshd >/tmp/sshd-start.out 2>/tmp/sshd-start.err &
start_pid=$!

i=0
while [ "$i" -lt 15 ]; do
  if ! kill -0 "$start_pid" 2>/dev/null; then
    wait "$start_pid" 2>/dev/null || true
    break
  fi
  sleep 1
  i=$((i + 1))
done

if kill -0 "$start_pid" 2>/dev/null; then
  echo "!! dinitctl start nao terminou"
  kill -9 "$start_pid" 2>/dev/null || true
fi

i=0
while [ "$i" -lt 12 ]; do
  if dinitctl is-started sshd >/dev/null 2>&1 && port_in_use; then
    break
  fi
  i=$((i + 1))
  sleep 1
done

echo "=== resultado ==="
dinitctl status sshd || true
port_listeners
tail -n 15 /var/log/dinit/sshd.log 2>/dev/null || true

if ! dinitctl is-started sshd >/dev/null 2>&1; then
  echo "!! dinit ainda nao marca sshd started"
  exit 1
fi

if ! port_in_use; then
  echo "!! dinit started mas :$SSHD_PORT nao escuta"
  exit 1
fi

echo "OK — sshd ativo sob dinit"
exit 0
'

echo
echo "OK — sshd sob dinit (porta 2222)"
echo "  corre: /data/linux/linux-status.sh"
