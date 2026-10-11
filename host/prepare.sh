#!/system/bin/sh
# ============================================================
# prepare.sh — roda no aparelho como root apos adb push
# Instala scripts em /data/linux/ e corrige CRLF.
#
# NUNCA strip/chmod sob $DST/mnt ou rootfs.img (imagem Artix).
#
# sh /sdcard/Download/rootfs/host/prepare.sh
# ou: sh /data/local/tmp/rootfs/host/prepare.sh
# ============================================================

for C in /data/local/tmp/rootfs /sdcard/Download/rootfs /sdcard/Download; do
  if [ -f "$C/device/core/linux-start.sh" ] || [ -f "$C/device/linux-start.sh" ]; then
    SRC="$C"
    break
  fi
  if [ -f "$C/core/linux-start.sh" ] || [ -f "$C/linux-start.sh" ]; then
    SRC="$C"
    break
  fi
done
SRC="${SRC:-/data/local/tmp/rootfs}"
DST=/data/linux

echo ">> origem: $SRC"
echo ">> destino: $DST"

if [ "$(id -u)" != "0" ]; then
  echo "!! precisa ser root (su / KernelSU)."
  exit 1
fi

mkdir -p "$DST"

# device/ ou raiz plana; aceita a arvore categorizada e a estrutura antiga.
DEV="$SRC/device"
[ -d "$DEV" ] || DEV="$SRC"

# strip CRLF sem apagar a letra r (bug BusyBox: sed \r / tr '\r')
# NAO usar nome "f" aqui: em ash/mksh vars de funcao sao globais e
# sobrescrevem o "f" do loop for (causava chmod /data/linux//data/linux/...).
strip_crlf() {
  _sf="$1"
  [ -f "$_sf" ] || return 0
  CR=$(printf '\r')
  tr -d "$CR" < "$_sf" > "$_sf.__nocr" && mv -f "$_sf.__nocr" "$_sf"
}

if [ -d "$DEV/core" ]; then
  for category in core setup fix gpu user x11 deploy; do
    [ -d "$DEV/$category" ] || continue
    mkdir -p "$DST/$category"
    for src_file in "$DEV/$category"/*.sh; do
      [ -f "$src_file" ] || continue
      name=${src_file##*/}
      target="$DST/$category/$name"
      if ! cp "$src_file" "$target"; then
        echo "!! falha cp $src_file"
        exit 1
      fi
      if ! strip_crlf "$target" || ! chmod 755 "$target"; then
        echo "!! falha a preparar $target"
        exit 1
      fi
      if ! ln -sfn "$category/$name" "$DST/$name"; then
        echo "!! falha alias $DST/$name"
        exit 1
      fi
      echo " ok $DST/$category/$name + alias $DST/$name"
    done
  done
else
  # Compatibilidade com pacotes antigos que ainda enviam device/ plano.
  for src_file in "$DEV"/*.sh; do
    [ -f "$src_file" ] || continue
    name=${src_file##*/}
    if ! cp "$src_file" "$DST/$name" || ! strip_crlf "$DST/$name" || ! chmod 755 "$DST/$name"; then
      echo "!! falha a preparar $DST/$name"
      exit 1
    fi
    echo " ok $DST/$name"
  done
fi

# configs dinit (ficheiros de servico) — so em DST/dinit.d, nunca mnt/
if [ -d "$DEV/deploy/dinit.d" ] || [ -d "$DEV/dinit.d" ]; then
  DINIT_SRC="$DEV/deploy/dinit.d"
  [ -d "$DINIT_SRC" ] || DINIT_SRC="$DEV/dinit.d"
  mkdir -p "$DST/dinit.d"
  if ! cp -R "$DINIT_SRC/." "$DST/dinit.d/"; then
    echo "!! falha cp dinit.d/"
    exit 1
  fi
  find "$DST/dinit.d" -type f | while read -r f; do
    if ! strip_crlf "$f"; then
      echo "!! falha strip_crlf $f"
      exit 1
    fi
  done
  echo " ok dinit.d/"
fi

# mirrorlist ARMtix + ALARM — so em DST/pacman.d, nunca mnt/
if [ -d "$DEV/deploy/pacman.d" ] || [ -d "$DEV/pacman.d" ]; then
  PACMAN_SRC="$DEV/deploy/pacman.d"
  [ -d "$PACMAN_SRC" ] || PACMAN_SRC="$DEV/pacman.d"
  mkdir -p "$DST/pacman.d"
  if ! cp -R "$PACMAN_SRC/." "$DST/pacman.d/"; then
    echo "!! falha cp pacman.d/"
    exit 1
  fi
  find "$DST/pacman.d" -type f | while read -r f; do
    if ! strip_crlf "$f"; then
      echo "!! falha strip_crlf $f"
      exit 1
    fi
  done
  echo " ok pacman.d/"
fi

# companion Termux:X11 (loader.apk) — Android 14+ 
if [ -d "$DEV/deploy/termux-x11" ] || [ -d "$DEV/termux-x11" ]; then
  TERMUX_X11_SRC="$DEV/deploy/termux-x11"
  [ -d "$TERMUX_X11_SRC" ] || TERMUX_X11_SRC="$DEV/termux-x11"
  mkdir -p "$DST/termux-x11"
  cp -R "$TERMUX_X11_SRC/." "$DST/termux-x11/" 2>/dev/null || true
  echo " ok termux-x11/"
fi

# deps offline GPU hybris (runtime overlays — sem compile no device)
# SRC/deps (deploy) tem prioridade; fallback device/deps
DEPS_SRC=""
if [ -d "$SRC/deps" ]; then
  DEPS_SRC="$SRC/deps"
elif [ -d "$DEV/deps" ]; then
  DEPS_SRC="$DEV/deps"
fi
if [ -n "$DEPS_SRC" ]; then
  mkdir -p "$DST/deps"
  if ! cp -R "$DEPS_SRC/." "$DST/deps/"; then
    echo "!! falha cp deps/"
    exit 1
  fi
  echo " ok deps/"
  for _df in libc-hybris.so \
             mesa25-android-mali-25.1.2-arm64.tar.zst \
             libhybris-opt-arm64.tar.zst \
             sysvk-opt-arm64.tar.zst; do
    if [ -f "$DST/deps/$_df" ]; then
      ls -lh "$DST/deps/$_df"
    else
      echo " -- deps/$_df (ausente)"
    fi
  done
fi

# so topo de /data/linux — nao recursivo (evita mnt/ e rootfs.img)
chmod 755 "$DST"/*.sh 2>/dev/null || true

# Autostart KernelSU (service.d) — SKIP_AUTOSTART=1 para saltar
if [ "${SKIP_AUTOSTART:-0}" != 1 ] && [ -f "$DST/99-linux.sh" ]; then
  mkdir -p /data/adb/service.d
  if ! cp "$DST/99-linux.sh" /data/adb/service.d/99-linux.sh; then
    echo "!! falha a instalar autostart em /data/adb/service.d/99-linux.sh"
    exit 1
  fi
  strip_crlf /data/adb/service.d/99-linux.sh
  chmod 755 /data/adb/service.d/99-linux.sh
  echo " ok /data/adb/service.d/99-linux.sh (autostart)"
elif [ "${SKIP_AUTOSTART:-0}" = 1 ]; then
  echo " -- autostart saltado (SKIP_AUTOSTART=1)"
fi

TAR_DEFAULT=/data/local/tmp/armtix-dinit-20260921.tar.xz
TAR_URL=https://armtix.artixlinux.org/images/armtix-dinit-20260921.tar.xz
echo
echo "============================================================"
echo " Scripts em $DST"
echo
echo " Pre-requisito desktop: app Termux:X11 (com.termux.x11) — F-Droid/GitHub"
echo " Termux base (com.termux) NAO chega"
echo
echo " 1) Instale o modulo KernelSU (ksu-module/) e reboot"
echo " 2) Ambiente do zero (recomendado — tudo num comando):"
echo "      /data/linux/bootstrap.sh"
echo "      # install + start + dbus/elogind + user + XFCE + X11"
echo "      # terminal: pergunta criar utilizador (default S)"
echo "      # adb sem TTY:"
echo "      CREATE_USER=1 ARTIX_USER=<user> ARTIX_PASS='senha' /data/linux/bootstrap.sh"
echo "      # tarball: home Termux ou $TAR_DEFAULT"
echo "      # se faltar: download automatico de $TAR_URL"
echo " 3) Alternativa passo-a-passo:"
echo "      /data/linux/install-rootfs.sh"
echo "      /data/linux/linux-start.sh"
echo "      /data/linux/run-setup.sh              # so nucleo"
echo "      SETUP_FULL=1 /data/linux/run-setup.sh # nucleo+GPU+XFCE"
echo "      YES=1 /data/linux/wipe-chroot.sh"
echo " 4) Dia a dia:"
echo "      /data/linux/linux-status.sh"
echo "      /data/linux/linux-shell.sh"
echo "      /data/linux/gpu-desktop.sh        # desktop GPU (Zink) / 1a vez faz setup"
echo "      /data/linux/x11-start.sh / x11-stop.sh"
echo "      /data/linux/gpu-check.sh"
echo " 5) Autostart: instalado por prepare (service.d/99-linux.sh)"
echo "      # repor: /data/linux/install-autostart.sh"
echo "      # saltar: SKIP_AUTOSTART=1 prepare.sh"
echo "============================================================"
if [ -f "$TAR_DEFAULT" ]; then
  echo ">> tarball encontrado: $TAR_DEFAULT"
  ls -lh "$TAR_DEFAULT"
else
  echo ">> tarball ainda nao visto em: $TAR_DEFAULT"
fi
df -h /data | tail -n 1
