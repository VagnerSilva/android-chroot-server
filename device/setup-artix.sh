#!/bin/sh
# ============================================================
# setup-artix.sh — corre DENTRO do chroot Artix (via run-setup)
# Prep: grupos Android, pacman, config sshd (porta/keys).
# Nao arranca sshd — isso e do fix-sshd-chroot apos stubs dinit.
# ============================================================
set -e

echo ">> setup Artix/dinit"

# grupos Android
if ! grep -q '^aid_inet:' /etc/group 2>/dev/null; then
  cat >> /etc/group <<'EOF'
aid_bt_admin:x:3001:root
aid_bt:x:3002:root
aid_inet:x:3003:root
aid_net_raw:x:3004:root
aid_net_admin:x:3005:root
aid_sdcard_rw:x:1015:root
aid_media_rw:x:1023:root
aid_everybody:x:9997:root
EOF
fi

# root e users comuns na rede
for u in root; do
  if id "$u" >/dev/null 2>&1; then
    usermod -aG aid_inet,aid_net_raw,aid_sdcard_rw "$u" 2>/dev/null || true
  fi
done

mkdir -p /mnt/android /run /tmp /usr/local/sbin /etc/pacman.d/hooks
chmod 1777 /tmp

# pacman 7+: sandbox Landlock/alpm ANTES de qualquer pacman -S
# (kernel Android sem Landlock — hang a 100% apos download)
if [ -f /usr/local/sbin/android-pacman-sandbox.sh ]; then
  /bin/sh /usr/local/sbin/android-pacman-sandbox.sh
else
  echo ">> android-pacman-sandbox.sh ausente — aplicar inline"
  if [ -f /etc/pacman.conf ]; then
    sed -i '/^# Android chroot: kernel sem Landlock$/d' /etc/pacman.conf
    sed -i '/^# Android chroot: kernel sem Landlock \/ sandbox alpm$/d' /etc/pacman.conf
    sed -i '/^DisableSandbox/d' /etc/pacman.conf
    sed -i '/^DownloadUser /d' /etc/pacman.conf
    sed -i '/^# DownloadUser /d' /etc/pacman.conf
    sed -i 's/^CheckSpace$/# CheckSpace/' /etc/pacman.conf
    sed -i '/^IgnorePkg /d' /etc/pacman.conf
    if grep -q '^\[options\]' /etc/pacman.conf; then
      awk '
        BEGIN { done=0 }
        /^\[options\]/ && !done {
          print
          print "# Android chroot: kernel sem Landlock / sandbox alpm"
          print "DisableSandbox"
          print "IgnorePkg = linux-aarch64 linux-aarch64-lts linux-aarch64-headers linux-firmware mkinitcpio mkinitcpio-busybox"
          done=1
          next
        }
        { print }
      ' /etc/pacman.conf > /etc/pacman.conf.tmp && mv /etc/pacman.conf.tmp /etc/pacman.conf
    fi
  fi
fi

# ARMtix: pacotes sem assinatura
if [ -f /etc/pacman.conf ]; then
  awk '
    BEGIN { repos["system"]=1; repos["world"]=1; repos["galaxy"]=1; repos["armtix"]=1 }
    /^\[/ {
      name=$0; gsub(/[\[\]]/,"",name)
      print
      if (name in repos) { print "SigLevel = Never"; inrepo=1; next }
      inrepo=0; next
    }
    inrepo && /^SigLevel/ { next }
    { print }
  ' /etc/pacman.conf > /etc/pacman.conf.tmp && mv /etc/pacman.conf.tmp /etc/pacman.conf
  echo ">> pacman: DisableSandbox + #CheckSpace + IgnorePkg + SigLevel=Never (ARMtix)"
fi

# mirrorlist ARMtix (nao usar mirrors x86)
if [ -f /data/linux/pacman.d/mirrorlist ]; then
  cp /data/linux/pacman.d/mirrorlist /etc/pacman.d/mirrorlist
elif [ -f /root/mirrorlist.armtix ]; then
  cp /root/mirrorlist.armtix /etc/pacman.d/mirrorlist
fi

# openssh (nucleo STRICT) — instalar se o rootfs base nao trouxe
if [ ! -x /usr/bin/sshd ]; then
  echo ">> openssh ausente — pacman -S openssh openssh-dinit"
  pacman -Sy --noconfirm --needed openssh openssh-dinit || {
    echo "!! falha a instalar openssh — mirrors/rede?"
    exit 1
  }
fi

# sshd: porta 2222 para nao colidir com servicos do telefone
mkdir -p /var/empty /run/sshd /etc/ssh /var/log/dinit /usr/local/sbin
chmod 755 /var/empty /run/sshd
find /var/empty -mindepth 1 -maxdepth 1 -exec rm -rf {} + 2>/dev/null || true
if [ -f /etc/ssh/sshd_config ]; then
  sed -i 's/^#\?Port .*/Port 2222/' /etc/ssh/sshd_config
  grep -q '^Port 2222' /etc/ssh/sshd_config || echo 'Port 2222' >> /etc/ssh/sshd_config
  sed -i 's/^#\?PermitRootLogin .*/PermitRootLogin yes/' /etc/ssh/sshd_config
  sed -i 's/^#\?PasswordAuthentication .*/PasswordAuthentication yes/' /etc/ssh/sshd_config
  grep -q '^PasswordAuthentication' /etc/ssh/sshd_config || echo 'PasswordAuthentication yes' >> /etc/ssh/sshd_config
  # PAM no chroot Android e fragil — Preferir auth interno do sshd
  sed -i 's/^#\?UsePAM .*/UsePAM no/' /etc/ssh/sshd_config
  grep -q '^UsePAM ' /etc/ssh/sshd_config || echo 'UsePAM no' >> /etc/ssh/sshd_config
fi

ssh-keygen -A 2>/dev/null || true
# Nao dinitctl enable/start sshd aqui: o unit stock ainda nao tem o
# wrapper chroot. run-setup aplica fix-dinit, reinicia e so depois
# fix-sshd-chroot — falhar ai, nao com um sshd a meio no passo 1.

# desativar / stub servicos de hardware que derrubam "boot" no chroot Android
for s in tty1 getty@tty1 udevd systemd-udevd modules-load \
  udev-settle udev-trigger modules early-modules.target kmod-static-nodes \
  cgroups fsck swap binfmt agetty getty early-keyboard.target \
  early-fs-pre.target early-fs-fstab.target early-fs-local.target login.target
do
  dinitctl disable "$s" 2>/dev/null || true
  rm -f "/etc/dinit.d/boot.d/$s" 2>/dev/null || true
done
# Se o host tiver o script, preferir stubs completos:
#   /data/linux/fix-dinit-chroot.sh

# glibc + libgcc/libstdc++: gcc-libs e meta no Arch novo; sem libgcc o chroot parte
echo ">> pacman -Sy glibc libgcc libstdc++"
pacman -Sy --noconfirm --needed glibc libgcc libstdc++ gcc-libs || \
  pacman -S --noconfirm glibc libgcc libstdc++ || {
  echo "!! falha a actualizar glibc/libgcc — mirrors/rede?"
  exit 1
}
[ -e /usr/lib/libgcc_s.so.1 ] || {
  echo "!! libgcc_s.so.1 ausente apos install libgcc"
  exit 1
}
ldd --version 2>/dev/null | head -n1 || true

# servicos que falham sem cgroups completos — patch chroot (sem run-in-cgroup)
if [ -f /etc/dinit.d/dbus ]; then
  [ -f /etc/dinit.d/dbus.bak-chroot ] || cp /etc/dinit.d/dbus /etc/dinit.d/dbus.bak-chroot
  grep -v '^run-in-cgroup' /etc/dinit.d/dbus > /tmp/dbus.new && mv /tmp/dbus.new /etc/dinit.d/dbus
fi
if [ -f /etc/dinit.d/dbus-pre ]; then
  cat > /etc/dinit.d/dbus-pre <<'EOF'
type         = scripted
command      = /usr/lib/dinit/pre/dbus
stop-command = /bin/true
after        = local.target
restart      = false
EOF
fi
mkdir -p /run/dbus /var/log/dinit /etc/dinit.d/boot.d
# dbus no boot; sshd fica para fix-dinit + fix-sshd (unit com wrapper)
[ -f /etc/dinit.d/dbus ] && ln -sfn ../dbus /etc/dinit.d/boot.d/dbus
echo ">> dbus: run-in-cgroup removido (chroot Android)"
# Nao arrancar dbus/sshd aqui — run-setup faz fix-* apos stubs + restart.

echo ">> setup concluido (prep). sshd/dbus sobem nos passos fix-* do run-setup"
