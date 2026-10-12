#!/system/bin/sh

. /data/linux/common.sh 2>/dev/null || . "$(dirname "$0")/../core/common.sh"

TEST_IMG="$BASE/rootfs-mesa26-test.img"
TEST_ROOT="$BASE/mnt-mesa26-test"
TEST_LOG="$BASE/mesa26-test-$(date +%Y%m%d-%H%M%S).log"
REUSE_TEST="${MESA26_TEST_REUSE:-0}"
SKIP_SYNC="${MESA26_TEST_SKIP_SYNC:-0}"
SOCK_DIR=/data/data/com.termux/files/usr/tmp/.X11-unix
SOCK_X0="$SOCK_DIR/X0"
LOOP=
MOUNTED_ROOT=0
MOUNTED_DEV=0
MOUNTED_BINDERFS=0
MOUNTED_PROC=0
MOUNTED_SYS=0
MOUNTED_PTS=0
MOUNTED_X11=0
MOUNTED_VENDOR=0

if [ "$(id -u)" != "0" ]; then
  echo "!! precisa ser root (su / KernelSU)" >&2
  exit 1
fi
if [ ! -f "$IMG" ]; then
  echo "!! imagem principal ausente: $IMG" >&2
  exit 1
fi
if [ "$REUSE_TEST" != 0 ] && [ "$REUSE_TEST" != 1 ]; then
  echo '!! MESA26_TEST_REUSE deve ser 0 ou 1' >&2
  exit 1
fi
if [ "$SKIP_SYNC" != 0 ] && [ "$SKIP_SYNC" != 1 ]; then
  echo '!! MESA26_TEST_SKIP_SYNC deve ser 0 ou 1' >&2
  exit 1
fi
if [ "$SKIP_SYNC" = 1 ] && [ "$REUSE_TEST" != 1 ]; then
  echo '!! MESA26_TEST_SKIP_SYNC=1 exige MESA26_TEST_REUSE=1' >&2
  exit 1
fi
if [ -e "$TEST_IMG" ] && [ "$REUSE_TEST" != 1 ]; then
  echo "!! imagem de teste ja existe; preserve-a ou remova-a manualmente: $TEST_IMG" >&2
  exit 1
fi
if [ ! -e "$TEST_IMG" ] && [ "$REUSE_TEST" = 1 ]; then
  echo "!! imagem de teste para reuso ausente: $TEST_IMG" >&2
  exit 1
fi

umask 077
[ -e "$TEST_LOG" ] && TEST_LOG="$BASE/mesa26-test-$(date +%Y%m%d-%H%M%S)-$$.log"
exec > "$TEST_LOG" 2>&1
echo ">> ensaio isolado Mesa 26: $(date)"
echo ">> imagem principal: $IMG (somente leitura/copia)"
echo ">> imagem de teste: $TEST_IMG"
echo ">> evidencias: $TEST_LOG"

# shellcheck disable=SC2329
cleanup() {
  [ "$MOUNTED_X11" = 1 ] && "$BB" umount "$TEST_ROOT/tmp/.X11-unix" 2>/dev/null || true
  [ "$MOUNTED_VENDOR" = 1 ] && "$BB" umount "$TEST_ROOT/vendor" 2>/dev/null || true
  [ "$MOUNTED_PTS" = 1 ] && "$BB" umount "$TEST_ROOT/dev/pts" 2>/dev/null || true
  [ "$MOUNTED_PROC" = 1 ] && "$BB" umount "$TEST_ROOT/proc" 2>/dev/null || true
  [ "$MOUNTED_SYS" = 1 ] && "$BB" umount "$TEST_ROOT/sys" 2>/dev/null || true
  [ "$MOUNTED_BINDERFS" = 1 ] && "$BB" umount "$TEST_ROOT/dev/binderfs" 2>/dev/null || true
  [ "$MOUNTED_DEV" = 1 ] && "$BB" umount "$TEST_ROOT/dev" 2>/dev/null || true
  [ "$MOUNTED_ROOT" = 1 ] && "$BB" umount "$TEST_ROOT" 2>/dev/null || true
  [ -n "$LOOP" ] && "$BB" losetup -d "$LOOP" 2>/dev/null || true
}
trap cleanup 0
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

run_mesa26() {
  "$BB" chroot "$TEST_ROOT" /usr/bin/env -i \
    HOME=/root TERM=linux ANDROID_DATA=/data ANDROID_ROOT=/opt/android-mali/system \
    ANDROID_MALI=/opt/android-mali HYBRIS_PREFIX=/opt/libhybris \
    HYBRIS_LINKER_DIR=/opt/libhybris/lib/libhybris/linker \
    HYBRIS_EGLPLATFORM_DIR=/opt/libhybris/lib/libhybris HYBRIS_EGLPLATFORM=null \
    HYBRIS_VULKANPLATFORM_DIR=/opt/libhybris/lib/libhybris HYBRIS_VULKANPLATFORM=null \
    HYBRIS_TLS_PATCH=vulkan.mali.so WRAPPER_VULKAN_PATH=/opt/android-mali/system/lib64/libvulkan.so \
    HYBRIS_LD_LIBRARY_PATH=/opt/android-mali/vendor/lib64/egl/mt6878:/opt/android-mali/vendor/lib64/hw/mt6878:/opt/android-mali/vendor/lib64:/opt/android-mali/system_ext/lib64:/opt/android-mali/system/lib64:/opt/android-mali/apex/com.android.vndk.v34/lib64:/opt/android-mali/apex/com.android.runtime/lib64/bionic:/opt/android-mali/apex/com.android.vndk.v34@1/lib64 \
    LD_LIBRARY_PATH=/usr/lib:/usr/lib64:/opt/libhybris/lib:/opt/libhybris/lib64:/opt/libhybris/lib/libhybris:/opt/libhybris/lib/libhybris/linker:/opt/android-mali/lib:/opt/android-mali/lib64 \
    LIBGL_DRIVERS_PATH=/usr/lib/dri MESA_LOADER_DRIVER_OVERRIDE=zink GALLIUM_DRIVER=zink \
    VK_DRIVER_FILES=/usr/share/vulkan/icd.d/wrapper_icd.aarch64.json \
    VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/wrapper_icd.aarch64.json \
    __EGL_VENDOR_LIBRARY_DIRS=/usr/share/glvnd/egl_vendor.d \
    PATH=/usr/local/sbin:/usr/local/bin:/usr/bin:/sbin:/bin "$@"
}

if [ "$REUSE_TEST" = 1 ]; then
  echo '>> reutilizando imagem de teste existente; nenhuma imagem sera sobrescrita'
else
  if ! sh /data/linux/backup-rootfs.sh "$TEST_IMG"; then
    echo "!! nao foi possivel criar a copia isolada"
    exit 1
  fi
fi
mkdir -p "$TEST_ROOT"
IMG=$TEST_IMG
# shellcheck disable=SC2034
ROOT=$TEST_ROOT
if ! mount_rootfs_rw; then
  echo "!! falha ao montar a imagem de teste"
  exit 1
fi
MOUNTED_ROOT=1
LOOP=${LOOP:-}

for path in dev proc sys; do
  mkdir -p "$TEST_ROOT/$path"
done
mkdir -p "$TEST_ROOT/dev/pts" "$TEST_ROOT/dev/binderfs" "$TEST_ROOT/tmp/.X11-unix"
if ! "$BB" mount --bind /dev "$TEST_ROOT/dev"; then
  echo "!! falha no bind de /dev"
  exit 1
fi
MOUNTED_DEV=1
if [ -d /dev/binderfs ]; then
  if "$BB" mount --rbind /dev/binderfs "$TEST_ROOT/dev/binderfs" 2>/dev/null \
    || "$BB" mount --bind /dev/binderfs "$TEST_ROOT/dev/binderfs"; then
    MOUNTED_BINDERFS=1
  else
    echo '!! falha ao disponibilizar binderfs na copia'
    exit 1
  fi
fi
if ! "$BB" mount -t proc proc "$TEST_ROOT/proc"; then
  echo "!! falha ao montar proc"
  exit 1
fi
MOUNTED_PROC=1
if ! "$BB" mount -t sysfs sysfs "$TEST_ROOT/sys"; then
  echo "!! falha ao montar sysfs"
  exit 1
fi
MOUNTED_SYS=1
if ! "$BB" mount -t devpts devpts "$TEST_ROOT/dev/pts"; then
  echo "!! falha ao montar devpts"
  exit 1
fi
MOUNTED_PTS=1

if [ -d "$TEST_ROOT/opt/android-mali/vendor" ]; then
  mkdir -p "$TEST_ROOT/vendor"
  if "$BB" mount --bind "$TEST_ROOT/opt/android-mali/vendor" "$TEST_ROOT/vendor"; then
    MOUNTED_VENDOR=1
    echo '>> Android Mali vendor ligado em /vendor somente na copia de teste'
  else
    echo '!! nao foi possivel ligar vendor do overlay em /vendor na copia'
    exit 1
  fi
fi

if [ -S "$SOCK_X0" ]; then
  if "$BB" mount --bind "$SOCK_DIR" "$TEST_ROOT/tmp/.X11-unix"; then
    MOUNTED_X11=1
    echo ">> Termux:X11 :0 ligado a copia"
  else
    echo '!! falha ao ligar socket Termux:X11'
  fi
else
  echo '!! Termux:X11 :0 indisponivel; testes de janela serao marcados como bloqueados'
fi

if [ ! -x "$TEST_ROOT/usr/bin/pacman" ]; then
  echo "!! pacman ausente na copia: ensaio impossivel"
  exit 1
fi

echo '>> IgnorePkg ativo em [options] da copia:'
IGNOREPKG=$(awk '
  /^[[:space:]]*\[options\][[:space:]]*$/ { options=1; next }
  /^\[/ { options=0 }
  options && /^[[:space:]]*IgnorePkg[[:space:]]*=/ { print }
' "$TEST_ROOT/etc/pacman.conf")
if [ -n "$IGNOREPKG" ]; then
  printf '%s\n' "$IGNOREPKG"
else
  echo '   (nenhum IgnorePkg ativo)'
fi

if [ -x "$TEST_ROOT/usr/bin/eglinfo" ]; then
  echo '>> baseline Mesa25 Zink EGL via current gpu-run overlay'
  "$BB" chroot "$TEST_ROOT" /usr/bin/env -i HOME=/root TERM=linux \
    PATH=/usr/local/sbin:/usr/local/bin:/usr/bin:/sbin:/bin GPU_USE_ZINK=1 \
    /usr/local/bin/gpu-run /usr/bin/eglinfo -p surfaceless \
    || echo '!! baseline Mesa25 EGL failed; comparison will be incomplete'
fi

if [ "$SKIP_SYNC" = 1 ]; then
  echo '>> sync ignorado explicitamente; candidata atual nao sera avaliada'
  echo '>> teste somente da versao ja instalada no clone'
else
  echo '>> sincronizando somente a base da copia de teste'
  if ! "$BB" chroot "$TEST_ROOT" /usr/bin/pacman -Sy --noconfirm; then
    echo 'DECISAO: BLOQUEADO, pacman -Sy falhou na copia; imagem principal intacta.'
    exit 1
  fi

  CANDIDATE=$("$BB" chroot "$TEST_ROOT" /usr/bin/pacman -Si mesa 2>/dev/null \
    | awk '$1 == "Version" { print $3; exit }')
  echo ">> versao candidata no repositorio: ${CANDIDATE:-indisponivel}"
  if ! printf '%s\n' "$CANDIDATE" | grep -Eq '(^|:)26\.'; then
    echo 'DECISAO: BLOQUEADO, repositorio nao oferece Mesa 26; imagem principal intacta.'
    exit 2
  fi

  echo '>> instalando mesa exclusivamente na copia'
  if ! "$BB" chroot "$TEST_ROOT" /usr/bin/pacman -S --noconfirm --needed mesa; then
    echo 'DECISAO: NO-GO, instalacao falhou na copia; imagem principal intacta.'
    exit 1
  fi
fi
INSTALLED=$("$BB" chroot "$TEST_ROOT" /usr/bin/pacman -Q mesa 2>/dev/null | awk 'NR == 1 { print $2 }')
echo ">> versao instalada: ${INSTALLED:-desconhecida}"
if ! printf '%s\n' "$INSTALLED" | grep -Eq '(^|:)26\.'; then
  echo 'DECISAO: NO-GO, a copia nao ficou com Mesa 26; imagem principal intacta.'
  exit 1
fi

RUNTIME_FAILURE=0
RUNTIME_BLOCKED=0
if [ -x "$TEST_ROOT/usr/bin/vulkaninfo" ]; then
  echo '>> vulkaninfo --summary via gpu-vulkan-run'
  "$BB" chroot "$TEST_ROOT" /usr/bin/env -i HOME=/root TERM=linux \
    PATH=/usr/local/sbin:/usr/local/bin:/usr/bin:/sbin:/bin \
    /usr/local/bin/gpu-vulkan-run /usr/bin/vulkaninfo --summary || RUNTIME_FAILURE=1
else
  echo '!! vulkaninfo ausente na copia'
  RUNTIME_BLOCKED=1
fi

if [ -x "$TEST_ROOT/usr/bin/eglinfo" ]; then
  echo '>> eglinfo -p surfaceless via Mesa26 libraries in /usr/lib (before overlay)'
  run_mesa26 /usr/bin/eglinfo -p surfaceless
  EGLINFO_RC=$?
  echo "eglinfo_exit=$EGLINFO_RC"
  [ "$EGLINFO_RC" -eq 0 ] || RUNTIME_FAILURE=1
else
  echo '!! eglinfo ausente na copia'
  RUNTIME_BLOCKED=1
fi

if [ "$MOUNTED_X11" = 1 ]; then
  if [ -x "$TEST_ROOT/usr/bin/glxinfo" ]; then
    echo '>> glxinfo -B via Mesa 26 Zink in /usr/lib/dri'
    run_mesa26 DISPLAY=:0 XDG_RUNTIME_DIR=/tmp /usr/bin/glxinfo -B
    GLXINFO_RC=$?
    echo "glxinfo_exit=$GLXINFO_RC"
    [ "$GLXINFO_RC" -eq 0 ] || RUNTIME_FAILURE=1
  else
    echo '!! glxinfo ausente na copia'
    RUNTIME_BLOCKED=1
  fi

  if [ -x "$TEST_ROOT/usr/bin/vkcube" ]; then
    echo '>> vkcube --wsi xcb --c 120 via gpu-vulkan-run'
    "$BB" timeout 30 "$BB" chroot "$TEST_ROOT" /usr/bin/env -i HOME=/root TERM=linux \
      DISPLAY=:0 XDG_RUNTIME_DIR=/tmp PATH=/usr/local/sbin:/usr/local/bin:/usr/bin:/sbin:/bin \
      /usr/local/bin/gpu-vulkan-run /usr/bin/vkcube --wsi xcb --c 120
    VKCUBE_RC=$?
    echo "vkcube_exit=$VKCUBE_RC"
    [ "$VKCUBE_RC" -eq 0 ] || RUNTIME_FAILURE=1
  else
    echo '!! vkcube ausente na copia'
    RUNTIME_BLOCKED=1
  fi
else
  echo 'BLOCKED: glxinfo/vkcube precisam de Termux:X11 :0; a imagem principal nao foi iniciada.'
  RUNTIME_BLOCKED=1
fi

if [ "$RUNTIME_FAILURE" -ne 0 ]; then
  echo 'DECISAO: NO-GO, teste de runtime falhou na copia; imagem principal intacta.'
  exit 1
fi
if [ "$RUNTIME_BLOCKED" -ne 0 ]; then
  echo 'DECISAO: INCONCLUSIVO, faltam ferramentas ou display para o teste completo; imagem principal intacta.'
  exit 3
fi
echo 'DECISAO: GO para revisao humana; validar logs e comportamento real antes de atualizar o rootfs principal.'
exit 0