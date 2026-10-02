#!/system/bin/sh
# ============================================================
# fix-elogind-chroot.sh
# Activa elogind/logind no chroot Android (apos stubs dinit).
# Antes falhava no early-boot; com local.target stub + dbus OK, arranca.
#
# su -c /data/linux/fix-elogind-chroot.sh
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
mkdir -p /etc/dinit.d/boot.d /run/systemd /var/log/dinit /etc/elogind

# garantir local.target stub (elogind depends-on)
if [ ! -f /etc/dinit.d/local.target ] || ! grep -q "chroot Android" /etc/dinit.d/local.target 2>/dev/null; then
  if [ -f /etc/dinit.d/local.target ] && [ ! -f /etc/dinit.d/local.target.bak-chroot ]; then
    cp /etc/dinit.d/local.target /etc/dinit.d/local.target.bak-chroot
  fi
  cat > /etc/dinit.d/local.target <<EOF
# chroot Android — stub para deps de elogind/desktop
type         = scripted
command      = /bin/true
restart      = false
EOF
fi

# elogind: sem run-in-cgroup; deps minimas
if [ -f /etc/dinit.d/elogind ]; then
  [ -f /etc/dinit.d/elogind.bak-chroot ] || cp /etc/dinit.d/elogind /etc/dinit.d/elogind.bak-chroot
fi
cat > /etc/dinit.d/elogind <<EOF
# chroot Android — sessao/login1 via dbus
type               = process
command            = /usr/lib/dinit/dbus-wait-for -s -f 4 -n org.freedesktop.login1 /usr/lib/elogind/elogind
smooth-recovery    = true
depends-on         = dbus
depends-on         = local.target
waits-for          = dbus
before             = logind
ready-notification = pipefd:4
restart            = true
logfile            = /var/log/dinit/elogind.log
EOF

# logind = alias interno
cat > /etc/dinit.d/logind <<EOF
type       = internal
depends-on = elogind
EOF

# config logind mais tolerante a chroot (sem VTs)
mkdir -p /etc/elogind
if [ -f /etc/elogind/logind.conf ]; then
  [ -f /etc/elogind/logind.conf.bak-chroot ] || cp /etc/elogind/logind.conf /etc/elogind/logind.conf.bak-chroot
fi
cat > /etc/elogind/logind.conf <<EOF
[Login]
NAutoVTs=0
ReserveVT=0
KillUserProcesses=no
HandlePowerKey=ignore
HandleSuspendKey=ignore
HandleHibernateKey=ignore
HandleLidSwitch=ignore
IdleAction=ignore
EOF

# activar no boot (depois de dbus)
ln -sfn ../dbus /etc/dinit.d/boot.d/dbus
ln -sfn ../elogind /etc/dinit.d/boot.d/elogind
ln -sfn ../logind /etc/dinit.d/boot.d/logind

# arrancar agora
dinitctl reload local.target 2>/dev/null || true
dinitctl reload elogind 2>/dev/null || true
dinitctl reload logind 2>/dev/null || true

dinitctl start dbus 2>/dev/null || true
sleep 1
dinitctl start local.target 2>/dev/null || true
dinitctl start elogind
sleep 1
dinitctl start logind 2>/dev/null || true

echo "=== status ==="
dinitctl status dbus || true
dinitctl status elogind || true
dinitctl status logind || true
echo "=== runtime ==="
ls -la /run/systemd/seats /run/systemd/sessions 2>/dev/null || true
busctl status org.freedesktop.login1 2>/dev/null | head -n 8 || \
  dbus-send --system --print-reply --dest=org.freedesktop.login1 \
    /org/freedesktop/login1 org.freedesktop.DBus.Peer.Ping 2>&1 | head -n 5 || true
echo "=== boot.d ==="
ls -la /etc/dinit.d/boot.d
'

echo
echo "OK — corre: /data/linux/linux-status.sh"
echo "  queres [ok] elogind"
