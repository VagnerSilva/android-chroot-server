#!/bin/sh
# ============================================================
# setup-gpu-mediatek.sh — LEGACY / NAO UTILIZAR NO BOOTSTRAP
#
# Caminho antigo: ICD Vulkan Bionic directo + Zink.
# Falha tipica no Artix glibc: invalid ELF header.
#
# Use em vez disso:
#   /data/linux/run-setup-gpu-hybris.sh
#   (GLES-first + /opt/android-mali + libhybris)
#
# Este script sobrescreve /etc/artix-gpu.conf e gpu-*-run —
# NAO correr depois do setup hybris.
# ============================================================
set -e

echo "!! LEGACY: setup-gpu-mediatek — preferir run-setup-gpu-hybris.sh"
echo ">> setup GPU MediaTek (Vulkan ICD + Zink) [LEGACY]"

# --- deteccao MTK (best-effort; continua mesmo sem getprop) ---
HW=""
if command -v getprop >/dev/null 2>&1; then
  HW=$(getprop ro.hardware 2>/dev/null)
  PLAT=$(getprop ro.board.platform 2>/dev/null)
  [ -n "$PLAT" ] && HW="$HW $PLAT"
fi
MTK=0
echo "$HW" | grep -qiE 'mt[0-9]|mediatek|mtk' && MTK=1
ls /sys/module/mali_kbase >/dev/null 2>&1 && MTK=1
ls /sys/module/mali >/dev/null 2>&1 && MTK=1
ls /dev/mali* >/dev/null 2>&1 && MTK=1

if [ "$MTK" = 1 ]; then
  echo ">> MediaTek/Mali detetado ($HW)"
else
  echo "!! aviso: nao confirmei MediaTek — a continuar na mesma (binds + Zink)"
fi

echo ">> pacman: mesa-utils + vulkan (sem mesa>=26; preferir overlay mesa25)"
if [ -f /root/install-mesa25-android-mali.sh ]; then
  /bin/bash /root/install-mesa25-android-mali.sh || true
fi
pacman -Sy --noconfirm --needed --overwrite='*' \
  mesa-utils vulkan-icd-loader vulkan-tools libglvnd \
  || pacman -S --noconfirm --needed --overwrite='*' \
  mesa-utils vulkan-icd-loader vulkan-tools libglvnd

mkdir -p /usr/local/bin /etc/profile.d /etc/vulkan/icd.d /mnt/vendor /mnt/system

# --- localizar ICD / libs do vendor (binds) ---
VENDOR_LIB=""
for d in \
  /mnt/vendor/lib64 \
  /mnt/vendor/lib \
  /mnt/system/lib64 \
  /mnt/system/vendor/lib64 \
  /mnt/system/lib
do
  [ -d "$d" ] || continue
  if [ -z "$VENDOR_LIB" ]; then
    VENDOR_LIB="$d"
  else
    VENDOR_LIB="$VENDOR_LIB:$d"
  fi
done

ICD_JSON=""
ICD_SO=""

# JSON ICD Android
for j in \
  /mnt/vendor/etc/vulkan/icd.d/*.json \
  /mnt/system/etc/vulkan/icd.d/*.json \
  /mnt/vendor/lib64/egl/*.json \
  /mnt/vendor/lib/egl/*.json
do
  [ -f "$j" ] || continue
  # preferir mali / mediatek
  base=$(basename "$j")
  case "$base" in
    *mali*|*Mali*|*mtk*|*MTK*|*mediatek*)
      ICD_JSON="$j"
      break
      ;;
  esac
  [ -z "$ICD_JSON" ] && ICD_JSON="$j"
done

# .so Vulkan direta
for s in \
  /mnt/vendor/lib64/hw/vulkan.*.so \
  /mnt/vendor/lib/hw/vulkan.*.so \
  /mnt/vendor/lib64/egl/libGLES_mali.so \
  /mnt/vendor/lib64/libmali*.so* \
  /mnt/vendor/lib64/hw/vulkan.mali.so \
  /mnt/system/lib64/hw/vulkan.*.so
do
  [ -e "$s" ] || continue
  case "$s" in
    *mali*|*Mali*|*mtk*|*/vulkan.*)
      ICD_SO="$s"
      break
      ;;
  esac
  [ -z "$ICD_SO" ] && ICD_SO="$s"
done

# extrair library_path do JSON se existir
if [ -n "$ICD_JSON" ] && [ -z "$ICD_SO" ]; then
  # "library_path": "libfoo.so" ou caminho absoluto
  LP=$(sed -n 's/.*"library_path"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$ICD_JSON" | head -n1)
  if [ -n "$LP" ]; then
    case "$LP" in
      /*) [ -e "$LP" ] && ICD_SO="$LP" ;;
      *)
        for d in /mnt/vendor/lib64 /mnt/vendor/lib /mnt/system/lib64 /mnt/system/lib; do
          [ -e "$d/$LP" ] && ICD_SO="$d/$LP" && break
        done
        ;;
    esac
  fi
fi

OUT_ICD=/etc/vulkan/icd.d/mali-android.json
if [ -n "$ICD_SO" ]; then
  # caminho absoluto para o loader Linux
  cat > "$OUT_ICD" <<EOF
{
    "file_format_version": "1.0.0",
    "ICD": {
        "library_path": "$ICD_SO",
        "api_version": "1.3.0"
    }
}
EOF
  echo ">> ICD gerado: $OUT_ICD -> $ICD_SO"
elif [ -n "$ICD_JSON" ]; then
  cp "$ICD_JSON" "$OUT_ICD"
  echo ">> ICD copiado: $ICD_JSON -> $OUT_ICD"
else
  echo "!! nenhum ICD Vulkan Mali encontrado sob /mnt/vendor|/mnt/system"
  echo "   confirme binds no linux-start e reinicie o container"
  echo "   (gpu-check vai falhar ate haver ICD)"
fi

# guardar paths para wrappers
cat > /etc/artix-gpu.conf <<EOF
# gerado por setup-gpu-mediatek.sh — NAO exporta llvmpipe
GPU_VENDOR_LIB='$VENDOR_LIB'
GPU_ICD_FILE='$OUT_ICD'
GPU_ICD_SO='$ICD_SO'
EOF
chmod 644 /etc/artix-gpu.conf

# profile: so paths; NAO GALLIUM_DRIVER=llvmpipe
cat > /etc/profile.d/gpu-mediatek.sh <<'EOF'
# MediaTek GPU helpers (Zink via gpu-run). Sem llvmpipe aqui.
[ -f /etc/artix-gpu.conf ] && . /etc/artix-gpu.conf
if [ -n "${GPU_VENDOR_LIB:-}" ]; then
  case ":${LD_LIBRARY_PATH:-}:" in
    *":$GPU_VENDOR_LIB:"*) ;;
    *) export LD_LIBRARY_PATH="${GPU_VENDOR_LIB}${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" ;;
  esac
fi
if [ -f "${GPU_ICD_FILE:-}" ]; then
  export VK_DRIVER_FILES="$GPU_ICD_FILE"
  export VK_ICD_FILENAMES="$GPU_ICD_FILE"
fi
EOF
chmod 644 /etc/profile.d/gpu-mediatek.sh

# --- wrappers ---
cat > /usr/local/bin/gpu-vulkan-run <<'EOF'
#!/bin/sh
# Corre comando com ICD Vulkan Mali do vendor Android
CONF=/etc/artix-gpu.conf
[ -f "$CONF" ] && . "$CONF"

if [ -n "${GPU_VENDOR_LIB:-}" ]; then
  export LD_LIBRARY_PATH="${GPU_VENDOR_LIB}${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
fi
if [ -f "${GPU_ICD_FILE:-}" ]; then
  export VK_DRIVER_FILES="$GPU_ICD_FILE"
  export VK_ICD_FILENAMES="$GPU_ICD_FILE"
fi
# Bionic/Android libs por vezes precisam destes
export ADRENO_DEBUG="${ADRENO_DEBUG:-}"
unset GALLIUM_DRIVER
unset MESA_LOADER_DRIVER_OVERRIDE
unset LIBGL_ALWAYS_SOFTWARE

if [ $# -eq 0 ]; then
  echo "uso: gpu-vulkan-run <comando> [args...]"
  exit 1
fi
exec "$@"
EOF
chmod 755 /usr/local/bin/gpu-vulkan-run

cat > /usr/local/bin/gpu-run <<'EOF'
#!/bin/sh
# OpenGL via Mesa Zink → Vulkan ICD Mali (GPU real, nao CPU)
# uso: gpu-run glxgears | gpu-run glxinfo -B
export MESA_LOADER_DRIVER_OVERRIDE=zink
export GALLIUM_DRIVER=zink
export LIBGL_KOPPER_DRI2=1
# garantir que nao cai em software
unset LIBGL_ALWAYS_SOFTWARE
unset MESA_GL_VERSION_OVERRIDE

if [ $# -eq 0 ]; then
  echo "uso: gpu-run <comando> [args...]"
  exit 1
fi
exec /usr/local/bin/gpu-vulkan-run "$@"
EOF
chmod 755 /usr/local/bin/gpu-run

# alias pedido no plano (zink-run)
ln -sfn gpu-run /usr/local/bin/zink-run

echo
echo ">> GPU MediaTek setup OK (ficheiros/wrappers)"
echo "   wrappers: gpu-vulkan-run | gpu-run | zink-run"
echo "   teste:    /data/linux/gpu-check.sh"
echo
echo "!! NOTA: vulkan.mali.so do Android e Bionic;"
echo "   no Artix (glibc) o loader tipicamente falha (invalid ELF header)."
echo "   /dev/mali0 + bind vendor NAO bastam — falta userspace Linux ou libhybris."
if [ ! -d /mnt/vendor/lib64 ] && [ ! -d /mnt/vendor/lib ]; then
  echo
  echo "!! /mnt/vendor vazio — reinicie com linux-start.sh atualizado (binds vendor/system)"
fi
