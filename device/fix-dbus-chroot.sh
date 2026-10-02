#!/system/bin/sh
# ============================================================
# fix-dbus-chroot.sh — dbus sem run-in-cgroup (chroot Android)
# Alinhado a fix-elogind-chroot.sh (common.sh + nsenter + /bin/sh).
#
# su -c /data/linux/fix-dbus-chroot.sh
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

# backup
for f in dbus dbus-pre elogind; do
  [ -f /etc/dinit.d/$f ] || continue
  [ -f /etc/dinit.d/$f.bak-chroot ] || cp /etc/dinit.d/$f /etc/dinit.d/$f.bak-chroot
done

# dbus: remover run-in-cgroup (falha no cgroup do Android)
if [ ! -f /etc/dinit.d/dbus ]; then
  echo "!! /etc/dinit.d/dbus ausente"
  exit 1
fi
grep -v "^run-in-cgroup" /etc/dinit.d/dbus > /tmp/dbus.new
mv /tmp/dbus.new /etc/dinit.d/dbus

# dbus-pre: stop-command usa sv-cg — simplificar
cat > /etc/dinit.d/dbus-pre <<EOF
type         = scripted
command      = /usr/lib/dinit/pre/dbus
stop-command = /bin/true
after        = local.target
restart      = false
EOF

# dirs runtime
mkdir -p /run/dbus /var/lib/dbus /var/log/dinit /etc/dinit.d/boot.d
chmod 755 /run/dbus

# machine-id se faltar
if [ ! -s /etc/machine-id ]; then
  if command -v dbus-uuidgen >/dev/null 2>&1; then
    dbus-uuidgen --ensure=/etc/machine-id
  else
    cat /proc/sys/kernel/random/uuid | tr -d - > /etc/machine-id
  fi
fi

ln -sfn ../dbus /etc/dinit.d/boot.d/dbus

# reload descritores e arrancar
dinitctl reload dbus 2>/dev/null || true
dinitctl reload dbus-pre 2>/dev/null || true
dinitctl reload elogind 2>/dev/null || true

dinitctl stop logind 2>/dev/null || true
dinitctl stop elogind 2>/dev/null || true
dinitctl stop dbus 2>/dev/null || true
dinitctl stop dbus-pre 2>/dev/null || true

dinitctl start dbus-pre
dinitctl start dbus
sleep 1
dinitctl start elogind 2>/dev/null || true
dinitctl start logind 2>/dev/null || true

echo "=== status ==="
dinitctl status dbus || true
dinitctl status elogind || true
dinitctl status logind || true
ls -la /run/dbus/ 2>/dev/null || true
echo "=== dbus socket ==="
if [ -S /run/dbus/system_bus_socket ]; then
  ls -l /run/dbus/system_bus_socket
else
  echo "(sem socket)"
  echo "!! dbus nao criou /run/dbus/system_bus_socket"
  exit 1
fi
if ! dinitctl is-started dbus >/dev/null 2>&1; then
  echo "!! dbus nao esta started"
  exit 1
fi
'

echo
echo "OK — dbus + socket"
echo "  corre: /data/linux/linux-status.sh"
