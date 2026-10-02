#!/system/bin/sh
# ============================================================
# fix-dinit-chroot.sh
# Artix dinit no Android: early-boot em /usr/lib/dinit.d (root-ro,
# udev, fsck, …) falha → boot derruba → unshare morre.
#
# Cria OVERRIDES em /etc/dinit.d/ (têm prioridade sobre /usr/lib).
#   su -c /data/linux/fix-dinit-chroot.sh
# ============================================================
set -e

. /data/linux/common.sh 2>/dev/null || . "$(dirname "$0")/common.sh"

ensure_dirs
mount_rootfs_rw || exit 1

INNER_FIX="$ROOT/root/fix-dinit-chroot-inner.sh"
mkdir -p "$ROOT/root"

cat > "$INNER_FIX" <<'INNER'
#!/bin/sh
# Corre DENTRO do chroot — overrides em /etc/dinit.d/
set -e
mkdir -p /etc/dinit.d/boot.d /var/log/dinit /run/dbus

stub() {
  name="$1"
  f="/etc/dinit.d/$name"
  # backup so da 1a vez se ja existia em /etc
  if [ -f "$f" ] && [ ! -f "$f.bak-chroot" ]; then
    cp "$f" "$f.bak-chroot"
  fi
  cat > "$f" <<EOF
# override chroot Android (fix-dinit-chroot) — ignora /usr/lib/dinit.d/$name
type         = scripted
command      = /bin/true
restart      = false
EOF
  echo "  stub $name"
}

# Critico: root-ro faz "mount -o remount,ro /" → exit 32 no chroot
# + toda a cadeia early/udev/fsck que depende disso
for s in \
  root-ro fsck-root fsck early-root-rw.target \
  early-prepare.target early-devices.target early-console.target \
  early-keyboard.target early-fs-pre.target early-fs-fstab.target \
  early-fs-local.target early-modules.target \
  udevd-early udevd udev-settle udev-trigger \
  tmpfiles-dev hwclock locale random-seed \
  cgroups modules kmod-static-nodes binfmt swap \
  agetty getty \
  pre-local.target
do
  stub "$s"
done

# targets internos sem deps de hardware
cat > /etc/dinit.d/local.target <<'EOF'
# chroot Android: sem rclocal / early-fs
type         = scripted
command      = /bin/true
restart      = false
EOF
echo "  override local.target"

cat > /etc/dinit.d/login.target <<'EOF'
# chroot Android: sem console/getty
type    = internal
restart = false
EOF
echo "  override login.target"

cat > /etc/dinit.d/network.target <<'EOF'
# chroot Android: rede = stack do Android (sem dhcpcd)
type    = internal
restart = false
EOF
echo "  override network.target"

cat > /etc/dinit.d/pre-network.target <<'EOF'
type    = internal
restart = false
EOF
echo "  override pre-network.target"

cat > /etc/dinit.d/system <<'EOF'
# chroot Android: system minimo
type       = internal
depends-on = network.target
waits-for.d = /etc/dinit.d/boot.d
EOF
echo "  override system"

cat > /etc/dinit.d/boot <<'EOF'
# chroot Android: boot = system + boot.d
type        = internal
depends-on  = system
waits-for.d = /etc/dinit.d/boot.d
EOF
echo "  override boot"

# dbus sem run-in-cgroup
if [ -f /etc/dinit.d/dbus ]; then
  [ -f /etc/dinit.d/dbus.bak-chroot ] || cp /etc/dinit.d/dbus /etc/dinit.d/dbus.bak-chroot
  grep -v '^run-in-cgroup' /etc/dinit.d/dbus > /tmp/dbus.new && mv /tmp/dbus.new /etc/dinit.d/dbus
  echo "  dbus: sem run-in-cgroup"
fi
if [ -f /etc/dinit.d/dbus-pre ]; then
  cat > /etc/dinit.d/dbus-pre <<'EOF'
type         = scripted
command      = /usr/lib/dinit/pre/dbus
stop-command = /bin/true
restart      = false
EOF
  echo "  dbus-pre simplificado"
fi

# sshd: stock depende de network.target / ssh-keygen frageis no chroot.
# Unit minimo sem deps — fix-sshd-chroot instala o wrapper e faz start.
if command -v sshd >/dev/null 2>&1 || [ -x /usr/bin/sshd ]; then
  mkdir -p /var/empty /run/sshd /usr/local/sbin
  chmod 755 /var/empty /run/sshd
  find /var/empty -mindepth 1 -maxdepth 1 -exec rm -rf {} + 2>/dev/null || true

  # wrapper idempotente (fix-sshd-chroot pode sobrescrever depois)
  if [ ! -x /usr/local/sbin/sshd-chroot-start ]; then
    cat > /usr/local/sbin/sshd-chroot-start <<'EOF'
#!/bin/sh
mkdir -p /var/empty /run/sshd /var/log/dinit
chmod 755 /var/empty /run/sshd
find /var/empty -mindepth 1 -maxdepth 1 -exec rm -rf {} + 2>/dev/null || true
/usr/bin/ssh-keygen -A >/dev/null 2>&1 || true
exec /usr/bin/sshd -D -e
EOF
    chmod 755 /usr/local/sbin/sshd-chroot-start
  fi

  if [ -f /etc/dinit.d/sshd ]; then
    [ -f /etc/dinit.d/sshd.bak-chroot ] || cp /etc/dinit.d/sshd /etc/dinit.d/sshd.bak-chroot
  fi
  cat > /etc/dinit.d/sshd <<'EOF'
# chroot Android — wrapper self-contained (sem network/ssh-keygen)
type            = process
command         = /usr/local/sbin/sshd-chroot-start
smooth-recovery = true
restart         = true
logfile         = /var/log/dinit/sshd.log
EOF
  echo "  override sshd (wrapper, sem deps)"
fi

# dhcpcd/wpa fora do boot (rede = Android)
rm -f /etc/dinit.d/boot.d/dhcpcd
rm -f /etc/dinit.d/boot.d/wpa_supplicant

# garantir sshd + dbus + elogind no boot
[ -f /etc/dinit.d/sshd ] && ln -sfn ../sshd /etc/dinit.d/boot.d/sshd
[ -f /etc/dinit.d/dbus ] && ln -sfn ../dbus /etc/dinit.d/boot.d/dbus
# elogind so se o unit existir — arranca apos stubs local.target
if [ -f /etc/dinit.d/elogind ] || [ -f /usr/lib/elogind/elogind ]; then
  # unit chroot-friendly (criado se so existir o stock)
  if ! grep -q 'logfile' /etc/dinit.d/elogind 2>/dev/null; then
    [ -f /etc/dinit.d/elogind ] && [ ! -f /etc/dinit.d/elogind.bak-chroot ] \
      && cp /etc/dinit.d/elogind /etc/dinit.d/elogind.bak-chroot
    cat > /etc/dinit.d/elogind <<'EOF'
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
  fi
  cat > /etc/dinit.d/logind <<'EOF'
type       = internal
depends-on = elogind
EOF
  ln -sfn ../elogind /etc/dinit.d/boot.d/elogind
  ln -sfn ../logind /etc/dinit.d/boot.d/logind
fi

if [ ! -s /etc/machine-id ]; then
  if command -v dbus-uuidgen >/dev/null 2>&1; then
    dbus-uuidgen --ensure=/etc/machine-id
  elif [ -r /proc/sys/kernel/random/uuid ]; then
    tr -d - < /proc/sys/kernel/random/uuid > /etc/machine-id
  else
    echo "00000000000000000000000000000000" > /etc/machine-id
  fi
fi

echo ">> boot.d:"
ls -la /etc/dinit.d/boot.d
echo ">> overrides em /etc/dinit.d (amostra):"
ls /etc/dinit.d/root-ro /etc/dinit.d/boot /etc/dinit.d/local.target 2>/dev/null
echo ">> fix-dinit-chroot OK"
INNER

chmod 755 "$INNER_FIX"
strip_crlf "$INNER_FIX"

$BB mountpoint -q "$ROOT/proc" 2>/dev/null || $BB mount -t proc proc "$ROOT/proc" 2>/dev/null || true
$BB mountpoint -q "$ROOT/dev" 2>/dev/null || $BB mount --bind /dev "$ROOT/dev" 2>/dev/null || true

echo ">> a aplicar overrides dinit (etc sobrescreve usr/lib)"
$BB chroot "$ROOT" /usr/bin/env -i \
  PATH=/usr/bin:/bin:/usr/sbin:/sbin HOME=/root \
  /bin/sh /root/fix-dinit-chroot-inner.sh

echo
if [ "${FIX_DINIT_QUIET:-0}" = 1 ]; then
  echo "OK — fix-dinit-chroot aplicado"
else
  echo "OK — agora:"
  echo "  /data/linux/linux-stop.sh"
  echo "  rmdir /data/linux/run/start.lock 2>/dev/null"
  echo "  /data/linux/linux-start.sh"
  echo "  /data/linux/linux-status.sh"
  echo "  # ou tudo: /data/linux/run-setup.sh"
fi
